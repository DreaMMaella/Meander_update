//! # mnd-plugin — хост плагинов Meander (L3B)
//!
//! Плагин = папка с манифестом `plugin.json` + точкой входа `main.lua`.
//! Манифест описывает **декларативные вкладки** (типы контента, слоты, хуки),
//! а поведение пишет Lua в песочнице.
//!
//! Принципы (см. `docs/event-contract.md`):
//!
//! - **Никакой загрузки нативного кода.** Lua — единственная «исполняемая»
//!   часть, поставляется как данные. Это то, что разрешает Google Play.
//! - **Плагин не трогает UI-код приложения.** Он присылает *команды*
//!   (`ui.render` с декларативным виджет-спеком), а рисует их Flutter по
//!   фиксированному набору виджетов (`spec.rs`).
//! - **Песочница строже, чем у скриптов квеста (L3A):** из stdlib только
//!   `base`/`table`/`string`/`math`, обнулены `load`/`loadfile`/`dofile` и
//!   `print`, `os`/`io`/`package`/`debug` не подключаются. Сети нет вообще.
//! - **Разрешения (permissions) проверяются ядром**: вызов API без разрешения
//!   — ошибка в Lua + запись в `logs`, а не тихий игнор.
//! - **Хуки идемпотентны**: паника/ошибка одного плагина не рушит геймлуп —
//!   она превращается в `InvocationOutcome::error`.
//!
//! Крейта, как и `mnd-core`, не делает I/O: файлы манифеста и Lua читает
//! клиент и передаёт строками.

pub mod events;
pub mod host;
pub mod manifest;
pub mod policy;
pub mod runtime;
pub mod spec;

pub use events::EVENTS;
pub use host::{EventDispatch, PluginHost};
pub use manifest::PluginManifest;
pub use policy::{Permission, Policy};
pub use runtime::{CallContext, InvocationOutcome, LogEntry, PluginInstance};

/// Версия контракта событий, который понимает этот хост.
pub const EVENT_CONTRACT_VERSION: &str = "0.1";

/// Версия SDK плагинов: манифесты с другим `sdk` отклоняются.
pub const SDK_VERSION: &str = "1";
