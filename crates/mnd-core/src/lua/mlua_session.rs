//! Реализация [`LuaSession`] поверх `mlua`. Только нативные сборки: см. [`crate::lua::session_stub`].
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};

use mlua::{Function, HookTriggers, Lua, LuaOptions, StdLib, Table, Value as LuaValue, VmState};
use serde_json::{Map, Value, json};

use crate::blocks::set_visible::{Mode as VisibilityMode, apply_mode};
use crate::executor::{ITEM_HIDDEN_VAR, ITEM_SOURCE_VAR, value_to_string};
use crate::models::QuestTable;
use crate::runtime::ScriptRuntime;

/// Сколько инструкций VM между двумя срабатываниями счётчика. Меньше — дороже
/// на каждом кадре, больше — грубее потолок.
const LUA_INSTRUCTION_CHUNK: u64 = 1000;

/// Потолок инструкций на один вызов блока `call_lua`. Без него
/// `while true do end` из скачанного квеста навечно вешает поток движка:
/// UI замирает, FFI-вызов не возвращается. 10 млн — это заведомо больше
/// любой разумной игровой формулы и ~0.1 с, то есть заметный, но не
/// убивающий игру тормоз вместо зависания.
const MAX_LUA_INSTRUCTIONS: u64 = 10_000_000;

/// Потолок вложенности при переносе значения между Lua и JSON. Циклическая
/// таблица (`t.self = t`) иначе уходит в бесконечную рекурсию, а она
/// заканчивается не ошибкой, а переполнением стека и abort процесса.
const MAX_LUA_VALUE_DEPTH: u32 = 32;

/// Очередь аудио-команд одного исполнения. Ключ совпадает с
/// `executor::push_audio_command`: клиент разбирает один и тот же канал и для
/// блоков, и для Lua.
const AUDIO_QUEUE_VAR: &str = "_internal_audio_queue";

/// Очередь внешних команд (`open_link`) — тот же ключ, что у блока.
const EXTERNAL_COMMANDS_VAR: &str = "_internal_external_commands";

/// Снимок состояния, с которым работает Lua в одном вызове блока.
#[derive(Clone, Default)]
struct LuaStateSnapshot {
    variables: Map<String, Value>,
    /// Таблицы: имя → `QuestTable.to_json()`.
    tables: Map<String, Value>,
}

/// Мост «Lua ↔ runtime»: хранится в сессии, заполняется на каждый вызов.
#[derive(Default)]
struct LuaBridge {
    snapshot: Option<LuaStateSnapshot>,
    /// Переход, запрошенный `core.go_to`. Отдельно от снимка: функция-триггер
    /// обычно ничего не возвращает, а уйти в узел ей надо уметь — у блока
    /// `go_to_node` для этого собственный возврат.
    transition: Option<String>,
}

/// Снимок доступен только во время вызова блока: вне движка (`snapshot == None`)
/// `core.*`-эффекты молча no-op, а не падают — Lua-функцию мог позвать и
/// посторонний код.
fn with_snapshot<T>(
    bridge: &Arc<Mutex<LuaBridge>>,
    f: impl FnOnce(&mut LuaStateSnapshot) -> T,
) -> Option<T> {
    let mut guard = bridge.lock().unwrap();
    guard.snapshot.as_mut().map(f)
}

impl LuaStateSnapshot {
    fn from_state(state: &dyn ScriptRuntime) -> Self {
        Self {
            variables: state.all_variables().clone(),
            tables: state
                .all_tables()
                .iter()
                .map(|(name, t)| (name.clone(), t.to_json()))
                .collect(),
        }
    }

    /// Очередь служебной переменной — аналог `executor::push_effect`, только на
    /// снимке: живой runtime получит значение тем же диффом, что и переменные.
    fn push_effect(&mut self, key: &str, value: Value) {
        let mut queue = match self.variables.remove(key) {
            Some(Value::Array(items)) => items,
            _ => Vec::new(),
        };
        queue.push(value);
        self.variables.insert(key.to_string(), Value::Array(queue));
    }

    /// Прямая запись служебной переменной (одноразовые слоты вроде громкости).
    fn set_effect(&mut self, key: &str, value: Value) {
        self.variables.insert(key.to_string(), value);
    }

    /// Карта переопределений контента `{itemId: значение}` — тот же канал, что
    /// у блоков `set_image` и `set_visible`.
    fn override_map(&mut self, key: &str) -> &mut Map<String, Value> {
        let entry = self
            .variables
            .entry(key.to_string())
            .or_insert_with(|| Value::Object(Map::new()));
        if !entry.is_object() {
            *entry = Value::Object(Map::new());
        }
        entry
            .as_object_mut()
            .expect("переопределения контента — объект")
    }

