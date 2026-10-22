//! Модель слота сохранения (`SaveSlot`).

use serde_json::{Map, Value, json};
use uuid::Uuid;

/// Паритет: `packages/mnd_core/lib/models/save_slot.dart`.
#[derive(Debug, Clone, PartialEq)]
pub struct SaveSlot {
    pub id: String,
    pub quest_id: String,
    pub slot_name: String,
    pub saved_at: String,
    pub current_node_id: String,
    pub variables: Map<String, Value>,
    /// Таблицы хранятся как JSON.
    pub tables: Map<String, Value>,
}

impl SaveSlot {
    pub fn create_new(
        quest_id: String,
        slot_name: String,
        current_node_id: String,
        variables: Map<String, Value>,
        tables: Map<String, Value>,
    ) -> Self {
        SaveSlot {
            id: Uuid::new_v4().to_string(),
            quest_id,
            slot_name,
            saved_at: now_iso8601(),
            current_node_id,
            variables,
            tables,
        }
    }

    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();
        SaveSlot {
            id: obj
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            quest_id: obj
                .get("questId")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            slot_name: obj
                .get("slotName")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            saved_at: obj
                .get("savedAt")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            current_node_id: obj
                .get("currentNodeId")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            variables: obj
                .get("variables")
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default(),
            tables: obj
                .get("tables")
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default(),
        }
    }

    pub fn to_json(&self) -> Value {
        json!({
            "id": self.id,
            "questId": self.quest_id,
            "slotName": self.slot_name,
            "savedAt": self.saved_at,
            "currentNodeId": self.current_node_id,
            "variables": self.variables,
            "tables": self.tables,
        })
    }
}

/// Текущее время в формате ISO-8601 (как `DateTime.now().toIso8601String()`).
pub fn now_iso8601() -> String {
    // Формат без микросекунд: "2026-08-12T00:15:00.000" как Dart.
    let nanos = crate::time::unix_now_nanos();
    let secs = (nanos / 1_000_000_000) as i64;
    let millis = ((nanos / 1_000_000) % 1_000) as u32;
    // Unix epoch → дата. Используем простую формулу дней из эпохи.
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    let (hh, mm, ss) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:03}",
        y, m, d, hh, mm, ss, millis
    )
}

/// Конверсия дней с Unix-эпохи в гражданскую дату (алгоритм Howard Hinnant).
fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as i64; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as i64; // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}
