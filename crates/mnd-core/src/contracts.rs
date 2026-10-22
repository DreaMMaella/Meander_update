//! Порты (contracts) ядра.
//!
//! Аналоги dart-контрактов `packages/mnd_core/lib/contracts/`.
//! Трейты намеренно минимальны — конкретные реализации поставляет
//! приложение (filesystem, network, in-memory).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use serde_json::{Map, Value};

/// Контракт движка вычисления выражений (`"a > 5"`, `"name == 'Bob'"`).
///
/// Паритет: `ScriptExpressionEngine` из
/// `packages/mnd_core/lib/contracts/script_expression_engine.dart` —
/// контекст это `Map<String, dynamic>` переменных/таблиц (не runtime).
/// Реализация в `mnd-core` — [`crate::expression::ExpressionEvaluator`],
/// приложение может подставить свою через [`crate::ScriptExecutor::configure`].
pub trait ScriptExpressionEngine: Send + Sync {
    /// Вычислить выражение в контексте переменных.
    /// `Value::Null` означает «не смог оценить» (каскадный lookup продолжает).
    fn evaluate(&self, expression: &str, context: &Map<String, Value>) -> Value;
}

/// Дефолтный алиас хранилища сейвов (как `DynAssetStore` в executor).
pub type DynSaveStore = Arc<dyn SaveStore + Send + Sync>;

/// Минимальный порт доступа к ассетам квеста (узлы, скрипты, ресурсы).
pub trait ScriptAssetStore: Send + Sync {
    /// Существует ли ресурс по указанному относительному пути.
    fn exists(&self, path: &str) -> bool;

    /// Прочитать JSON-документ по `path`.
    fn read_json(&self, path: &str) -> Option<Value>;

    /// Прочитать «сырой» текстовый ресурс по `path` (например, `.lua`-скрипт).
    ///
    /// По умолчанию `None` — реализации, не работающие с текстом (кроме JSON),
    /// могут не переопределять метод.
    fn read_text(&self, _path: &str) -> Option<String> {
        None
    }

    /// Относительные пути файлов внутри `rel_dir` (без подкаталогов).
    ///
    /// Нужен движку, чтобы найти скрипты квеста, объявившие квестовое событие
    /// (`onQuestStart`, `onVarChange`) — таких реестра в конфиге нет.
    /// Реализации без перечисления файлов возвращают пустой список.
    fn list_dir(&self, _rel_dir: &str) -> Vec<String> {
        Vec::new()
    }
}

/// Файловая реализация [`ScriptAssetStore`]: читает JSON-документы с диска.
///
/// `root` — базовая директория (например, каталог документов приложения).
/// Пути задаются относительно `root` в виде `quests/<quest_id>/<file>`
/// (паритет путей клиента `FileStorage`). Защищает от выхода за пределы
/// корня (`..` и абсолютные пути отклоняются).
pub struct FsScriptAssetStore {
    root: PathBuf,
    cache: Mutex<HashMap<String, Option<Value>>>,
    text_cache: Mutex<HashMap<String, Option<String>>>,
}

impl FsScriptAssetStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            cache: Mutex::new(HashMap::new()),
            text_cache: Mutex::new(HashMap::new()),
        }
    }

    fn resolve(&self, path: &str) -> Option<PathBuf> {
        let p = Path::new(path);
        if p.is_absolute()
            || p.components().any(|c| {
                matches!(
                    c,
                    std::path::Component::ParentDir
                        | std::path::Component::RootDir
                        | std::path::Component::Prefix(_)
                )
            })
        {
            return None;
        }
        Some(self.root.join(p))
    }
}

impl ScriptAssetStore for FsScriptAssetStore {
    fn exists(&self, path: &str) -> bool {
        self.resolve(path).map(|p| p.is_file()).unwrap_or(false)
    }

    fn read_json(&self, path: &str) -> Option<Value> {
        if let Some(hit) = self.cache.lock().ok().and_then(|c| c.get(path).cloned()) {
            return hit;
        }
        let file = self.resolve(path)?;
        let content = std::fs::read_to_string(&file).ok()?;
        let parsed = serde_json::from_str(&content).ok();
        if let Ok(mut cache) = self.cache.lock() {
            cache.insert(path.to_string(), parsed.clone());
        }
        parsed
    }

    fn read_text(&self, path: &str) -> Option<String> {
        if let Some(hit) = self
            .text_cache
            .lock()
            .ok()
            .and_then(|c| c.get(path).cloned())
        {
            return hit;
        }
        let file = self.resolve(path)?;
        let content = std::fs::read_to_string(&file).ok();
        if let Ok(mut cache) = self.text_cache.lock() {
            cache.insert(path.to_string(), content.clone());
        }
        content
    }

