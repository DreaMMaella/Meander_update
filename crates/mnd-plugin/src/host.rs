//! Реестр плагинов: порядок вызовов, рассылка `mnd.emit` и агрегация
//! исходов в один ответ для клиента.
//!
//! Порядок обхода — по `plugin_id` ([`BTreeMap`]), а не по порядку установки:
//! так результат не зависит от того, в каком порядке пользователь ставил
//! плагины (`docs/event-contract.md` §5).

use std::collections::{BTreeMap, VecDeque};

use serde_json::{Map, Value};

use crate::events;
use crate::manifest::{ContentTypeDecl, PluginManifest};
use crate::runtime::{CallContext, InvocationOutcome, LogEntry, PluginError, PluginInstance};

/// Глубина разворота `mnd.emit`: сколько вложенных рассылок терпит хост.
pub const MAX_EMIT_DEPTH: u32 = 4;

/// Один проход события по всем подписанным плагинам.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct EventDispatch {
    pub event: String,
    /// Исходы в порядке обхода (по `plugin_id`), включая пустые.
    pub outcomes: Vec<InvocationOutcome>,
    /// Диагностика хоста: отброшенные рассылки, переполнение глубины. Не
    /// команды и не часть какого-либо плагина.
    pub notes: Vec<String>,
}

impl EventDispatch {
    /// Отменил ли хоть один плагин дефолтное поведение события.
    pub fn canceled(&self) -> bool {
        events::is_cancelable(&self.event) && self.outcomes.iter().any(|o| o.cancel)
    }

    /// Нечего применять — можно пропустить проход через клиент.
    pub fn is_empty(&self) -> bool {
        self.notes.is_empty()
            && self.outcomes.iter().all(|outcome| {
                outcome.commands.is_empty()
                    && outcome.var_writes.is_empty()
                    && outcome.logs.is_empty()
                    && !outcome.cancel
                    && outcome.error.is_none()
            })
    }

    /// Команды всех плагинов в порядке обхода — то, что исполняет клиент.
    pub fn commands(&self) -> Vec<Value> {
        self.outcomes
            .iter()
            .flat_map(|outcome| outcome.commands.iter().cloned())
            .collect()
    }

    /// Объединённые изменения переменных: поздний плагин перекрывает раннего.
    pub fn var_writes(&self) -> Map<String, Value> {
        let mut merged = Map::new();
        for outcome in &self.outcomes {
            merged.extend(outcome.var_writes.clone());
        }
        merged
    }

    pub fn logs(&self) -> Vec<LogEntry> {
        self.outcomes
            .iter()
            .flat_map(|outcome| outcome.logs.iter().cloned())
            .collect()
    }

    pub fn errors(&self) -> Vec<String> {
        self.outcomes
            .iter()
            .filter_map(|outcome| outcome.error.clone())
            .collect()
    }
}

/// Хост плагинов. I/O не делает и на движок не ссылается: вход — данные,
/// выход — команды.
#[derive(Default)]
pub struct PluginHost {
    plugins: BTreeMap<String, PluginInstance>,
}

impl PluginHost {
    pub fn new() -> Self {
        Self::default()
    }

    /// Установить плагин: `plugin.json` + код точки входа + снимок хранилища.
    /// Дубликат `id` отклоняется — молча перезаписать существующий плагин
    /// было бы слишком весело.
    pub fn register(
        &mut self,
        manifest_json: &str,
        source: &str,
        storage: Option<Value>,
    ) -> Result<String, PluginError> {
        let manifest = PluginManifest::from_json(manifest_json).map_err(PluginError)?;
        let id = manifest.id.clone();
        if self.plugins.contains_key(&id) {
            return Err(PluginError(vec![format!("плагин '{id}' уже установлен")]));
        }
        let instance = PluginInstance::new(manifest, source, storage)?;
        self.plugins.insert(id.clone(), instance);
        Ok(id)
    }

    pub fn unregister(&mut self, plugin_id: &str) -> bool {
        self.plugins.remove(plugin_id).is_some()
    }