    /// Применить снимок к runtime: только изменённые ключи (дифф), чтобы
    /// не перезаписывать без нужды и не отмечать всё в dirty-наборах.
    fn apply_to(&self, state: &mut dyn ScriptRuntime) {
        for (k, v) in &self.variables {
            let changed = match state.get_variable(k) {
                Some(cur) => cur != v,
                None => true,
            };
            if changed {
                state.set_variable(k, v.clone());
            }
        }
        for (name, json) in &self.tables {
            let changed = match state.get_table(name) {
                Some(cur) => cur.to_json() != *json,
                None => true,
            };
            if changed {
                state.set_table(name, QuestTable::from_json(json));
            }
        }
    }
}

/// Lua-сессия квеста (L3A). Не `Send`/`Sync` — живёт в одном потоке движка.
pub struct LuaSession {
    lua: Lua,
    bridge: Arc<Mutex<LuaBridge>>,
    /// Счётчик инструкций, накопленных с начала текущего вызова блока.
    instructions: Arc<AtomicU64>,
}

impl LuaSession {
    pub fn new() -> Self {
        // Песочница: `ALL_SAFE` = все стандартные библиотеки, кроме `debug`
        // (mlua сам refuse-ит `debug` и отключает C-модули для `require`).
        // Опасные для хоста функции `os`/`io` обнуляем ниже в `install_core_api`.
        let lua =
            Lua::new_with(StdLib::ALL_SAFE, LuaOptions::default()).expect("создать Lua-состояние");
        let bridge = Arc::new(Mutex::new(LuaBridge::default()));
        let instructions = Arc::new(AtomicU64::new(0));

        // Глобальный хук (не thread-хук): он же достаётся coroutine-потокам,
        // созданным после установки. Ошибка из хук-колбэка mlua пробрасывает
        // её как обычную ошибку Lua, то есть блок просто завершается с
        // ошибкой вместо вечной зависки движка.
        let counter = instructions.clone();
        lua.set_global_hook(
            HookTriggers::new().every_nth_instruction(LUA_INSTRUCTION_CHUNK as u32),
            move |_lua, _debug| {
                let spent =
                    counter.fetch_add(LUA_INSTRUCTION_CHUNK, Ordering::Relaxed) + LUA_INSTRUCTION_CHUNK;
                if spent > MAX_LUA_INSTRUCTIONS {
                    Err(mlua::Error::runtime(format!(
                        "слишком много инструкций Lua (>{MAX_LUA_INSTRUCTIONS}) — похоже на бесконечный цикл"
                    )))
                } else {
                    Ok(VmState::Continue)
                }
            },
        )
        .expect("установить хук лимита инструкций");

        let session = Self {
            lua,
            bridge,
            instructions,
        };
        session.install_core_api();
        session
    }

