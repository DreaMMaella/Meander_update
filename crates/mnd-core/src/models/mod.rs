//! Модели данных движка.
//!
//! Все модели имеют ручные `from_json`/`to_json` — точный паритет с
//! Dart-эталоном (`packages/mnd_core/lib/models/*.dart`), включая
//! коллизии имён полей и легаси-fallback'и.

pub mod content_item;
pub mod json_utils;
pub mod quest_descriptor;
pub mod quest_project;
pub mod quest_table;
pub mod save_slot;
pub mod saved_node;
pub mod template_model;

pub use content_item::{ButtonStyleConfig, ContentItem, ContentTrigger, ModalButtonConfig};
pub use quest_descriptor::Quest;
pub use quest_descriptor::QuestTag;
pub use quest_project::QuestProject;
pub use quest_table::QuestTable;
pub use save_slot::SaveSlot;
pub use saved_node::{CameraState, SavedNode};
pub use template_model::{TemplateAsset, TemplateItem, TemplateKind};