    pub fn contains(&self, plugin_id: &str) -> bool {
        self.plugins.contains_key(plugin_id)
    }

    pub fn len(&self) -> usize {
        self.plugins.len()
    }

    pub fn is_empty(&self) -> bool {
        self.plugins.is_empty()
    }

    /// Установленные id в порядке обхода.
    pub fn plugin_ids(&self) -> Vec<String> {
        self.plugins.keys().cloned().collect()
    }

    /// Проход события по подписанным плагинам, с разворотом очереди
    /// `mnd.emit` (глубина ограничена [`MAX_EMIT_DEPTH`]).
    pub fn invoke_event(
        &mut self,
        event: &str,
        payload: Value,
        context: &CallContext,
    ) -> EventDispatch {
        let mut dispatch = EventDispatch {
            event: event.to_string(),
            ..Default::default()
        };
        if !events::is_declareable(event) {
            dispatch.notes.push(format!(
                "события '{event}' нет в контракте — проход пропущен"
            ));
            return dispatch;
        }

        // (событие, payload, кто разослал, глубина)
        let mut queue = VecDeque::from([(event.to_string(), payload, None, 0u32)]);
        while let Some((event, payload, source, depth)) = queue.pop_front() {
            if depth > MAX_EMIT_DEPTH {
                dispatch.notes.push(format!(
                    "'{event}' отброшено: глубина рассылок превысила {MAX_EMIT_DEPTH}"
                ));
                continue;
            }
            if depth > 0 && !events::is_declareable(&event) {
                dispatch.notes.push(format!("рассылка '{event}' отклонена"));
                continue;
            }
            for (id, plugin) in self.plugins.iter_mut() {
                // `mnd.emit` адресован другим плагинам: автор события не должен
                // зацикливать сам себя.
                if Some(id.as_str()) == source.as_deref() || !plugin.subscribes_to(&event) {
                    continue;
                }
                let outcome = plugin.invoke_event(&event, payload.clone(), context);
                for emitted in &outcome.emits {
                    queue.push_back((
                        emitted.event.clone(),
                        emitted.payload.clone(),
                        Some(id.clone()),
                        depth + 1,
                    ));
                }
                dispatch.outcomes.push(outcome);
            }
        }
        dispatch
    }

    /// Вызвать функцию конкретного плагина (кнопка слота, пункт меню, тип
    /// контента). Возвращает тот же [`EventDispatch`]: первым идёт исход
    /// адресата, затем — исходы плагинов, до которых дошёл `mnd.emit`
    /// (глубина ограничена, как в `invoke_event`).
    pub fn call(
        &mut self,
        plugin_id: &str,
        function: &str,
        args: Value,
        context: &CallContext,
    ) -> EventDispatch {
        let Some(plugin) = self.plugins.get_mut(plugin_id) else {
            return EventDispatch {
                event: format!("call:{function}"),
                outcomes: vec![InvocationOutcome::failed(
                    plugin_id,
                    format!("плагин '{plugin_id}' не установлен"),
                )],
                notes: Vec::new(),
            };
        };
        let outcome = plugin.call_function(function, args, context);
        let mut dispatch = EventDispatch {
            event: format!("call:{function}"),
            outcomes: vec![outcome.clone()],
            notes: Vec::new(),
        };
        let mut queue: VecDeque<(String, Value, u32)> = outcome
            .emits
            .iter()
            .map(|emitted| (emitted.event.clone(), emitted.payload.clone(), 1))
            .collect();
        while let Some((event, payload, depth)) = queue.pop_front() {
            if depth > MAX_EMIT_DEPTH {
                dispatch.notes.push(format!(
                    "'{event}' отброшено: глубина рассылок превысила {MAX_EMIT_DEPTH}"
                ));
                continue;
            }
            for (id, other) in self.plugins.iter_mut() {
                if id == plugin_id || !other.subscribes_to(&event) {
                    continue;
                }
                let nested = other.invoke_event(&event, payload.clone(), context);
                for emitted in &nested.emits {
                    queue.push_back((emitted.event.clone(), emitted.payload.clone(), depth + 1));
                }
                dispatch.outcomes.push(nested);
            }
        }
        dispatch
    }

