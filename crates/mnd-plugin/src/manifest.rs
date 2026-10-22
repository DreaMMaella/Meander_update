//! Манифест плагина (`plugin.json`).
//!
//! Только JSON — без YAML-зависимости: клиент уже читает JSON-ассеты, а
//! формат должен быть тем же, что и у остальных файлов квеста.
//!
//! Валидация `id`/путей написана руками (а не через `regex`): правила
//! короткие, а зависимостей в крейте должно быть минимум.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::events;
use crate::policy::Permission;
use crate::{SDK_VERSION, spec};

/// Как выглядит тип контента плагина в редакторе и в плеере.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContentTypeDecl {
    /// Ключ внутри плагина, например `combinationLock`. Полный `type`
    /// содержимого — `<pluginId>:<id>`.
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    /// Имя Material-иконки по схеме, которую понимает клиент; пусто — иконка
    /// по умолчанию.
    #[serde(default)]
    pub icon: Option<String>,
    /// Поля, которые редактор показывает как форму (данные, не код).
    #[serde(default)]
    pub fields: Vec<FieldDecl>,
    /// Декларация превью в карточке контента.
    #[serde(default)]
    pub preview: Option<Value>,
}

/// Описание одного поля формы типа контента.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FieldDecl {
    pub key: String,
    pub label: String,
    /// `text` | `number` | `bool` | `select` | `color` | `asset`
    #[serde(rename = "type")]
    pub kind: FieldKind,
    #[serde(default)]
    pub default: Option<Value>,
    /// Опции для `select`.
    #[serde(default)]
    pub options: Vec<String>,
    #[serde(default)]
    pub min: Option<f64>,
    #[serde(default)]
    pub max: Option<f64>,
    #[serde(default)]
    pub hint: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FieldKind {
    Text,
    Number,
    Bool,
    Select,
    Color,
    Asset,
}

/// Куда клиент может встроить UI плагина.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SlotDecl {
    pub id: String,
    /// `hud` | `overlay` | `drawer` | `menu`
    pub area: String,
    /// Порядок внутри области; меньше — выше/левее.
    #[serde(default)]
    pub priority: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PluginManifest {
    pub id: String,
    pub name: String,
    pub version: String,
    /// Совместимость по SDK; см. [`SDK_VERSION`].
    pub sdk: String,
    /// Относительный путь к Lua-точке входа, например `main.lua`.
    pub entry: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub author: Option<String>,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub permissions: Vec<String>,
    /// События, на которые плагин объявляет хуки. Нужны, чтобы ядро не дергало
    /// плагин на каждом событии, и чтобы подписка была видна до исполнения Lua.
    #[serde(default)]
    pub hooks: Vec<String>,
    #[serde(default)]
    pub content_types: Vec<ContentTypeDecl>,
    #[serde(default)]
    pub slots: Vec<SlotDecl>,
}

/// Ошибки манифеста — одна строка на проблему, чтобы показать их все сразу.
pub type ManifestErrors = Vec<String>;

