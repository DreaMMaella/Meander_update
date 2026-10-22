//! FFI-слой хоста плагинов (L3B).
//!
//! В отличие от [`crate::api::game_engine`], здесь **один** глобальный хост на
//! процесс: плагины живут дольше квеста (это установка, а не сессия), а их
//! Lua-состояние изолировано внутри каждого `PluginInstance`.
//!
//! Контракт границы — только строки JSON: хост не отдаёт Dart-объектов, а
//! плагин не может прислать исполняемый код (см. `mnd-plugin::spec`).
//!
//! Ответы на «изменение состояния» (`plugin_invoke_event`, `plugin_call`) —
//! один и тот же пакет, чтобы клиенту не приходилось различать проходы:
//!
//! ```json
//! {
//!   "event": "node_enter",
//!   "commands": [{"kind": "toast", "text": "…"}],
//!   "varWrites": {"hp": 9},
//!   "cancel": false,
//!   "logs": [{"pluginId": "…", "level": "info", "text": "…"}],
//!   "errors": ["…"],
//!   "notes": ["…"],
//!   "storages": {"плагин": {"ключ": …}}
//! }
//! ```
//!
//! `storages` содержит снимки только тех плагинов, которые в этом проходе
//! трогали `mnd.storage` — их и пишет обратно клиент.
//!
//! Poison: паника внутри хоста не уходит через FFI-границу (UB) — она
//! ловится, логируется в `/tmp/mnd_rust_panic.log`, и вызов возвращает
//! `{"error":"plugin_host_poisoned"}`. Восстановление — `plugin_reset`.

use std::sync::{Mutex, OnceLock};

use flutter_rust_bridge::frb;
use serde_json::{Map, Value};

use mnd_plugin::{CallContext, PluginHost};

/// Маркер: мьютекс хоста отравлен предыдущей паникой — продолжать нельзя.
const POISON_MARKER: &str = "{\"error\":\"plugin_host_poisoned\"}";

fn append_panic_log(msg: &str) {
    use std::io::Write;
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/mnd_rust_panic.log")
    {
        let _ = writeln!(file, "{msg}");
    }
}

fn log_poisoned(context: &str) {
    let msg = format!("[RUST] plugin_host: mutex poisoned during {context}; refusing to continue");
    eprintln!("{msg}");
    append_panic_log(&msg);
}

fn log_panic(context: &str, payload: &(dyn std::any::Any + Send)) {
    let detail = if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "(non-string panic payload)".to_string()
    };
    let msg = format!("[RUST] plugin_host: panicked during {context}: {detail}");
    eprintln!("{msg}");
    append_panic_log(&msg);
}

static HOST: OnceLock<Mutex<PluginHost>> = OnceLock::new();

fn host() -> &'static Mutex<PluginHost> {
    HOST.get_or_init(|| Mutex::new(PluginHost::new()))
}

/// Выполнить `f` под мьютексом хоста, превратив панику в JSON-ошибку.
fn with_host<T, F>(context: &str, f: F) -> Result<T, String>
where
    F: FnOnce(&mut PluginHost) -> T,
{
    let mut guard = match host().lock() {
        Ok(guard) => guard,
        Err(_poisoned) => {
            log_poisoned(context);
            return Err(POISON_MARKER.to_string());
        }
    };
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| f(&mut guard))) {
        Ok(result) => Ok(result),
        Err(payload) => {
            log_panic(context, &payload);
            Err(POISON_MARKER.to_string())
        }
    }
}

fn parse_json(raw: &str) -> Value {
    serde_json::from_str(raw).unwrap_or(Value::Null)
}

fn dump(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "{}".to_string())
}

/// Собрать [`CallContext`] из `{"questId","nodeId","vars","nowMs"}`.
///
/// `vars` обязан прожить дольше контекста — поэтому снимок живёт в вызывающем
/// теле, а заимствуется только `&Map`.
struct ContextInput {
    quest_id: String,
    node_id: String,
    vars: Map<String, Value>,
    now_ms: i64,
}

impl ContextInput {
    fn from_json(raw: &str) -> Self {
        let value = parse_json(raw);
        let now_ms = match value.get("nowMs") {
            Some(Value::Number(n)) => n.as_i64().unwrap_or(0),
            Some(Value::String(s)) => s.parse().unwrap_or(0),
            _ => 0,
        };
        Self {
            quest_id: string_field(&value, "questId"),
            node_id: string_field(&value, "nodeId"),
            vars: value
                .get("vars")
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default(),
            now_ms,
        }
    }

