//! Разрешения плагинов и лимиты. Всё, что не перечислено здесь, плагину
//! недоступно — ни напрямую, ни «через дырку» в API.

use serde::{Deserialize, Serialize};

/// Право плагина на определённый класс вызовов. Проверяется ядром при каждом
/// вызове `mnd.*`, поэтому компрометация одного плагина не даёт доступа к
/// чужим поверхностям.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Permission {
    /// Рисовать UI: тосты, слоты, экран.
    Ui,
    /// Читать и писать переменные квеста.
    Quest,
    /// Переходы по нодам (`game.goto`).
    Navigation,
    /// Воспроизведение звука.
    Audio,
    /// Собственное хранилище плагина. Один каталог на плагин, не на квест:
    /// автор включает ключи префиксом `questId`, иначе прогресс одного квеста
    /// увидит другой.
    Storage,
    /// Отправка событий другим плагинам (`mnd.emit`).
    Events,
}

impl Permission {
    pub const ALL: &'static [Permission] = &[
        Permission::Ui,
        Permission::Quest,
        Permission::Navigation,
        Permission::Audio,
        Permission::Storage,
        Permission::Events,
    ];

    /// Имя в манифесте (`permissions: [ui, quest, …]`).
    pub fn name(&self) -> &'static str {
        match self {
            Permission::Ui => "ui",
            Permission::Quest => "quest",
            Permission::Navigation => "navigation",
            Permission::Audio => "audio",
            Permission::Storage => "storage",
            Permission::Events => "events",
        }
    }

    pub fn parse(raw: &str) -> Option<Permission> {
        Permission::ALL.iter().copied().find(|p| p.name() == raw)
    }
}

/// Жёсткие ограничения одного вызова. Плагин — недоверенный код: он не должен
/// иметь возможности «раздуть» очередь команд или UI-дерево.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Limits {
    pub max_commands_per_call: usize,
    pub max_logs_per_call: usize,
    pub max_spec_nodes: usize,
    pub max_spec_depth: usize,
    pub max_text_len: usize,
    pub max_payload_len: usize,
    pub max_storage_keys: usize,
    pub max_storage_value_len: usize,
    /// Бюджет памяти Lua-состояния плагина, байты.
    pub lua_memory_bytes: usize,
    /// Бюджет VM-инструкций одного вызова хука. Нужен, чтобы `while true do end`
    /// в плагине не подвесил игровой цикл: Lua-хук прерывается ошибкой.
    pub max_instructions_per_call: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_commands_per_call: 64,
            max_logs_per_call: 100,
            max_spec_nodes: 400,
            max_spec_depth: 24,
            max_text_len: 2000,
            max_payload_len: 64 * 1024,
            max_storage_keys: 256,
            max_storage_value_len: 16 * 1024,
            lua_memory_bytes: 16 * 1024 * 1024,
            max_instructions_per_call: 5_000_000,
        }
    }
}

/// Итоговая политика плагина: набор выданных прав + лимиты.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Policy {
    permissions: Vec<Permission>,
    limits: Limits,
}

impl Policy {
    /// Собрать политику из строк манифеста. Возвращает список ошибок для
    /// неизвестных разрешений — манифест с ними отклоняется.
    pub fn from_names(names: &[String]) -> (Self, Vec<String>) {
        let mut permissions = Vec::new();
        let mut errors = Vec::new();
        for name in names {
            match Permission::parse(name) {
                Some(p) if !permissions.contains(&p) => permissions.push(p),
                Some(_) => {}
                None => errors.push(format!("неизвестное разрешение '{name}'")),
            }
        }
        (
            Self {
                permissions,
                limits: Limits::default(),
            },
            errors,
        )
    }

    pub fn allows(&self, permission: Permission) -> bool {
        self.permissions.contains(&permission)
    }

    pub fn permissions(&self) -> &[Permission] {
        &self.permissions
    }

    pub fn limits(&self) -> &Limits {
        &self.limits
    }

    pub fn with_limits(mut self, limits: Limits) -> Self {
        self.limits = limits;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_permission_is_reported() {
        let (policy, errors) = Policy::from_names(&["ui".into(), "filesystem".into(), "ui".into()]);
        assert!(policy.allows(Permission::Ui));
        assert!(!policy.allows(Permission::Quest));
        assert_eq!(errors, vec!["неизвестное разрешение 'filesystem'"]);
        assert_eq!(policy.permissions().len(), 1);
    }

    #[test]
    fn limits_have_non_zero_defaults() {
        let limits = Limits::default();
        assert!(limits.max_commands_per_call > 0);
        assert!(limits.lua_memory_bytes >= 1024 * 1024);
    }
}