    /// Зарегистрировать `core.*` (белый список; один раз при создании).
    fn install_core_api(&self) {
        let get_var = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(move |lua, name: String| -> Result<LuaValue, mlua::Error> {
                    let Some(snapshot) = &bridge.lock().unwrap().snapshot else {
                        return Ok(LuaValue::Nil);
                    };
                    let value = snapshot
                        .variables
                        .get(&name)
                        .cloned()
                        .unwrap_or(Value::Null);
                    json_to_lua(lua, &value)
                })
                .expect("create get_var")
        };
        let set_var = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, (name, value): (String, LuaValue)| -> Result<(), mlua::Error> {
                        if let Some(snapshot) = &mut bridge.lock().unwrap().snapshot {
                            snapshot.variables.insert(name, lua_to_json(value));
                        }
                        Ok(())
                    },
                )
                .expect("create set_var")
        };
        let get_table = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(move |lua, name: String| -> Result<LuaValue, mlua::Error> {
                    let Some(snapshot) = &bridge.lock().unwrap().snapshot else {
                        return Ok(LuaValue::Nil);
                    };
                    let value = snapshot.tables.get(&name).cloned().unwrap_or(Value::Null);
                    json_to_lua(lua, &value)
                })
                .expect("create get_table")
        };
        let set_table = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, (name, value): (String, LuaValue)| -> Result<(), mlua::Error> {
                        if let Some(snapshot) = &mut bridge.lock().unwrap().snapshot {
                            snapshot.tables.insert(name, lua_to_json(value));
                        }
                        Ok(())
                    },
                )
                .expect("create set_table")
        };

        let go_to = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let node = arg_text(args.first()).trim().to_string();
                        if node.is_empty() {
                            return Ok(false);
                        }
                        bridge.lock().unwrap().transition = Some(node);
                        Ok(true)
                    },
                )
                .expect("create go_to")
        };
        let play_sound = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let audio_id = arg_text(args.first());
                        if audio_id.is_empty() {
                            return Ok(false);
                        }
                        let volume = arg_num(args.get(1)).unwrap_or(1.0).clamp(0.0, 1.0);
                        Ok(pushed(
                            &bridge,
                            AUDIO_QUEUE_VAR,
                            json!({"type": "play_sound", "audio_id": audio_id, "volume": volume}),
                        ))
                    },
                )
                .expect("create play_sound")
        };
        let stop_sound = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let target = {
                            let raw = arg_text(args.first());
                            if raw.is_empty() {
                                "all".to_string()
                            } else {
                                raw
                            }
                        };
                        Ok(pushed(
                            &bridge,
                            AUDIO_QUEUE_VAR,
                            json!({"type": "stop_sound", "target": target}),
                        ))
                    },
                )
                .expect("create stop_sound")
        };
        let play_music = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let audio_id = arg_text(args.first());
                        if audio_id.is_empty() {
                            return Ok(false);
                        }
                        let opts = args.get(1);
                        let volume = arg_num(opts_field(opts, "volume").as_ref())
                            .unwrap_or(1.0)
                            .clamp(0.0, 1.0);
                        let loop_ = arg_bool(opts_field(opts, "loop").as_ref(), true);
                        let global = arg_bool(opts_field(opts, "global").as_ref(), false);
                        let queued = pushed(
                            &bridge,
                            AUDIO_QUEUE_VAR,
                            json!({
                                "type": "play_music",
                                "audio_id": audio_id,
                                "loop": loop_,
                                "volume": volume,
                                "global": global,
                            }),
                        );
                        // Слот активной скриптовой музыки: без него трек не
                        // возобновляется после загрузки сейва — блок `play_music`
                        // пишет те же три ключа.
                        with_snapshot(&bridge, |snapshot| {
                            snapshot.set_effect("_internal_active_script_bgm_id", json!(audio_id));
                            snapshot
                                .set_effect("_internal_active_script_bgm_volume", json!(volume));
                            snapshot.set_effect("_internal_active_script_bgm_loop", json!(loop_));
                        });
                        Ok(queued)
                    },
                )
                .expect("create play_music")
        };
        let stop_music = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, _args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let queued =
                            pushed(&bridge, AUDIO_QUEUE_VAR, json!({"type": "stop_music"}));
                        with_snapshot(&bridge, |snapshot| {
                            for key in [
                                "_internal_active_script_bgm_id",
                                "_internal_active_script_bgm_volume",
                                "_internal_active_script_bgm_loop",
                            ] {
                                snapshot.set_effect(key, Value::Null);
                            }
                        });
                        Ok(queued)
                    },
                )
                .expect("create stop_music")
        };
        let pause_resume = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let target = {
                            let raw = arg_text(args.first());
                            if raw.is_empty() {
                                "all".to_string()
                            } else {
                                raw
                            }
                        };
                        let action = {
                            let raw = arg_text(args.get(1));
                            if raw.is_empty() {
                                "toggle".to_string()
                            } else {
                                raw
                            }
                        };
                        Ok(pushed(
                            &bridge,
                            AUDIO_QUEUE_VAR,
                            json!({"type": "pause_resume", "target": target, "action": action}),
                        ))
                    },
                )
                .expect("create pause_resume")
        };
        let set_volume = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let target = {
                            let raw = arg_text(args.first());
                            if raw.is_empty() {
                                "contentAudio".to_string()
                            } else {
                                raw
                            }
                        };
                        let volume = arg_num(args.get(1)).unwrap_or(1.0).clamp(0.0, 1.0);
                        Ok(with_snapshot(&bridge, |snapshot| match target.as_str() {
                            "contentAudio" => {
                                snapshot.set_effect("_internal_node_content_volume", json!(volume));
                            }
                            "tagAudio" => {
                                snapshot.set_effect("_internal_tag_volume", json!(volume));
                            }
                            // Как блок: неизвестный адресат — ничего не меняем.
                            _ => {}
                        })
                        .is_some())
                    },
                )
                .expect("create set_volume")
        };
        let set_blur = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let blur = arg_num(args.first()).unwrap_or(10.0);
                        Ok(with_snapshot(&bridge, |snapshot| {
                            snapshot.set_effect("_internal_background_blur", json!(blur));
                        })
                        .is_some())
                    },
                )
                .expect("create set_blur")
        };
        let set_item_visible = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let item_id = arg_text(args.first()).trim().to_string();
                        let mode_raw = lua_to_json(args.get(1).cloned().unwrap_or(LuaValue::Nil));
                        let Some(mode) = VisibilityMode::from_raw(Some(&mode_raw)) else {
                            return Ok(false);
                        };
                        if item_id.is_empty() {
                            return Ok(false);
                        }
                        // apply_mode — та же функция, что у блока: «скрыть»
                        // сохраняет место, «убрать» схлопывает ряд, toggle умеет
                        // только прятать с сохранением места.
                        Ok(with_snapshot(&bridge, |snapshot| {
                            apply_mode(snapshot.override_map(ITEM_HIDDEN_VAR), &item_id, mode);
                        })
                        .is_some())
                    },
                )
                .expect("create set_item_visible")
        };
        let set_item_image = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let item_id = arg_text(args.first()).trim().to_string();
                        let source = arg_text(args.get(1)).trim().to_string();
                        if item_id.is_empty() || source.is_empty() {
                            return Ok(false);
                        }
                        Ok(with_snapshot(&bridge, |snapshot| {
                            snapshot
                                .override_map(ITEM_SOURCE_VAR)
                                .insert(item_id, json!(source));
                        })
                        .is_some())
                    },
                )
                .expect("create set_item_image")
        };
        let open_link = {
            let bridge = self.bridge.clone();
            self.lua
                .create_function(
                    move |_, args: mlua::Variadic<LuaValue>| -> Result<bool, mlua::Error> {
                        let url = arg_text(args.first()).trim().to_string();
                        if url.is_empty() {
                            return Ok(false);
                        }
                        // Белый список сети — тот же фильтр, что у блока.
                        if crate::network_safety::check_url(&url).is_err() {
                            return Ok(false);
                        }
                        Ok(pushed(
                            &bridge,
                            EXTERNAL_COMMANDS_VAR,
                            json!({"type": "open_link", "url": url}),
                        ))
                    },
                )
                .expect("create open_link")
        };

        let core = self.lua.create_table().expect("create core table");
        core.set("get_var", get_var).expect("core.get_var");
        core.set("set_var", set_var).expect("core.set_var");
        core.set("get_table", get_table).expect("core.get_table");
        core.set("set_table", set_table).expect("core.set_table");
        for (name, func) in [
            ("go_to", go_to),
            ("play_sound", play_sound),
            ("stop_sound", stop_sound),
            ("play_music", play_music),
            ("stop_music", stop_music),
            ("pause_resume", pause_resume),
            ("set_volume", set_volume),
            ("set_blur", set_blur),
            ("set_item_visible", set_item_visible),
            ("set_item_image", set_item_image),
            ("open_link", open_link),
        ] {
            core.set(name, func)
                .unwrap_or_else(|e| panic!("core.{name}: {e}"));
        }
        self.lua.globals().set("core", core).expect("globals core");

        self.neutralize_host_escape_hatches();
    }

    /// Обнуляет функции stdlib, которые могут исполнять/удалять что-либо на
    /// хосте. Изоляция mlua — whitelist библиотек, а не OS-песочница: без
    /// этого `os.execute("rm -rf …")` реально бы исполнился в процессе движка.
    fn neutralize_host_escape_hatches(&self) {
        let os = self.lua.globals().get::<mlua::Table>("os").ok();
        if let Some(os) = os {
            for name in ["execute", "exit", "remove", "rename"] {
                let _ = os.set(name, mlua::Nil);
            }
        }
        let io = self.lua.globals().get::<mlua::Table>("io").ok();
        if let Some(io) = io {
            let _ = io.set("popen", mlua::Nil);
        }
    }

    /// Исполнить исходник, не вызывая функцию — «подключение» скрипта.
    ///
    /// Так глобальный (квестовый) Lua-скрипт доживает до скриптов любой ноды:
    /// его `function …` становятся глобалами сессии. Изменения состояния,
    /// сделанные кодом верхнего уровня, применяются тем же диффом, что и в
    /// `call_function`.
    pub fn exec_source(
        &mut self,
        state: &mut dyn ScriptRuntime,
        script: &str,
    ) -> Result<(), String> {
        if script.trim().is_empty() {
            return Ok(());
        }
        self.instructions.store(0, Ordering::Relaxed);
        let snapshot = LuaStateSnapshot::from_state(state);
        *self.bridge.lock().unwrap() = LuaBridge {
            snapshot: Some(snapshot),
            transition: None,
        };
        let exec = self
            .lua
            .load(script)
            .exec()
            .map_err(|e| format!("script: {e}"));
        if let Some(snapshot) = self.bridge.lock().unwrap().snapshot.clone() {
            snapshot.apply_to(state);
        }
        self.bridge.lock().unwrap().snapshot = None;
        exec
    }

    /// Выполнить Lua-функцию блока `call_lua`.
    ///
    /// `script` — inline Lua-код (может быть пустым, если функция уже
    /// зарегистрирована в этой сессии). `args` — JSON-значение: массив
    /// распаковывается в аргументы функции, любое другое значение
    /// передаётся единственным аргументом.
    ///
    /// Возвращает переход, если функция вызвала `core.go_to` или вернула
    /// таблицу с ключом `node` / `go_to_node` (строка).
    pub fn call_function(
        &mut self,
        state: &mut dyn ScriptRuntime,
        script: Option<&str>,
        function_name: &str,
        args: Value,
    ) -> Result<Option<String>, String> {
        // 1. Снимок текущего состояния — то, что видит core.*.
        self.instructions.store(0, Ordering::Relaxed);
        let snapshot = LuaStateSnapshot::from_state(state);
        *self.bridge.lock().unwrap() = LuaBridge {
            snapshot: Some(snapshot),
            transition: None,
        };

        // 2. Inline-скрипт: повторный exec идемпотентен (функции
        //    переопределяются, состояние Lua вне core.* не сохраняется).
        if let Some(script) = script
            && !script.trim().is_empty()
        {
            self.lua
                .load(script)
                .exec()
                .map_err(|e| format!("script: {e}"))?;
        }

        // 3. Вызов функции.
        let func: Function = self
            .lua
            .globals()
            .get::<Function>(function_name)
            .map_err(|_| format!("функция '{function_name}' не найдена"))?;

        let call_args = args_to_multi(&self.lua, &args)?;
        let result: LuaValue = func
            .call(call_args)
            .map_err(|e| format!("{function_name}: {e}"))?;

        // 4. Применить изменения состояния диффом.
        let (applied, explicit_transition) = {
            let mut guard = self.bridge.lock().unwrap();
            (guard.snapshot.clone(), guard.transition.take())
        };
        if let Some(snapshot) = applied {
            snapshot.apply_to(state);
        }
        self.bridge.lock().unwrap().snapshot = None;

        // 5. Переход: явный `core.go_to` важнее возврата функции — автор мог
        //    вернуть таблицу с итогами, а уйти попросить отдельно.
        if explicit_transition.is_some() {
            return Ok(explicit_transition);
        }
        Ok(transition_from_lua_result(&result))
    }
}