    fn call(&self) -> CallContext<'_> {
        CallContext {
            quest_id: &self.quest_id,
            node_id: &self.node_id,
            vars: &self.vars,
            now_ms: self.now_ms,
        }
    }
}

fn string_field(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

/// Сериализовать проход события в пакет для клиента.
fn dispatch_json(dispatch: &mnd_plugin::EventDispatch) -> Value {
    let outcomes: Vec<Value> = dispatch
        .outcomes
        .iter()
        .filter_map(|outcome| serde_json::to_value(outcome).ok())
        .collect();
    Value::Object(Map::from_iter([
        ("event".into(), Value::String(dispatch.event.clone())),
        ("outcomes".into(), Value::Array(outcomes)),
        ("commands".into(), Value::Array(dispatch.commands())),
        ("varWrites".into(), Value::Object(dispatch.var_writes())),
        ("cancel".into(), Value::Bool(dispatch.canceled())),
        (
            "logs".into(),
            serde_json::to_value(dispatch.logs()).unwrap_or(Value::Array(vec![])),
        ),
        (
            "notes".into(),
            Value::Array(dispatch.notes.iter().cloned().map(Value::String).collect()),
        ),
        (
            "errors".into(),
            Value::Array(dispatch.errors().into_iter().map(Value::String).collect()),
        ),
        (
            "storages".into(),
            Value::Object(Map::from_iter(
                dispatch
                    .outcomes
                    .iter()
                    .filter(|outcome| outcome.storage_dirty)
                    .map(|outcome| (outcome.plugin_id.clone(), Value::Null)),
            )),
        ),
    ]))
}

/// Заполнить `storages` снимками грязных плагинов (lock уже удерживается
/// вызывающим кодом — снимки берём до возврата из `with_host`).
fn attach_storages(host: &PluginHost, packet: &mut Value) {
    let Some(storages) = packet.get_mut("storages").and_then(Value::as_object_mut) else {
        return;
    };
    for id in storages.keys().cloned().collect::<Vec<_>>() {
        let snapshot = host.storage(&id).unwrap_or(Value::Null);
        storages.insert(id, snapshot);
    }
}

// ---------------------------------------------------------------------------
// Экспортируемые функции
// ---------------------------------------------------------------------------

/// Установить плагин. `manifest_json` — содержимое `plugin.json`,
/// `source` — содержимое файла точки входа, `storage_json` — снимок
/// хранилища (`{}` если его ещё нет).
///
/// Возвращает `{"ok":true,"id":"…"}` или `{"ok":false,"errors":[…]}` —
/// ошибки валидации собирается сразу несколько, чтобы манифест правился
/// за один проход.
pub fn plugin_register(manifest_json: String, source: String, storage_json: String) -> String {
    let storage = parse_json(&storage_json);
    let storage = storage.as_object().cloned().map(Value::Object);
    let result = with_host("register", move |host| {
        host.register(&manifest_json, &source, storage)
    });
    match result {
        Ok(Ok(id)) => dump(&Value::Object(Map::from_iter([
            ("ok".into(), Value::Bool(true)),
            ("id".into(), Value::String(id)),
        ]))),
        Ok(Err(error)) => dump(&Value::Object(Map::from_iter([
            ("ok".into(), Value::Bool(false)),
            (
                "errors".into(),
                Value::Array(error.0.into_iter().map(Value::String).collect()),
            ),
        ]))),
        Err(marker) => marker,
    }
}

/// Снять плагин. `true` — такой был.
#[frb(sync)]
pub fn plugin_unregister(plugin_id: String) -> bool {
    with_host("unregister", move |host| host.unregister(&plugin_id)).unwrap_or(false)
}

/// Манифесты установленных плагинов — экран «Плагины».
pub fn plugin_list() -> String {
    with_host("list", |host| dump(&Value::Array(host.manifests()))).unwrap_or_else(|marker| marker)
}

/// Типы контента всех плагинов: палитра редактора и рендер в плеере.
pub fn plugin_content_types() -> String {
    with_host("content_types", |host| {
        dump(&Value::Array(host.content_types()))
    })
    .unwrap_or_else(|marker| marker)
}

/// Слоты UI: `{pluginId,id,area,priority}`, отсортированы по области и приоритету.
pub fn plugin_slots() -> String {
    with_host("slots", |host| dump(&Value::Array(host.slots()))).unwrap_or_else(|marker| marker)
}

/// Разрешения плагина (для экрана подтверждения установки).
pub fn plugin_permissions(plugin_id: String) -> String {
    with_host("permissions", move |host| {
        dump(
            &host
                .permissions_of(&plugin_id)
                .map(|list| Value::Array(list.into_iter().map(Value::String).collect()))
                .unwrap_or(Value::Null),
        )
    })
    .unwrap_or_else(|marker| marker)
}

/// На какие события есть подписчики — плеер не дёргает хост в мёртвых точках.
pub fn plugin_active_hooks() -> String {
    with_host("active_hooks", |host| {
        dump(&Value::Array(
            host.active_hooks().into_iter().map(Value::String).collect(),
        ))
    })
    .unwrap_or_else(|marker| marker)
}

/// Пройти событие EventContract по подписанным плагинам.
///
/// `payload_json` — плоский JSON-объект события, `context_json` —
/// `{"questId","nodeId","vars","nowMs"}`.
pub fn plugin_invoke_event(event: String, payload_json: String, context_json: String) -> String {
    let payload = parse_json(&payload_json);
    let context = ContextInput::from_json(&context_json);
    with_host("invoke_event", move |host| {
        let dispatch = host.invoke_event(&event, payload.clone(), &context.call());
        let mut packet = dispatch_json(&dispatch);
        attach_storages(host, &mut packet);
        packet
    })
    .map(|packet| dump(&packet))
    .unwrap_or_else(|marker| marker)
}

/// Вызвать функцию плагина по имени: нажатие кнопки в UI-спеке, пункт меню.
pub fn plugin_call(
    plugin_id: String,
    function: String,
    args_json: String,
    context_json: String,
) -> String {
    let args = parse_json(&args_json);
    let context = ContextInput::from_json(&context_json);
    with_host("call", move |host| {
        let dispatch = host.call(&plugin_id, &function, args.clone(), &context.call());
        let mut packet = dispatch_json(&dispatch);
        attach_storages(host, &mut packet);
        packet
    })
    .map(|packet| dump(&packet))
    .unwrap_or_else(|marker| marker)
}

/// Текущее хранилище плагина (`null` — плагина нет).
pub fn plugin_storage(plugin_id: String) -> String {
    with_host("storage", move |host| {
        dump(&host.storage(&plugin_id).unwrap_or(Value::Null))
    })
    .unwrap_or_else(|marker| marker)
}

/// Сбросить хост: снять все плагины. Нужен после poison и при горячей
/// перезагрузке набора плагинов.
#[frb(sync)]
pub fn plugin_reset() -> bool {
    // Отравленный мьютекс — единственный случай, когда этот вызов вообще
    // нужен, а ветка `Err` лишь возвращала false: хост оставался мёртвым до
    // перезапуска процесса, хотя документация обещала восстановление здесь.
    // Забирать содержимое при poison безопасно — его всё равно заменяют
    // свежим `PluginHost::new()`. Флаг отравления хранится на самом мьютексе,
    // поэтому снимается явно: после `into_inner()` следующий `lock()` без
    // `clear_poison()` снова вернул бы маркер.
    let mutex = host();
    let mut guard = match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            log_poisoned("reset");
            poisoned.into_inner()
        }
    };
    *guard = PluginHost::new();
    drop(guard);
    mutex.clear_poison();
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, MutexGuard};

    /// Хост — глобальный на процесс, а тесты гоняются в параллельных потоках:
    /// без сериализации один тест видит чужие подписки на то же событие.
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn guard() -> MutexGuard<'static, ()> {
        TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Исход конкретного плагина из пакета.
    fn outcome_of(packet: &Value, plugin_id: &str) -> Value {
        packet["outcomes"]
            .as_array()
            .and_then(|list| {
                list.iter()
                    .find(|outcome| outcome["pluginId"].as_str() == Some(plugin_id))
            })
            .cloned()
            .unwrap_or(Value::Null)
    }

    fn manifest(id: &str, hooks: &[&str], permissions: &[&str]) -> String {
        serde_json::json!({
            "id": id,
            "name": "Test",
            "version": "1.0.0",
            "sdk": mnd_plugin::SDK_VERSION,
            "entry": "main.lua",
            "permissions": permissions,
            "hooks": hooks,
        })
        .to_string()
    }

    fn ok(result: &str) -> bool {
        parse_json(result).get("ok").and_then(Value::as_bool) == Some(true)
    }

    #[test]
    fn register_rejects_bad_manifest_with_all_errors_at_once() {
        let _guard = guard();
        let reply = plugin_register(
            manifest("ffi.bad.manifest", &["nope"], &["filesystem"]),
            "".into(),
            "{}".into(),
        );
        let value = parse_json(&reply);
        assert_eq!(value["ok"], Value::Bool(false));
        let errors = value["errors"].as_array().unwrap();
        assert!(errors.len() >= 2, "ожидались несколько ошибок: {errors:?}");
        assert_eq!(
            parse_json(&plugin_storage("ffi.bad.manifest".into())),
            Value::Null
        );
    }

    #[test]
    fn invoke_event_round_trip_returns_commands() {
        let _guard = guard();
        assert!(ok(&plugin_register(
            manifest("ffi.demo.hud", &["quest_start"], &["ui"]),
            "mnd.on('quest_start', function()\n  mnd.ui.toast('привет')\nend)\n".into(),
            "{}".into(),
        )));

        let hooks = parse_json(&plugin_active_hooks());
        assert!(hooks
            .as_array()
            .unwrap()
            .contains(&Value::String("quest_start".into())));

        let reply = plugin_invoke_event(
            "quest_start".into(),
            "{}".into(),
            r#"{"questId":"q1","nodeId":"n1","vars":{},"nowMs":1}"#.into(),
        );
        let value = parse_json(&reply);
        assert_eq!(value["event"], Value::String("quest_start".into()));
        let mine = outcome_of(&value, "ffi.demo.hud");
        assert_eq!(mine["error"], Value::Null);
        assert_eq!(mine["commands"][0]["kind"], Value::String("toast".into()));
        assert_eq!(mine["commands"][0]["text"], Value::String("привет".into()));
        assert!(plugin_unregister("ffi.demo.hud".into()));
    }

    #[test]
    fn call_returns_var_writes_and_dirty_storage() {
        let _guard = guard();
        assert!(ok(&plugin_register(
            manifest("ffi.demo.bump", &[], &["quest", "storage"]),
            "function bump()\n  mnd.vars.set('gold', (mnd.vars.get('gold') or 0) + 1)\n  mnd.storage.set('runs', (mnd.storage.get('runs') or 0) + 1)\nend\n".into(),
            "{}".into(),
        )));
        let reply = plugin_call(
            "ffi.demo.bump".into(),
            "bump".into(),
            "null".into(),
            r#"{"questId":"q1","vars":{"gold":10},"nowMs":2}"#.into(),
        );
        let value = parse_json(&reply);
        assert_eq!(outcome_of(&value, "ffi.demo.bump")["error"], Value::Null);
        assert_eq!(value["varWrites"]["gold"], Value::from(11));
        // Грязное хранилище отдаётся снимком, чтобы клиент записал его на диск.
        assert_eq!(value["storages"]["ffi.demo.bump"]["runs"], Value::from(1));
        assert_eq!(
            parse_json(&plugin_storage("ffi.demo.bump".into()))["runs"],
            Value::from(1)
        );
        assert!(plugin_unregister("ffi.demo.bump".into()));
    }

    #[test]
    fn sandbox_violation_surfaces_as_error_not_panic() {
        let _guard = guard();
        assert!(ok(&plugin_register(
            manifest("ffi.demo.evil", &["quest_start"], &["ui"]),
            "mnd.on('quest_start', function()\n  os.execute('ls')\nend)\n".into(),
            "{}".into(),
        )));
        let reply = plugin_invoke_event(
            "quest_start".into(),
            "{}".into(),
            r#"{"questId":"q1","vars":{},"nowMs":3}"#.into(),
        );
        let mine = outcome_of(&parse_json(&reply), "ffi.demo.evil");
        assert!(mine["commands"].as_array().unwrap().is_empty());
        assert!(mine["error"].as_str().unwrap().contains("os"));
        assert!(plugin_unregister("ffi.demo.evil".into()));
    }

    #[test]
    fn reset_recovers_a_poisoned_host() {
        let _guard = guard();

        // Паника под замком — тот же путь, что проходит реальный panic
        // внутри хоста: guard дропается при unwinding, мьютекс отравляется.
        let locked = host().lock().expect("хост до паники здоров");
        let panic_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _locked = locked;
            panic!("плагин паникует под замком");
        }));
        assert!(panic_result.is_err());

        assert_eq!(
            plugin_list(),
            POISON_MARKER,
            "после паники вызов обязан вернуть маркер отравления"
        );

        // Раньше reset на отравленном мьютексе возвращал false и хост умирал
        // до перезапуска процесса — несмотря на обещание в шапке модуля.
        assert!(plugin_reset(), "reset обязан снять poison");
        assert_ne!(plugin_list(), POISON_MARKER, "хост снова отвечает");

        // И вызовы действительно работают: плагин после reset регистрируется.
        assert!(ok(&plugin_register(
            manifest("ffi.after.reset", &["quest_start"], &[]),
            "mnd.on('quest_start', function() end)\n".into(),
            "{}".into(),
        )));
        assert!(plugin_unregister("ffi.after.reset".into()));
    }
}