    /// Хранилище плагина для персистентности.
    pub fn storage(&self, plugin_id: &str) -> Option<Value> {
        self.plugins.get(plugin_id).map(PluginInstance::storage)
    }

    /// Снимки хранилищ всех плагинов: `{ pluginId: {…} }`.
    pub fn storages(&self) -> Map<String, Value> {
        self.plugins
            .iter()
            .map(|(id, plugin)| (id.clone(), plugin.storage()))
            .collect()
    }

    /// Типы контента всех плагинов — клиент строит по ним палитру и формы.
    pub fn content_types(&self) -> Vec<Value> {
        self.plugins
            .values()
            .flat_map(|plugin| {
                let manifest = plugin.manifest();
                manifest
                    .content_types
                    .iter()
                    .map(move |ct| content_type_json(manifest, ct))
            })
            .collect()
    }

    /// Слоты всех плагинов: порядок — область, затем `priority`, затем id.
    pub fn slots(&self) -> Vec<Value> {
        let mut slots: Vec<(String, i32, String, String)> = self
            .plugins
            .iter()
            .flat_map(|(id, plugin)| {
                plugin.manifest().slots.iter().map(move |slot| {
                    (
                        slot.area.clone(),
                        slot.priority,
                        id.clone(),
                        slot.id.clone(),
                    )
                })
            })
            .collect();
        slots.sort();
        slots
            .into_iter()
            .map(|(area, priority, plugin_id, id)| {
                Value::Object(Map::from_iter([
                    ("pluginId".into(), Value::String(plugin_id)),
                    ("id".into(), Value::String(id)),
                    ("area".into(), Value::String(area)),
                    ("priority".into(), Value::from(priority)),
                ]))
            })
            .collect()
    }

    /// Манифесты для экрана «Плагины».
    pub fn manifests(&self) -> Vec<Value> {
        self.plugins
            .values()
            .filter_map(|plugin| serde_json::to_value(plugin.manifest()).ok())
            .collect()
    }

    pub fn permissions_of(&self, plugin_id: &str) -> Option<Vec<String>> {
        self.plugins.get(plugin_id).map(|plugin| {
            plugin
                .policy()
                .permissions()
                .iter()
                .map(|permission| permission.name().to_string())
                .collect()
        })
    }

    /// На какие события движка отвечает хоть один плагин — клиент не дёргает
    /// хост в точках, где слушателей нет.
    pub fn active_hooks(&self) -> Vec<String> {
        events::EVENTS
            .iter()
            .filter(|event| {
                self.plugins
                    .values()
                    .any(|plugin| plugin.subscribes_to(event))
            })
            .map(|event| event.to_string())
            .collect()
    }
}