impl Default for LuaSession {
    fn default() -> Self {
        Self::new()
    }
}

/// Append одной команды в очередь на снимке. `false` — вызов вне движка,
/// снимка нет, команде негде лечь.
fn pushed(bridge: &Arc<Mutex<LuaBridge>>, key: &str, command: Value) -> bool {
    with_snapshot(bridge, |snapshot| snapshot.push_effect(key, command)).is_some()
}

/// Аргумент как текст: число и булев `tostring`-ом, nil — пустая строка.
/// Блоки читают те же поля через `value_to_string`, поэтому разбор одинаков.
fn arg_text(value: Option<&LuaValue>) -> String {
    match value {
        None | Some(LuaValue::Nil) => String::new(),
        Some(v) => value_to_string(&lua_to_json(v.clone())),
    }
}

/// Аргумент как число: строку пробуем распарсить (автор мог подать «0.5»),
/// остальное — None, чтобы вызывающий подставил блоковый дефолт.
fn arg_num(value: Option<&LuaValue>) -> Option<f64> {
    match value? {
        LuaValue::Integer(i) => Some(*i as f64),
        LuaValue::Number(n) => Some(*n),
        LuaValue::String(s) => s.to_string_lossy().trim().parse().ok(),
        _ => None,
    }
}

/// Аргумент-переключатель: nil или неверный тип — дефолт блока.
fn arg_bool(value: Option<&LuaValue>, default: bool) -> bool {
    match value {
        Some(LuaValue::Boolean(b)) => *b,
        _ => default,
    }
}

