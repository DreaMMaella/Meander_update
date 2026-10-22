//! Имена событий EventContract v0.1 — единый источник истины для хуков.

/// События, на которые может подписаться плагин
/// (`docs/event-contract.md` §2–§3).
pub const EVENTS: &[&str] = &[
    "quest_start",
    "quest_end",
    "quest_save",
    "quest_load",
    "node_enter",
    "node_exit",
    "item_reveal",
    "item_press",
    "transition",
    "audio",
];

/// События, где хук вправе отменить дефолтное поведение (`cancel: true`).
pub const CANCELABLE_EVENTS: &[&str] = &["node_enter"];

/// Префикс собственных событий плагинов: `mnd.emit('custom.comboDone', …)`.
/// Их не эмитит движок — только хост, разворачивая очередь `emit`.
pub const CUSTOM_EVENT_PREFIX: &str = "custom.";

pub fn is_known(event: &str) -> bool {
    EVENTS.contains(&event)
}

/// Можно ли подписаться/отправить: событие движка или своё `custom.*`.
pub fn is_declareable(event: &str) -> bool {
    is_known(event)
        || event
            .strip_prefix(CUSTOM_EVENT_PREFIX)
            .is_some_and(|name| !name.is_empty())
}

pub fn is_cancelable(event: &str) -> bool {
    CANCELABLE_EVENTS.contains(&event)
}

/// Имя Lua-функции по соглашению: `node_enter` → `on_node_enter`.
pub fn handler_name(event: &str) -> String {
    format!("on_{event}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn event_names_are_unique_and_ordered_as_documented() {
        let mut sorted = EVENTS.to_vec();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(sorted.len(), EVENTS.len());
        assert!(is_known("item_press"));
        assert!(!is_known("onItemPress"));
        assert!(is_cancelable("node_enter"));
        assert!(!is_cancelable("node_exit"));
        assert_eq!(handler_name("quest_start"), "on_quest_start");
    }
}
