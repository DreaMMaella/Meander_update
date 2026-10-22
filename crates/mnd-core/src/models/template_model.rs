//! Модель шаблона (`TemplateItem`, `TemplateAsset`, `TemplateKind`).
//!
//! Паритет: `packages/mnd_core/lib/models/template_model.dart`.

use serde_json::{Map, Value, json};
use uuid::Uuid;

use super::save_slot::now_iso8601;

/// Тип шаблона.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TemplateKind {
    Node,
    Content,
    Row,
    Column,
    Modal,
    Chapter,
    Multi,
}

impl TemplateKind {
    pub fn raw(&self) -> &'static str {
        match self {
            TemplateKind::Node => "node",
            TemplateKind::Content => "content",
            TemplateKind::Row => "row",
            TemplateKind::Column => "column",
            TemplateKind::Modal => "modal",
            TemplateKind::Chapter => "chapter",
            TemplateKind::Multi => "multi",
        }
    }

    /// Человекочитаемое название (для UI).
    pub fn display_name(&self) -> &'static str {
        match self {
            TemplateKind::Node => "Нода",
            TemplateKind::Content => "Контент",
            TemplateKind::Row => "Ряд",
            TemplateKind::Column => "Колонка",
            TemplateKind::Modal => "Модалка",
            TemplateKind::Chapter => "Глава",
            TemplateKind::Multi => "Набор",
        }
    }

    pub fn from_raw(raw: Option<&str>) -> Self {
        match raw {
            Some("node") => TemplateKind::Node,
            Some("row") => TemplateKind::Row,
            Some("column") => TemplateKind::Column,
            Some("modal") => TemplateKind::Modal,
            Some("chapter") => TemplateKind::Chapter,
            Some("multi") => TemplateKind::Multi,
            // content — дефолт (совпадает с Dart)
            _ => TemplateKind::Content,
        }
    }
}

/// Источник шаблона: где он физически хранится.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TemplateScope {
    /// Локальный для одного квеста: `quests/<id>/res/templates.json`.
    Quest,
    /// Глобальный для всех квестов: `app/templates/templates.json`.
    Global,
}

/// Описание одного упакованного ресурса в шаблоне.
#[derive(Debug, Clone, PartialEq)]
pub struct TemplateAsset {
    pub relative_path: String,
    pub sha256: String,
    pub size: i64,
    pub storage_file_name: Option<String>,
}

impl TemplateAsset {
    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();
        TemplateAsset {
            relative_path: obj
                .get("relativePath")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            sha256: obj
                .get("sha256")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            size: obj.get("size").and_then(Value::as_i64).unwrap_or(0),
            storage_file_name: obj
                .get("storageFileName")
                .and_then(Value::as_str)
                .map(str::to_string),
        }
    }

    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("relativePath".into(), json!(self.relative_path));
        map.insert("sha256".into(), json!(self.sha256));
        map.insert("size".into(), json!(self.size));
        if self.storage_file_name.is_some() {
            map.insert("storageFileName".into(), json!(self.storage_file_name));
        }
        Value::Object(map)
    }
}

/// Единица «репозитория шаблонов».
#[derive(Debug, Clone, PartialEq)]
pub struct TemplateItem {
    pub id: String,
    pub name: String,
    pub kind: TemplateKind,
    pub description: Option<String>,
    pub category: Option<String>,
    pub icon_name: Option<String>,
    pub payload: Map<String, Value>,
    pub assets: Vec<TemplateAsset>,
    pub created_at: String,
    pub updated_at: String,
    pub schema_version: i64,
    pub content_version: i64,
}

impl TemplateItem {
    /// Текущая версия схемы (Dart: 3).
    pub const CURRENT_SCHEMA_VERSION: i64 = 3;

    #[allow(clippy::too_many_arguments)] // паритет с Dart-конструктором
    pub fn new(
        id: String,
        name: String,
        kind: TemplateKind,
        payload: Map<String, Value>,
        description: Option<String>,
        category: Option<String>,
        icon_name: Option<String>,
        assets: Vec<TemplateAsset>,
    ) -> Self {
        let now = now_iso8601();
        TemplateItem {
            id,
            name,
            kind,
            description,
            category,
            icon_name,
            payload,
            assets,
            created_at: now.clone(),
            updated_at: now,
            schema_version: Self::CURRENT_SCHEMA_VERSION,
            content_version: 1,
        }
    }

    pub fn has_assets(&self) -> bool {
        !self.assets.is_empty()
    }

    /// Суммарный размер ассетов в байтах.
    pub fn total_assets_size(&self) -> i64 {
        self.assets.iter().map(|a| a.size).sum()
    }

    fn parse_date(v: Option<&Value>) -> String {
        match v.and_then(Value::as_str) {
            Some(s) if !s.trim().is_empty() => s.to_string(),
            _ => now_iso8601(),
        }
    }

    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();

        let assets = obj
            .get("assets")
            .and_then(Value::as_array)
            .map(|a| a.iter().map(TemplateAsset::from_json).collect())
            .unwrap_or_default();

        TemplateItem {
            id: obj
                .get("id")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_else(|| Uuid::new_v4().to_string()),
            name: obj
                .get("name")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_else(|| "Без имени".to_string()),
            kind: TemplateKind::from_raw(obj.get("kind").and_then(Value::as_str)),
            description: obj
                .get("description")
                .and_then(Value::as_str)
                .map(str::to_string),
            category: obj
                .get("category")
                .and_then(Value::as_str)
                .map(str::to_string),
            icon_name: obj
                .get("iconName")
                .and_then(Value::as_str)
                .map(str::to_string),
            payload: obj
                .get("payload")
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default(),
            assets,
            created_at: Self::parse_date(obj.get("createdAt")),
            updated_at: Self::parse_date(obj.get("updatedAt")),
            schema_version: obj
                .get("schemaVersion")
                .and_then(Value::as_i64)
                .unwrap_or(1),
            content_version: obj
                .get("contentVersion")
                .and_then(Value::as_i64)
                .unwrap_or(1),
        }
    }

    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("id".into(), json!(self.id));
        map.insert("name".into(), json!(self.name));
        map.insert("kind".into(), json!(self.kind.raw()));
        if self.description.is_some() {
            map.insert("description".into(), json!(self.description));
        }
        if self.category.is_some() {
            map.insert("category".into(), json!(self.category));
        }
        if self.icon_name.is_some() {
            map.insert("iconName".into(), json!(self.icon_name));
        }
        map.insert("payload".into(), Value::Object(self.payload.clone()));
        if !self.assets.is_empty() {
            map.insert(
                "assets".into(),
                json!(self.assets.iter().map(|a| a.to_json()).collect::<Vec<_>>()),
            );
        }
        map.insert("createdAt".into(), json!(self.created_at));
        map.insert("updatedAt".into(), json!(self.updated_at));
        map.insert("schemaVersion".into(), json!(self.schema_version));
        map.insert("contentVersion".into(), json!(self.content_version));
        Value::Object(map)
    }
}