/// Поле таблицы опций: `core.play_music('ид', { loop = false })`.
fn opts_field(value: Option<&LuaValue>, key: &str) -> Option<LuaValue> {
    match value? {
        LuaValue::Table(table) => table.get::<LuaValue>(key).ok(),
        _ => None,
    }
}

/// Переход из результата Lua-функции: таблица `{ node = "..." }` или
/// `{ go_to_node = "..." }`.
fn transition_from_lua_result(result: &LuaValue) -> Option<String> {
    let LuaValue::Table(t) = result else {
        return None;
    };
    t.get::<String>("node")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(|| t.get::<String>("go_to_node").ok())
        .filter(|s| !s.is_empty())
}

/// JSON-аргументы → MultiValue для Lua-вызова.
fn args_to_multi(lua: &Lua, args: &Value) -> Result<mlua::MultiValue, String> {
    match args {
        Value::Array(items) => {
            let mut multi = mlua::MultiValue::new();
            for item in items {
                multi.push_back(json_to_lua(lua, item).map_err(|e| e.to_string())?);
            }
            Ok(multi)
        }
        other => {
            let mut multi = mlua::MultiValue::new();
            multi.push_back(json_to_lua(lua, other).map_err(|e| e.to_string())?);
            Ok(multi)
        }
    }
}

