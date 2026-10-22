/// FFI-безопасные копии моделей mnd-core.
///
/// Все поля дублируют структуры из `mnd_core::models`, но используют
/// `String` вместо `serde_json::Value` для совместимости с flutter_rust_bridge.
use std::collections::HashMap;

/// Тип события скрипта (паритет `EventType` в Dart).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventType {
    OnNodeEnter,
    OnPress,
    OnContentAppear,
    Function,
    /// variant добавлен последним — индексы прежних вариантов не меняются,
    /// поэтому старый `.so` не начнёт молча путать события.
    OnQuestStart,
    /// Событие «При изменении данных»: движок сам находит такие блоки в
    /// скриптах квеста и гоняет их на границе игрового шага.
    OnDataChange,
}

impl EventType {
    pub fn name(&self) -> &'static str {
        match self {
            Self::OnNodeEnter => "onNodeEnter",
            Self::OnPress => "onPress",
            Self::OnContentAppear => "onContentAppear",
            Self::Function => "function",
            Self::OnQuestStart => "onQuestStart",
            Self::OnDataChange => "onDataChange",
        }
    }
}

impl From<EventType> for mnd_core::executor::EventType {
    fn from(v: EventType) -> Self {
        match v {
            EventType::OnNodeEnter => mnd_core::executor::EventType::OnNodeEnter,
            EventType::OnPress => mnd_core::executor::EventType::OnPress,
            EventType::OnContentAppear => mnd_core::executor::EventType::OnContentAppear,
            EventType::Function => mnd_core::executor::EventType::Function,
            EventType::OnQuestStart => mnd_core::executor::EventType::OnQuestStart,
            EventType::OnDataChange => mnd_core::executor::EventType::OnDataChange,
        }
    }
}

/// Плоская структура слота сохранения для FFI.
#[derive(Debug, Clone)]
pub struct SaveSlotData {
    pub id: String,
    pub quest_id: String,
    pub slot_name: String,
    pub saved_at: String,
    pub current_node_id: String,
    /// Переменные: ключ → JSON-строка значения.
    pub variables: HashMap<String, String>,
    /// Таблицы: имя таблицы → (ключ → JSON-строка).
    pub tables: HashMap<String, HashMap<String, String>>,
}

/// Результат исполнения скрипта: имя таблицы, новое значение.
#[derive(Debug, Clone)]
pub struct TableUpdate {
    pub table_name: String,
    pub json_value: String, // сериализованный Value
}

/// Строка таблицы квеста для FFI.
#[derive(Debug, Clone)]
pub struct QuestTableRow {
    pub cells: HashMap<String, String>,
}

/// Описание таблицы квеста.
#[derive(Debug, Clone)]
pub struct QuestTableDescriptor {
    pub name: String,
    pub columns: Vec<String>,
    pub rows: Vec<HashMap<String, String>>,
    pub data: HashMap<String, String>,
}
