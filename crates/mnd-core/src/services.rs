//! Сервисы ядра — высокоуровневые операции поверх портов.
//!
//! Паритет: `packages/mnd_core/lib/services/save_game_service.dart`.

use serde_json::Map;

use crate::contracts::SaveStore;
use crate::models::SaveSlot;
use crate::models::save_slot::now_iso8601;

/// Высокоуровневые операции над сейв-слотами квеста.
/// Не привязан к ФС — работает через порт [`SaveStore`].
pub struct SaveGameService {
    store: Box<dyn SaveStore>,
}

impl SaveGameService {
    /// Id специального слота автосохранения.
    pub const AUTOSAVE_ID: &'static str = "_autosave";

    pub fn new(store: Box<dyn SaveStore>) -> Self {
        Self { store }
    }

    /// Список всех слотов квеста. Автосохранение всегда первым, остальные
    /// отсортированы по дате убывания.
    pub fn get_save_slots(&self, quest_id: &str) -> Vec<SaveSlot> {
        let mut slots = self.store.list(quest_id);
        slots.sort_by(|a, b| {
            if a.id == Self::AUTOSAVE_ID {
                return std::cmp::Ordering::Less;
            }
            if b.id == Self::AUTOSAVE_ID {
                return std::cmp::Ordering::Greater;
            }
            // ISO-8601 строки сравниваются лексикографически корректно.
            b.saved_at.cmp(&a.saved_at)
        });
        slots
    }

    /// Сохранить произвольный слот.
    pub fn save_game(&self, slot: &SaveSlot) {
        self.store.write(slot);
    }

    /// Записать автосохранение для квеста.
    pub fn perform_autosave(
        &self,
        quest_id: &str,
        current_node_id: &str,
        variables: Map<String, serde_json::Value>,
        tables: Map<String, serde_json::Value>,
    ) {
        let slot = SaveSlot {
            id: Self::AUTOSAVE_ID.to_string(),
            quest_id: quest_id.to_string(),
            slot_name: "Автосохранение".to_string(),
            saved_at: now_iso8601(),
            current_node_id: current_node_id.to_string(),
            variables,
            tables,
        };
        self.store.write(&slot);
    }

    pub fn delete_save(&self, quest_id: &str, save_id: &str) {
        self.store.delete(quest_id, save_id);
    }

    pub fn delete_all_saves(&self, quest_id: &str) {
        self.store.delete_all(quest_id);
    }
}

#[cfg(test)]
mod tests {
    use crate::contracts::InMemorySaveStore;

    use super::*;

    fn slot(id: &str, saved_at: &str) -> SaveSlot {
        SaveSlot {
            id: id.to_string(),
            quest_id: "q1".to_string(),
            slot_name: String::new(),
            saved_at: saved_at.to_string(),
            current_node_id: String::new(),
            variables: Map::new(),
            tables: Map::new(),
        }
    }

    #[test]
    fn autosave_first_others_by_date_desc() {
        let store = InMemorySaveStore::default();
        {
            let service = SaveGameService::new(Box::new(store));
            service.save_game(&slot("b", "2026-01-02T10:00:00.000"));
            service.save_game(&slot(
                SaveGameService::AUTOSAVE_ID,
                "2026-01-01T10:00:00.000",
            ));
            service.save_game(&slot("a", "2026-01-03T10:00:00.000"));

            let slots = service.get_save_slots("q1");
            let ids: Vec<&str> = slots.iter().map(|s| s.id.as_str()).collect();
            assert_eq!(ids, vec!["_autosave", "a", "b"]);
        }
    }

    #[test]
    fn autosave_writes_and_deletes() {
        let store = InMemorySaveStore::default();
        let service = SaveGameService::new(Box::new(store));
        service.perform_autosave("q1", "node_1", Map::new(), Map::new());

        let slots = service.get_save_slots("q1");
        assert_eq!(slots.len(), 1);
        assert_eq!(slots[0].id, "_autosave");
        assert_eq!(slots[0].current_node_id, "node_1");
        assert_eq!(slots[0].slot_name, "Автосохранение");

        service.delete_save("q1", "_autosave");
        assert!(service.get_save_slots("q1").is_empty());
    }
}