impl PluginManifest {
    /// Разобрать и проверить `plugin.json`.
    pub fn from_json(raw: &str) -> Result<Self, ManifestErrors> {
        let manifest: Self = serde_json::from_str(raw)
            .map_err(|e| vec![format!("манифест разобран не был: {e}")])?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn validate(&self) -> Result<(), ManifestErrors> {
        let mut errors = ManifestErrors::new();

        check_id(&self.id, &mut errors);
        if self.name.trim().is_empty() {
            errors.push("name пустой".into());
        }
        if self.version.trim().is_empty() {
            errors.push("version пустой".into());
        }
        if self.sdk != SDK_VERSION {
            errors.push(format!(
                "sdk '{}' не поддерживается (ожидается '{SDK_VERSION}')",
                self.sdk
            ));
        }
        check_entry(&self.entry, &mut errors);

        let (policy, permission_errors) = crate::policy::Policy::from_names(&self.permissions);
        errors.extend(permission_errors);
        let _ = policy;

        let mut seen_hooks = BTreeSet::new();
        for hook in &self.hooks {
            if !events::is_declareable(hook) {
                errors.push(format!(
                    "хук '{hook}' — не событие EventContract и не custom.*"
                ));
            } else if !seen_hooks.insert(hook.as_str()) {
                errors.push(format!("хук '{hook}' объявлен дважды"));
            }
        }

        let mut seen_content = BTreeSet::new();
        for ct in &self.content_types {
            if !is_safe_key(&ct.id) {
                errors.push(format!("contentTypes[].id '{}' недопустим", ct.id));
            } else if !seen_content.insert(ct.id.as_str()) {
                errors.push(format!("contentTypes[].id '{}' дублируется", ct.id));
            }
            if ct.name.trim().is_empty() {
                errors.push(format!("contentTypes '{}': пустое name", ct.id));
            }
            let mut seen_keys = BTreeSet::new();
            for field in &ct.fields {
                if !is_safe_key(&field.key) {
                    errors.push(format!(
                        "contentTypes '{}': поле '{}' недопустимо",
                        ct.id, field.key
                    ));
                } else if !seen_keys.insert(field.key.as_str()) {
                    errors.push(format!(
                        "contentTypes '{}': поле '{}' дублируется",
                        ct.id, field.key
                    ));
                }
                if field.label.trim().is_empty() {
                    errors.push(format!(
                        "contentTypes '{}': поле '{}' без label",
                        ct.id, field.key
                    ));
                }
                if field.kind == FieldKind::Select && field.options.is_empty() {
                    errors.push(format!(
                        "contentTypes '{}': select-поле '{}' без options",
                        ct.id, field.key
                    ));
                }
            }
            if let Some(preview) = &ct.preview {
                let limits = crate::policy::Limits::default();
                if let Err(spec_errors) = spec::validate(preview, &limits) {
                    errors.extend(
                        spec_errors
                            .into_iter()
                            .map(|e| format!("contentTypes '{}': {e}", ct.id)),
                    );
                }
            }
        }

        let mut seen_slots = BTreeSet::new();
        for slot in &self.slots {
            if !is_safe_key(&slot.id) {
                errors.push(format!("slots[].id '{}' недопустим", slot.id));
            } else if !seen_slots.insert(slot.id.as_str()) {
                errors.push(format!("slots[].id '{}' дублируется", slot.id));
            }
            if !matches!(slot.area.as_str(), "hud" | "overlay" | "drawer" | "menu") {
                errors.push(format!(
                    "slots '{}': area '{}' должен быть hud/overlay/drawer/menu",
                    slot.id, slot.area
                ));
            }
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
    }

    /// Разрешения как типизированный список (после `validate` ошибок нет).
    pub fn permission_list(&self) -> Vec<Permission> {
        let (policy, _) = crate::policy::Policy::from_names(&self.permissions);
        policy.permissions().to_vec()
    }

    /// Полный `type` содержимого для клиента: `com.example.lock:combinationLock`.
    pub fn content_type_id(&self, local_id: &str) -> String {
        format!("{}:{local_id}", self.id)
    }
}

/// Каталог-идентификатор: строчные сегменты через точку + локальный ключ.
fn check_id(id: &str, errors: &mut ManifestErrors) {
    if id.is_empty() {
        errors.push("id пустой".into());
        return;
    }
    if !id.is_ascii() {
        errors.push(format!("id '{id}' должен быть ASCII"));
        return;
    }
    let segments: Vec<&str> = id.split('.').collect();
    if segments.len() < 2 {
        errors.push(format!("id '{id}' должен быть как com.example.name"));
        return;
    }
    for segment in &segments {
        let valid = !segment.is_empty()
            && segment.len() <= 32
            && segment.starts_with(|c: char| c.is_ascii_lowercase())
            && segment
                .chars()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_');
        if !valid {
            errors.push(format!("id '{id}': сегмент '{segment}' недопустим"));
            return;
        }
    }
}

/// Путь точки входа: только относительный, без `..` и ведующего слэша.
fn check_entry(entry: &str, errors: &mut ManifestErrors) {
    if entry.is_empty() || !entry.ends_with(".lua") {
        errors.push(format!("entry '{entry}' должен указывать на .lua"));
        return;
    }
    if entry.starts_with('/') || entry.contains("..") {
        errors.push(format!("entry '{entry}' должен быть относительным путём"));
        return;
    }
    if !entry
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '/'))
    {
        errors.push(format!("entry '{entry}' содержит недопустимые символы"));
    }
}