fn content_type_json(manifest: &PluginManifest, content_type: &ContentTypeDecl) -> Value {
    let mut object = Map::new();
    object.insert("pluginId".into(), Value::String(manifest.id.clone()));
    object.insert(
        "type".into(),
        Value::String(manifest.content_type_id(&content_type.id)),
    );
    object.insert("name".into(), Value::String(content_type.name.clone()));
    if let Some(description) = &content_type.description {
        object.insert("description".into(), Value::String(description.clone()));
    }
    if let Some(icon) = &content_type.icon {
        object.insert("icon".into(), Value::String(icon.clone()));
    }
    object.insert(
        "fields".into(),
        serde_json::to_value(&content_type.fields).unwrap_or(Value::Array(vec![])),
    );
    object.insert(
        "preview".into(),
        content_type.preview.clone().unwrap_or(Value::Null),
    );
    Value::Object(object)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::LogLevel;
    use serde_json::json;

    fn manifest_json(id: &str, permissions: &[&str], hooks: &[&str]) -> String {
        let mut object = Map::from_iter([
            ("id".into(), Value::String(id.into())),
            ("name".into(), Value::String(id.into())),
            ("version".into(), Value::String("1.0.0".into())),
            ("sdk".into(), Value::String(crate::SDK_VERSION.into())),
            ("entry".into(), Value::String("main.lua".into())),
        ]);
        if !permissions.is_empty() {
            object.insert(
                "permissions".into(),
                Value::Array(
                    permissions
                        .iter()
                        .map(|p| Value::String((*p).into()))
                        .collect(),
                ),
            );
        }
        if !hooks.is_empty() {
            object.insert(
                "hooks".into(),
                Value::Array(hooks.iter().map(|h| Value::String((*h).into())).collect()),
            );
        }
        Value::Object(object).to_string()
    }

    fn context() -> CallContext<'static> {
        static EMPTY: std::sync::OnceLock<Map<String, Value>> = std::sync::OnceLock::new();
        CallContext {
            quest_id: "q",
            node_id: "start",
            vars: EMPTY.get_or_init(Map::new),
            now_ms: 0,
        }
    }

    fn install(
        host: &mut PluginHost,
        id: &str,
        permissions: &[&str],
        hooks: &[&str],
        source: &str,
    ) {
        host.register(&manifest_json(id, permissions, hooks), source, None)
            .unwrap();
    }

    #[test]
    fn registration_rejects_duplicate_id_and_broken_manifest() {
        let mut host = PluginHost::new();
        install(&mut host, "com.example.a", &[], &[], "function f() end");
        let error = host
            .register(&manifest_json("com.example.a", &[], &[]), "", None)
            .expect_err("дубликат");
        assert!(error.0[0].contains("уже установлен"), "{error:?}");

        let error = host
            .register(r#"{ "id": "nope" }"#, "", None)
            .expect_err("сломанный манифест");
        assert!(!error.0.is_empty());
        assert_eq!(host.len(), 1);
        assert!(host.contains("com.example.a"));
    }

    #[test]
    fn events_dispatch_in_plugin_id_order_not_install_order() {
        let mut host = PluginHost::new();
        // «b» ставим первым — порядок обхода должен быть все равно a→b
        install(
            &mut host,
            "com.example.b",
            &["quest"],
            &["node_enter"],
            "function on_node_enter() mnd.vars.set('order', 'b') end",
        );
        install(
            &mut host,
            "com.example.a",
            &["quest"],
            &["node_enter"],
            "function on_node_enter() mnd.vars.set('order', 'a') end",
        );
        let dispatch = host.invoke_event("node_enter", json!({ "nodeId": "start" }), &context());
        let ids: Vec<&str> = dispatch
            .outcomes
            .iter()
            .map(|outcome| outcome.plugin_id.as_str())
            .collect();
        assert_eq!(ids, vec!["com.example.a", "com.example.b"]);
        // поздний перекрывает раннего, но отработали оба
        assert_eq!(dispatch.var_writes().get("order"), Some(&json!("b")));
    }

    #[test]
    fn only_subscribers_are_called_and_unknown_events_are_skipped_with_note() {
        let mut host = PluginHost::new();
        install(
            &mut host,
            "com.example.a",
            &["quest"],
            &["item_press"],
            "function on_node_enter() mnd.vars.set('boom', true) end",
        );
        let dispatch = host.invoke_event("node_enter", json!({}), &context());
        assert!(dispatch.outcomes.is_empty());
        assert!(dispatch.is_empty());

        let dispatch = host.invoke_event("nope", json!({}), &context());
        assert_eq!(dispatch.notes.len(), 1);
        assert!(dispatch.notes[0].contains("нет в контракте"));
    }

    #[test]
    fn emit_reaches_other_plugins_but_not_the_author() {
        let mut host = PluginHost::new();
        install(
            &mut host,
            "com.example.a",
            &["quest", "events"],
            &["node_enter", "custom.ping"],
            r#"function on_node_enter()
                 mnd.emit('custom.ping', { n = 1 })
               end
               mnd.on('custom.ping', function() mnd.vars.set('aSawOwn', true) end)"#,
        );
        install(
            &mut host,
            "com.example.b",
            &["quest"],
            &["custom.ping"],
            "mnd.on('custom.ping', function(p) mnd.vars.set('bGotN', p.n) end)",
        );
        let dispatch = host.invoke_event("node_enter", json!({}), &context());
        let merged = dispatch.var_writes();
        assert_eq!(merged.get("bGotN"), Some(&json!(1)));
        assert_eq!(
            merged.get("aSawOwn"),
            None,
            "автор не получает своё событие"
        );
    }

    #[test]
    fn emit_ping_pong_stops_at_the_depth_limit() {
        let mut host = PluginHost::new();
        // a: node_enter → custom.a; на custom.b шлёт custom.a обратно
        install(
            &mut host,
            "com.example.a",
            &["events"],
            &["node_enter", "custom.b"],
            r#"function on_node_enter() mnd.emit('custom.a', {}) end
               mnd.on('custom.b', function() mnd.emit('custom.a', {}) end)"#,
        );
        // b: на custom.a шлёт custom.b
        install(
            &mut host,
            "com.example.b",
            &["events"],
            &["custom.a"],
            "mnd.on('custom.a', function() mnd.emit('custom.b', {}) end)",
        );
        let dispatch = host.invoke_event("node_enter", json!({}), &context());
        assert!(
            dispatch.notes.iter().any(|note| note.contains("глубина")),
            "рассылка должна быть остановлена лимитом: {:?}",
            dispatch.notes
        );
    }

    #[test]
    fn direct_call_reaches_its_target_and_emits_still_spread() {
        let mut host = PluginHost::new();
        install(
            &mut host,
            "com.example.a",
            &["ui", "events"],
            &[],
            r#"function open(p)
                 mnd.ui.toast('открыт ' .. p.name)
                 mnd.emit('custom.opened', { name = p.name })
               end"#,
        );
        install(
            &mut host,
            "com.example.b",
            &["quest"],
            &["custom.opened"],
            "mnd.on('custom.opened', function(p) mnd.vars.set('bSaw', p.name) end)",
        );
        let dispatch = host.call(
            "com.example.a",
            "open",
            json!({ "name": "инвентарь" }),
            &context(),
        );
        assert_eq!(dispatch.outcomes[0].plugin_id, "com.example.a");
        assert_eq!(dispatch.outcomes[0].error, None);
        assert_eq!(dispatch.commands()[0]["text"], json!("открыт инвентарь"));
        assert_eq!(
            dispatch.var_writes().get("bSaw"),
            Some(&json!("инвентарь")),
            "до «b» рассылка дошла, хотя его не звали напрямую"
        );

        let dispatch = host.call("com.example.zzz", "open", Value::Null, &context());
        assert!(
            dispatch.errors()[0].contains("не установлен"),
            "{:?}",
            dispatch.errors()
        );
    }

    #[test]
    fn cancel_works_only_on_cancelable_events() {
        let mut host = PluginHost::new();
        install(
            &mut host,
            "com.example.a",
            &[],
            &["node_enter", "item_press"],
            "function on_node_enter() mnd.cancel() end
             function on_item_press() mnd.cancel() end",
        );
        let dispatch = host.invoke_event("node_enter", json!({ "nodeId": "x" }), &context());
        assert!(dispatch.canceled(), "{:?}", dispatch.outcomes);
        assert!(
            dispatch.outcomes[0].cancel,
            "отмена есть и в исходе плагина"
        );

        let dispatch = host.invoke_event("item_press", json!({ "nodeId": "x" }), &context());
        assert!(!dispatch.canceled());
        assert!(
            !dispatch.errors().is_empty(),
            "mnd.cancel() на не отменяемом событии — ошибка"
        );
    }

    #[test]
    fn one_failing_plugin_does_not_stop_the_others() {
        let mut host = PluginHost::new();
        install(
            &mut host,
            "com.example.a",
            &["quest"],
            &["node_enter"],
            "function on_node_enter() error('сломался') end",
        );
        install(
            &mut host,
            "com.example.b",
            &["quest"],
            &["node_enter"],
            "function on_node_enter() mnd.vars.set('didIt', true) end",
        );
        let dispatch = host.invoke_event("node_enter", json!({}), &context());
        assert_eq!(dispatch.errors().len(), 1);
        assert_eq!(dispatch.var_writes().get("didIt"), Some(&json!(true)));
    }

    #[test]
    fn storage_is_per_plugin_and_readable_from_the_host() {
        let mut host = PluginHost::new();
        host.register(
            &manifest_json("com.example.a", &["storage"], &[]),
            "function f() mnd.storage.set('x', 1) end",
            Some(json!({ "kept": true })),
        )
        .unwrap();
        host.call("com.example.a", "f", Value::Null, &context());
        let stored = host.storage("com.example.a").unwrap();
        assert_eq!(stored["x"], json!(1));
        assert_eq!(
            stored["kept"],
            json!(true),
            "снимок при установке не теряется"
        );
        assert_eq!(host.storages()["com.example.a"]["x"], json!(1));
    }

    #[test]
    fn content_types_slots_and_manifests_describe_the_installations() {
        let mut host = PluginHost::new();
        let with_extras = json!({
            "id": "com.example.hud",
            "name": "HUD",
            "version": "1.0.0",
            "sdk": crate::SDK_VERSION,
            "entry": "main.lua",
            "permissions": ["ui"],
            "hooks": ["node_enter"],
            "contentTypes": [{
                "id": "counter",
                "name": "Счётчик",
                "description": "Кликов",
                "fields": [{ "key": "step", "label": "Шаг", "type": "number" }]
            }],
            "slots": [
                { "id": "topRight", "area": "hud", "priority": 10 },
                { "id": "menu", "area": "menu", "priority": 1 }
            ]
        })
        .to_string();
        host.register(&with_extras, "function on_node_enter() end", None)
            .unwrap();

        let types = host.content_types();
        assert_eq!(types[0]["type"], json!("com.example.hud:counter"));
        assert_eq!(types[0]["pluginId"], json!("com.example.hud"));
        assert_eq!(types[0]["description"], json!("Кликов"));
        assert_eq!(types[0]["fields"][0]["key"], json!("step"));

        let slots = host.slots();
        assert_eq!(slots.len(), 2);
        assert_eq!(slots[0]["area"], json!("hud"), "области сортируются");
        assert_eq!(slots[1]["area"], json!("menu"));
        assert_eq!(slots[0]["id"], json!("topRight"));

        assert_eq!(host.active_hooks(), vec!["node_enter".to_string()]);
        assert_eq!(
            host.permissions_of("com.example.hud"),
            Some(vec!["ui".to_string()])
        );
        assert_eq!(host.manifests()[0]["id"], json!("com.example.hud"));
    }

    #[test]
    fn logs_from_plugins_are_collected() {
        let mut host = PluginHost::new();
        install(
            &mut host,
            "com.example.a",
            &[],
            &["item_press"],
            "function on_item_press() mnd.log.warn('тест') end",
        );
        let dispatch = host.invoke_event("item_press", json!({}), &context());
        let logs = dispatch.logs();
        assert_eq!(logs.len(), 1);
        assert_eq!(logs[0].level, LogLevel::Warn);
        assert_eq!(logs[0].text, "тест");
    }

    #[test]
    fn unregister_removes_the_plugin() {
        let mut host = PluginHost::new();
        install(
            &mut host,
            "com.example.a",
            &[],
            &["node_enter"],
            "function on_node_enter() end",
        );
        assert_eq!(host.active_hooks(), vec!["node_enter".to_string()]);
        assert!(host.unregister("com.example.a"));
        assert!(!host.unregister("com.example.a"));
        assert!(host.is_empty());
        assert!(host.active_hooks().is_empty());
        assert!(host.slots().is_empty());
    }
}