    fn list_dir(&self, rel_dir: &str) -> Vec<String> {
        let Some(dir) = self.resolve(rel_dir) else {
            return Vec::new();
        };
        let Ok(entries) = std::fs::read_dir(&dir) else {
            return Vec::new();
        };
        let mut out: Vec<String> = entries
            .filter_map(Result::ok)
            .filter(|e| e.path().is_file())
            .filter_map(|e| {
                e.file_name()
                    .to_str()
                    .map(|name| format!("{}/{}", rel_dir.trim_end_matches('/'), name))
            })
            .collect();
        out.sort();
        out
    }
}

/// Хранилище сохранений (save slots) квеста.
///
/// Реализации: файловая система, БД, память.
pub trait SaveStore: Send + Sync {
    /// Вернуть все сейв-слоты конкретного квеста.
    fn list(&self, quest_id: &str) -> Vec<crate::models::SaveSlot>;

    /// Прочитать конкретный слот, либо `None`.
    fn read(&self, quest_id: &str, slot_id: &str) -> Option<crate::models::SaveSlot>;

    /// Сохранить слот (создаст или перезапишет).
    fn write(&self, slot: &crate::models::SaveSlot);

    /// Удалить слот.
    fn delete(&self, quest_id: &str, slot_id: &str);

    /// Удалить все слоты квеста.
    fn delete_all(&self, quest_id: &str);
}

/// In-memory реализация [`SaveStore`] для тестов и окружений без ФС.
#[derive(Default)]
pub struct InMemorySaveStore {
    slots: Mutex<HashMap<String, crate::models::SaveSlot>>,
}

impl InMemorySaveStore {
    pub fn new() -> Self {
        Self::default()
    }

    fn key(quest_id: &str, slot_id: &str) -> String {
        format!("{quest_id}/{slot_id}")
    }
}

impl SaveStore for InMemorySaveStore {
    fn list(&self, quest_id: &str) -> Vec<crate::models::SaveSlot> {
        let guard = self.slots.lock().unwrap();
        guard
            .iter()
            .filter(|(k, _)| k.starts_with(&format!("{quest_id}/")))
            .map(|(_, v)| v.clone())
            .collect()
    }

    fn read(&self, quest_id: &str, slot_id: &str) -> Option<crate::models::SaveSlot> {
        let guard = self.slots.lock().unwrap();
        guard.get(&Self::key(quest_id, slot_id)).cloned()
    }

    fn write(&self, slot: &crate::models::SaveSlot) {
        let mut guard = self.slots.lock().unwrap();
        guard.insert(Self::key(&slot.quest_id, &slot.id), slot.clone());
    }

    fn delete(&self, quest_id: &str, slot_id: &str) {
        let mut guard = self.slots.lock().unwrap();
        guard.remove(&Self::key(quest_id, slot_id));
    }

    fn delete_all(&self, quest_id: &str) {
        let mut guard = self.slots.lock().unwrap();
        let prefix = format!("{quest_id}/");
        guard.retain(|k, _| !k.starts_with(&prefix));
    }
}

/// Файловая реализация [`SaveStore`]: слоты в JSON-файлах
/// `root/quests/<quest_id>/saves/<slot_id>.json` (паритет клиентского
/// `JsonFileSaveStore` — старые сейвы читаются сразу).
pub struct FsSaveStore {
    root: PathBuf,
}

impl FsSaveStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    fn slot_path(&self, quest_id: &str, slot_id: &str) -> PathBuf {
        self.root
            .join("quests")
            .join(quest_id)
            .join("saves")
            .join(format!("{slot_id}.json"))
    }

    fn save_folder(&self, quest_id: &str) -> PathBuf {
        self.root.join("quests").join(quest_id).join("saves")
    }
}

impl SaveStore for FsSaveStore {
    fn list(&self, quest_id: &str) -> Vec<crate::models::SaveSlot> {
        let folder = self.save_folder(quest_id);
        let Ok(entries) = std::fs::read_dir(&folder) else {
            return Vec::new();
        };
        entries
            .filter_map(Result::ok)
            .filter(|e| e.path().extension().is_some_and(|ext| ext == "json"))
            .filter_map(|e| {
                let content = std::fs::read_to_string(e.path()).ok()?;
                let value = serde_json::from_str(&content).ok()?;
                Some(crate::models::SaveSlot::from_json(&value))
            })
            .collect()
    }