/// serde_json → Lua value.
pub fn json_to_lua(lua: &Lua, v: &Value) -> Result<LuaValue, mlua::Error> {
    json_to_lua_depth(lua, v, 0)
}

fn json_to_lua_depth(lua: &Lua, v: &Value, depth: u32) -> Result<LuaValue, mlua::Error> {
    if depth > MAX_LUA_VALUE_DEPTH {
        return Ok(LuaValue::Nil);
    }
    Ok(match v {
        Value::Null => LuaValue::Nil,
        Value::Bool(b) => LuaValue::Boolean(*b),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                LuaValue::Integer(i)
            } else {
                LuaValue::Number(n.as_f64().unwrap_or(0.0))
            }
        }
        Value::String(s) => LuaValue::String(lua.create_string(s)?),
        Value::Array(items) => {
            let t = lua.create_table()?;
            for (i, item) in items.iter().enumerate() {
                t.raw_set(i + 1, json_to_lua_depth(lua, item, depth + 1)?)?;
            }
            LuaValue::Table(t)
        }
        Value::Object(map) => {
            let t = lua.create_table()?;
            for (k, val) in map {
                t.raw_set(k.clone(), json_to_lua_depth(lua, val, depth + 1)?)?;
            }
            LuaValue::Table(t)
        }
    })
}

/// Lua value → serde_json (таблицы: integer-ключи → массив, иначе объект).
pub fn lua_to_json(v: LuaValue) -> Value {
    lua_to_json_depth(v, 0)
}

fn lua_to_json_depth(v: LuaValue, depth: u32) -> Value {
    if depth > MAX_LUA_VALUE_DEPTH {
        return Value::Null;
    }
    match v {
        LuaValue::Nil => Value::Null,
        LuaValue::Boolean(b) => Value::Bool(b),
        LuaValue::Integer(i) => Value::from(i),
        LuaValue::Number(n) => Value::from(n),
        LuaValue::String(s) => Value::String(s.to_string_lossy().to_string()),
        LuaValue::Table(t) => table_to_json(&t, depth).unwrap_or(Value::Null),
        _ => Value::Null,
    }
}