/// Ключ (id поля/слота/типа контента): ASCII-идентификатор в верблюжьей-case.
fn is_safe_key(raw: &str) -> bool {
    let mut chars = raw.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    raw.len() <= 64
        && first.is_ascii_alphabetic()
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn minimal() -> Value {
        Value::Object(serde_json::Map::from_iter([
            ("id".into(), json!("com.example.lock")),
            ("name".into(), json!("Замок")),
            ("version".into(), json!("1.0.0")),
            ("sdk".into(), json!(SDK_VERSION)),
            ("entry".into(), json!("main.lua")),
        ]))
    }

    fn parse(value: Value) -> Result<PluginManifest, ManifestErrors> {
        PluginManifest::from_json(&value.to_string())
    }

    #[test]
    fn minimal_manifest_parses_with_no_optional_sections() {
        let manifest = parse(minimal()).unwrap();
        assert_eq!(manifest.entry, "main.lua");
        assert!(manifest.hooks.is_empty());
        assert!(manifest.content_types.is_empty());
        assert!(manifest.permission_list().is_empty());
        assert_eq!(
            manifest.content_type_id("combinationLock"),
            "com.example.lock:combinationLock"
        );
    }

    #[test]
    fn rejects_wrong_sdk_and_bad_ids() {
        let mut value = minimal();
        value["sdk"] = json!("2");
        value["id"] = json!("com..Example");
        let errors = parse(value).unwrap_err();
        assert!(
            errors
                .iter()
                .any(|e| e.contains("sdk '2' не поддерживается")),
            "{errors:?}"
        );
        assert!(errors.iter().any(|e| e.contains("сегмент")), "{errors:?}");
    }

    #[test]
    fn rejects_entry_escaping_the_plugin_folder() {
        for bad in ["../secrets.lua", "/etc/passwd.lua", "main.txt"] {
            let mut value = minimal();
            value["entry"] = json!(bad);
            let errors = parse(value).unwrap_err();
            assert!(!errors.is_empty(), "'{bad}' принят");
        }
    }

    #[test]
    fn rejects_unknown_hook_and_permission_and_duplicate_keys() {
        let mut value = minimal();
        value["hooks"] = json!(["node_enter", "onNodeEnter", "node_enter"]);
        value["permissions"] = json!(["ui", "filesystem"]);
        value["contentTypes"] = json!([
            { "id": "lock", "name": "Замок", "fields": [
                { "key": "a", "label": "A", "type": "select", "options": [] },
                { "key": "a", "label": "B", "type": "text" }
            ]},
            { "id": "lock", "name": "Ещё" }
        ]);
        value["slots"] = json!([{ "id": "hud1", "area": "somewhere" }]);
        let errors = parse(value).unwrap_err();
        assert!(
            errors
                .iter()
                .any(|e| e.contains("не событие EventContract")),
            "{errors:?}"
        );
        assert!(
            errors
                .iter()
                .any(|e| e.contains("хук 'node_enter' объявлен дважды")),
            "{errors:?}"
        );
        assert!(
            errors.iter().any(|e| e.contains("неизвестное разрешение")),
            "{errors:?}"
        );
        assert!(
            errors.iter().any(|e| e.contains("select-поле")),
            "{errors:?}"
        );
        assert!(
            errors.iter().any(|e| e.contains("дублируется")),
            "{errors:?}"
        );
        assert!(
            errors.iter().any(|e| e.contains("hud/overlay/drawer/menu")),
            "{errors:?}"
        );
    }

    #[test]
    fn full_manifest_roundtrips_camel_case() {
        let manifest = PluginManifest {
            id: "com.example.hud".into(),
            name: "HUD".into(),
            version: "0.1.0".into(),
            sdk: SDK_VERSION.into(),
            entry: "main.lua".into(),
            description: None,
            author: None,
            icon: None,
            tags: vec!["hud".into()],
            permissions: vec!["ui".into(), "quest".into()],
            hooks: vec!["node_enter".into()],
            content_types: vec![ContentTypeDecl {
                id: "counter".into(),
                name: "Счётчик".into(),
                description: None,
                icon: None,
                fields: vec![FieldDecl {
                    key: "step".into(),
                    label: "Шаг".into(),
                    kind: FieldKind::Number,
                    default: Some(json!(1)),
                    options: vec![],
                    min: Some(1.0),
                    max: None,
                    hint: None,
                }],
                preview: Some(json!({ "type": "text", "text": "x" })),
            }],
            slots: vec![SlotDecl {
                id: "topRight".into(),
                area: "hud".into(),
                priority: 10,
            }],
        };
        let raw = serde_json::to_string(&manifest).unwrap();
        assert!(raw.contains("\"contentTypes\""), "{raw}");
        assert!(raw.contains("\"sdk\""), "{raw}");
        let again = PluginManifest::from_json(&raw).unwrap();
        assert_eq!(again, manifest);
    }
}
