//! Песочница плагина: одно Lua-состояние на плагин, API `mnd.*` и сбор
//! «исхода» вызова — команд, изменений переменных, логов и флага отмены.
//!
//! Порядок одного вызова:
//!
//! 1. хост даёт [`CallContext`] (квест, нода, снимок переменных, время);
//! 2. [`PluginInstance::begin`] заполняет входные поля `mnd.*` и обнуляет
//!    счётчик инструкций;
//! 3. выполняются обработчики (`mnd.on(...)` и глобальная `on_<event>`);
//! 4. [`PluginInstance::finish`] забирает накопленный [`InvocationOutcome`].
//!
//!живых объектов движка обработчик не получает: только данные (аргумент и
//! `mnd.payload`) и команды. Память и число VM-инструкций ограничены
//! (`policy::Limits`), поэтому зациклившийся плагин не подвесит геймлуп.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

// Как и в `mnd_core::lua`: `PluginInstance` существует в обеих сборках с одним
// набором методов, иначе `mnd-ffi` и сгенерированный `frb_generated` разъехались
// бы по платформам. В веб-сборке плагин не поднимается (`new()` — ошибка), и
// хост честно докладывает её в `InvocationOutcome.error`.
#[cfg(feature = "lua-runtime")]
mod mlua_instance;
#[cfg(feature = "lua-runtime")]
pub use mlua_instance::PluginInstance;

#[cfg(not(feature = "lua-runtime"))]
mod stub;
#[cfg(not(feature = "lua-runtime"))]
pub use stub::PluginInstance;

/// Входные данные одного вызова. Всё — значения, а не ссылки на движок.
#[derive(Debug, Clone)]
pub struct CallContext<'a> {
    pub quest_id: &'a str,
    /// Нода, на которой произошло событие; пусто — вне ноды.
    pub node_id: &'a str,
    /// Снимок переменных квеста на момент вызова.
    pub vars: &'a Map<String, Value>,
    /// «Сейчас» в миллисекундах — хук детерминирован в тестах.
    pub now_ms: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LogEntry {
    pub plugin_id: String,
    pub level: LogLevel,
    pub text: String,
}

/// Событие, которое плагин попросил разослать (`mnd.emit`). Очередь
/// разворачивает хост — клиент её получает только как диагностику.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EmittedEvent {
    pub event: String,
    pub payload: Value,
}

/// Результат одного вызова: что применить к приложению + диагностика.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InvocationOutcome {
    pub plugin_id: String,
    /// Команды фиксированного набора (`toast`/`render`/`gotoNode`/…). Клиент
    /// исполняет их по порядку и никогда не исполняет код плагина.
    pub commands: Vec<Value>,
    /// Изменения переменных квеста (только записанные этим вызовом).
    pub var_writes: Map<String, Value>,
    pub logs: Vec<LogEntry>,
    pub emits: Vec<EmittedEvent>,
    /// Смысл имеет только для cancelable-событий (`node_enter`).
    pub cancel: bool,
    /// Ошибка Lua/песочницы. Ядро логирует её и продолжает геймлуп.
    pub error: Option<String>,
    /// Плагин менял своё хранилище — хост отдаёт снимок клиенту на запись.
    pub storage_dirty: bool,
}

impl InvocationOutcome {
    fn empty(plugin_id: &str) -> Self {
        Self {
            plugin_id: plugin_id.to_string(),
            commands: Vec::new(),
            var_writes: Map::new(),
            logs: Vec::new(),
            emits: Vec::new(),
            cancel: false,
            error: None,
            storage_dirty: false,
        }
    }

    pub(crate) fn failed(plugin_id: &str, error: impl Into<String>) -> Self {
        Self {
            error: Some(error.into()),
            ..Self::empty(plugin_id)
        }
    }
}

/// Накопитель одного вызова; в мьютексе, чтобы замыкания `mnd.*` видели его
/// из Lua.
#[cfg(feature = "lua-runtime")]
struct ActiveCall {
    event: String,
    /// Рабочий снимок переменных: читает то, что плагин уже записал.
    vars: Map<String, Value>,
    /// Факт записей — наружу уходит только он, а не весь снимок.
    var_writes: Map<String, Value>,
    commands: Vec<Value>,
    logs: Vec<LogEntry>,
    emits: Vec<EmittedEvent>,
    cancel: bool,
}

#[derive(Default)]
#[cfg(feature = "lua-runtime")]
struct Bridge {
    active: Option<ActiveCall>,
    storage: Map<String, Value>,
    storage_dirty: bool,
}

/// Ошибка сборки плагина — список проблем (манифест/песочница/скрипт).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginError(pub Vec<String>);

impl std::fmt::Display for PluginError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0.join("; "))
    }
}

impl std::error::Error for PluginError {}