fn table_to_json(t: &Table, depth: u32) -> Result<Value, mlua::Error> {
    let mut seq: Vec<(i64, Value)> = Vec::new();
    let mut map: Map<String, Value> = Map::new();
    let mut seq_only = true;

    for pair in t.pairs::<LuaValue, LuaValue>() {
        let (k, val) = pair?;
        match k {
            LuaValue::Integer(i) if i >= 1 && seq_only => {
                seq.push((i, lua_to_json_depth(val, depth + 1)));
            }
            LuaValue::String(s) => {
                seq_only = false;
                let key = s.to_string_lossy().to_string();
                map.insert(key, lua_to_json_depth(val, depth + 1));
            }
            _ => {
                seq_only = false;
            }
        }
    }

    if seq_only && !seq.is_empty() {
        seq.sort_by_key(|(i, _)| *i);
        Ok(Value::Array(seq.into_iter().map(|(_, v)| v).collect()))
    } else {
        Ok(Value::Object(map))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::InMemoryScriptRuntimeState;
    use serde_json::json;

    #[test]
    fn stdlib_available_but_debug_blocked() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        session
            .call_function(
                &mut s,
                Some(
                    "function probe() core.set_var('io_exists', io ~= nil) core.set_var('os_exists', os ~= nil) core.set_var('pkg_exists', package ~= nil) core.set_var('dbg_exists', debug ~= nil) core.set_var('require_ok', type(require) == 'function') end",
                ),
                "probe",
                Value::Null,
            )
            .unwrap();
        assert_eq!(s.get_variable("io_exists"), Some(&json!(true)));
        assert_eq!(s.get_variable("os_exists"), Some(&json!(true)));
        assert_eq!(s.get_variable("pkg_exists"), Some(&json!(true)));
        // debug — единственная исключённая библиотека.
        assert_eq!(s.get_variable("dbg_exists"), Some(&json!(false)));
        assert_eq!(s.get_variable("require_ok"), Some(&json!(true)));
    }

    #[test]
    fn host_escape_hatches_neutralized() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        session
            .call_function(
                &mut s,
                Some(
                    "function probe() core.set_var('os_execute', type(os.execute)) core.set_var('os_exit', type(os.exit)) core.set_var('os_remove', type(os.remove)) core.set_var('io_popen', type(io.popen)) core.set_var('io_open', type(io.open)) end",
                ),
                "probe",
                Value::Null,
            )
            .unwrap();
        assert_eq!(s.get_variable("os_execute"), Some(&json!("nil")));
        assert_eq!(s.get_variable("os_exit"), Some(&json!("nil")));
        assert_eq!(s.get_variable("os_remove"), Some(&json!("nil")));
        assert_eq!(s.get_variable("io_popen"), Some(&json!("nil")));
        // io.open оставляем — файлы разрешены.
        assert_eq!(s.get_variable("io_open"), Some(&json!("function")));
    }

    #[test]
    fn infinite_loop_is_interrupted_not_hung() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        let err = session
            .call_function(
                &mut s,
                Some("function spin() local i = 0 while true do i = i + 1 end end"),
                "spin",
                Value::Null,
            )
            .expect_err("бесконечный цикл должен прерваться, а не занять поток движка навсегда");
        assert!(err.contains("инструкц"), "не та ошибка: {err}");
    }

    #[test]
    fn ordinary_loop_still_runs() {
        // Потолок не должен ломать честные скрипты: 300k итераций — штатно.
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        session
            .call_function(
                &mut s,
                Some("function sum() local acc = 0 for i = 1, 300000 do acc = acc + i end core.set_var('acc', acc) end"),
                "sum",
                Value::Null,
            )
            .unwrap();
        assert_eq!(s.get_variable("acc"), Some(&json!(45_000_150_000_i64)));
    }

    #[test]
    fn cyclic_table_does_not_overflow_stack() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        session
            .call_function(
                &mut s,
                Some(
                    "function cyc() local t = { name = 'метка' } t.self = t core.set_var('cyc', t) end",
                ),
                "cyc",
                Value::Null,
            )
            .unwrap();

        let mut node = s.get_variable("cyc").cloned().unwrap();
        assert_eq!(node.get("name"), Some(&json!("метка")));
        // Цикл обрезается на потолке глубины: цепочка self конечна и
        // заканчивается null, а не abort процесса переполнением стека.
        for _ in 0..MAX_LUA_VALUE_DEPTH + 5 {
            let next = match node.get("self") {
                Some(v) if v.is_object() => v.clone(),
                _ => {
                    assert_eq!(node.get("self"), Some(&Value::Null));
                    return;
                }
            };
            node = next;
        }
        panic!("циклическая таблица развернулась глубже потолка");
    }

    #[test]
    fn core_table_roundtrip_preserves_structure() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        session
            .call_function(
                &mut s,
                Some(
                    "function mk() core.set_var('obj', { a = 1, b = 'x', c = { 10, 20 } }) return core.get_var('obj') end",
                ),
                "mk",
                Value::Null,
            )
            .unwrap();
        let obj = s.get_variable("obj").cloned().unwrap();
        assert_eq!(obj.get("a"), Some(&json!(1)));
        assert_eq!(obj.get("b"), Some(&json!("x")));
        assert_eq!(obj.get("c"), Some(&json!([10, 20])));
    }

    #[test]
    fn every_registered_core_function_is_offered_by_completion() {
        // Автодополнение и рантайм расходятся молча: проверка по живому
        // реестру, а не по второму списку в тесте.
        let session = LuaSession::new();
        let core: Table = session.lua.globals().get("core").expect("core таблица");
        let mut registered: Vec<String> = Vec::new();
        for pair in core.pairs::<String, LuaValue>() {
            let (name, _) = pair.expect("ключ core.*");
            registered.push(name);
        }
        registered.sort();
        let mut documented = crate::lua::completion::CORE_API.to_vec();
        documented.sort();
        assert_eq!(
            registered, documented,
            "core.* в рантайме и в автодополнении разъехались"
        );
    }

    #[test]
    fn core_effects_land_on_the_same_channels_as_blocks() {
        // Паритет проверяется не «Lua-функция существует», а тем, что клиент
        // получает побайтово ту же команду, что дала бы кнопка-блок.
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        let transition = session
            .call_function(
                &mut s,
                Some(
                    "function f() \
                         core.play_sound('hit', 0.4) \
                         core.play_music('boss_theme', { volume = 0.5, loop = false, global = true }) \
                         core.set_item_visible('btn', 'hide') \
                         core.set_item_image('pic', 'res/images/cat.png') \
                         core.set_volume('contentAudio', 0.3) \
                         core.set_blur(12) \
                         core.open_link('https://example.com/quest') \
                         core.go_to('узел-2') \
                     end",
                ),
                "f",
                Value::Null,
            )
            .expect("эффекты не должны ронять вызов");
        assert_eq!(transition.as_deref(), Some("узел-2"));

        assert_eq!(
            s.get_variable("_internal_audio_queue"),
            Some(&json!([
                {"type": "play_sound", "audio_id": "hit", "volume": 0.4},
                {"type": "play_music", "audio_id": "boss_theme", "loop": false, "volume": 0.5, "global": true},
            ]))
        );
        // Слот активной скриптовой музыки попадает в сейв — как у блока.
        assert_eq!(
            s.get_variable("_internal_active_script_bgm_id"),
            Some(&json!("boss_theme"))
        );
        assert_eq!(
            s.get_variable("_internal_active_script_bgm_volume"),
            Some(&json!(0.5))
        );
        assert_eq!(
            s.get_variable("_internal_active_script_bgm_loop"),
            Some(&json!(false))
        );

        assert_eq!(
            s.get_variable(ITEM_HIDDEN_VAR),
            Some(&json!({"btn": "hidden"}))
        );
        assert_eq!(
            s.get_variable(ITEM_SOURCE_VAR),
            Some(&json!({"pic": "res/images/cat.png"}))
        );
        assert_eq!(
            s.get_variable("_internal_node_content_volume"),
            Some(&json!(0.3))
        );
        // Число, не целое: блок пишет f64, и клиенту важен именно тип числа.
        assert_eq!(
            s.get_variable("_internal_background_blur"),
            Some(&json!(12.0))
        );
        assert_eq!(
            s.get_variable("_internal_external_commands"),
            Some(&json!([{"type": "open_link", "url": "https://example.com/quest"}]))
        );
    }

    #[test]
    fn core_set_item_visible_reuses_block_mode_semantics() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        session
            .call_function(
                &mut s,
                Some(
                    "function f() \
                         core.set_item_visible('a', 'gone') \
                         core.set_item_visible('b', 'переключить') \
                         core.set_item_visible('c', false) \
                         core.set_item_visible('d', 'мусор') \
                     end",
                ),
                "f",
                Value::Null,
            )
            .unwrap();
        let overrides = s.get_variable(ITEM_HIDDEN_VAR).cloned().unwrap();
        assert_eq!(overrides.get("a"), Some(&json!("gone")));
        // toggle прятает с сохранением места, а не схлопывает ряд.
        assert_eq!(overrides.get("b"), Some(&json!("hidden")));
        // Булево — старый формат блока: false значит «убран».
        assert_eq!(overrides.get("c"), Some(&json!("gone")));
        // Нераспознанный режим — ничего не записано, ровно как в блоке.
        assert_eq!(overrides.get("d"), None);
    }

    #[test]
    fn core_open_link_blocks_the_same_urls_the_block_blocks() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        session
            .call_function(
                &mut s,
                Some(
                    "function f() \
                         core.set_var('ok', core.open_link('http://127.0.0.1:8080/admin')) \
                         core.set_var('scheme', core.open_link('file:///etc/passwd')) \
                         core.set_var('good', core.open_link('https://example.com')) \
                     end",
                ),
                "f",
                Value::Null,
            )
            .unwrap();
        assert_eq!(s.get_variable("ok"), Some(&json!(false)));
        assert_eq!(s.get_variable("scheme"), Some(&json!(false)));
        assert_eq!(s.get_variable("good"), Some(&json!(true)));
        assert_eq!(
            s.get_variable("_internal_external_commands"),
            Some(&json!([{"type": "open_link", "url": "https://example.com"}])),
            "заблокированная ссылка не должна лечь в очередь"
        );
    }

    #[test]
    fn core_go_to_wins_over_returned_table() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        let transition = session
            .call_function(
                &mut s,
                Some("function f() core.go_to('явный') return { node = 'из возврата' } end"),
                "f",
                Value::Null,
            )
            .unwrap();
        assert_eq!(transition.as_deref(), Some("явный"));
    }

    #[test]
    fn lua_double_equal_numbers_not_flattened_to_int() {
        let mut session = LuaSession::new();
        let mut s = InMemoryScriptRuntimeState::default();
        session
            .call_function(
                &mut s,
                Some("function f(x) core.set_var('v', x) end"),
                "f",
                Value::from(2.5),
            )
            .unwrap();
        assert_eq!(s.get_variable("v"), Some(&json!(2.5)));
    }
}