    fn read(&self, quest_id: &str, slot_id: &str) -> Option<crate::models::SaveSlot> {
        let path = self.slot_path(quest_id, slot_id);
        if !path.is_file() {
            return None;
        }
        let content = std::fs::read_to_string(path).ok()?;
        let value = serde_json::from_str(&content).ok()?;
        Some(crate::models::SaveSlot::from_json(&value))
    }

    fn write(&self, slot: &crate::models::SaveSlot) {
        let path = self.slot_path(&slot.quest_id, &slot.id);
        let Some(parent) = path.parent() else {
            return;
        };
        let _ = std::fs::create_dir_all(parent);
        let json = slot.to_json();
        let bytes = serde_json::to_vec(&json).unwrap_or_default();
        let _ = std::fs::write(path, bytes);
    }

    fn delete(&self, quest_id: &str, slot_id: &str) {
        let path = self.slot_path(quest_id, slot_id);
        if path.is_file() {
            let _ = std::fs::remove_file(path);
        }
    }

    fn delete_all(&self, quest_id: &str) {
        let folder = self.save_folder(quest_id);
        if folder.is_dir() {
            let _ = std::fs::remove_dir_all(folder);
        }
    }
}

/// Порт воспроизведения звука/музыки квеста.
pub trait AudioPort: Send + Sync {
    fn play_sound(&self, path: &str, volume: f64);
    fn play_music(&self, path: &str, loop_: bool, volume: f64);
    fn stop(&self);
    fn stop_all(&self);
    fn dispose(&self);
}

/// No-op реализация аудио (для тестов и окружений без звука).
pub struct NoopAudioPort;

impl AudioPort for NoopAudioPort {
    fn play_sound(&self, _path: &str, _volume: f64) {}
    fn play_music(&self, _path: &str, _loop: bool, _volume: f64) {}
    fn stop(&self) {}
    fn stop_all(&self) {}
    fn dispose(&self) {}
}

/// Минимальный логгер ядра.
pub trait CoreLogger: Send + Sync {
    fn debug(&self, message: &str);
    fn info(&self, message: &str);
    fn warn(&self, message: &str);
    fn error(&self, message: &str, error: Option<&str>);
}

/// Silent-логгер по умолчанию.
pub struct SilentCoreLogger;

impl CoreLogger for SilentCoreLogger {
    fn debug(&self, _message: &str) {}
    fn info(&self, _message: &str) {}
    fn warn(&self, _message: &str) {}
    fn error(&self, _message: &str, _error: Option<&str>) {}
}

/// Терминологическая совместимость с dart: CoreLogger.
pub type CoreLoggerTrait = dyn CoreLogger;

#[cfg(test)]
mod tests {
    use super::*;

    fn slot(id: &str, quest_id: &str, slot_name: &str) -> crate::models::SaveSlot {
        crate::models::SaveSlot {
            id: id.to_string(),
            quest_id: quest_id.to_string(),
            slot_name: slot_name.to_string(),
            saved_at: "2026-08-13T00:00:00.000".to_string(),
            current_node_id: "node_1".to_string(),
            variables: Map::new(),
            tables: Map::new(),
        }
    }

    #[test]
    fn fs_save_store_roundtrip_and_delete() {
        let root = std::env::temp_dir().join(format!("mnd_fs_save_{}", uuid::Uuid::new_v4()));
        let store = FsSaveStore::new(root.clone());

        assert!(store.list("q1").is_empty());
        assert!(store.read("q1", "s1").is_none());

        let s1 = slot("s1", "q1", "Первый");
        store.write(&s1);
        store.write(&slot("s2", "q1", "Второй"));

        let read = store.read("q1", "s1").unwrap();
        assert_eq!(read, s1);
        assert_eq!(store.list("q1").len(), 2);

        store.delete("q1", "s1");
        assert!(store.read("q1", "s1").is_none());
        assert_eq!(store.list("q1").len(), 1);

        store.delete_all("q1");
        assert!(store.list("q1").is_empty());

        // подчистка за тестом
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn fs_save_store_isolated_by_quest() {
        let root = std::env::temp_dir().join(format!("mnd_fs_save_{}", uuid::Uuid::new_v4()));
        let store = FsSaveStore::new(root.clone());
        store.write(&slot("a1", "qa", "A"));
        store.write(&slot("b1", "qb", "B"));

        assert_eq!(store.list("qa").len(), 1);
        assert_eq!(store.list("qb").len(), 1);
        assert!(store.read("qa", "b1").is_none());

        let _ = std::fs::remove_dir_all(&root);
    }
}
