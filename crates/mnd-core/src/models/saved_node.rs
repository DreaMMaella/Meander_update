//! Модель узла канваса (`SavedNode`) и камеры (`CameraState`).

use serde_json::{Map, Value, json};
use uuid::Uuid;

use super::json_utils::{parse_bool, parse_double, parse_string};

/// Паритет: `packages/mnd_core/lib/models/saved_node.dart`.
#[derive(Debug, Clone, PartialEq)]
pub struct SavedNode {
    pub id: String,
    pub chapter_id: String,
    pub title: String,
    pub content: Map<String, Value>,
    pub x: f64,
    pub y: f64,
    /// Цвет ноды в формате ARGB.
    pub color: Option<i64>,
    pub background_asset_id: Option<String>,
    pub background_video_asset_id: Option<String>,
    pub background_video_volume: Option<f64>,
    pub background_video_loop: Option<bool>,
    pub background_video_muted: Option<bool>,
    pub background_video_fit: Option<String>,
    pub background_blur: Option<f64>,
    pub script_asset_id: Option<String>,
    pub timer_duration: Option<f64>,
    pub default_action_node_id: Option<String>,
    pub timer_hidden: Option<bool>,
    pub background_audio_id: Option<String>,
    pub background_audio_volume: Option<f64>,
    pub toolbar_mode: String,
    pub toolbar_position: String,
    pub toolbar_style: Option<Map<String, Value>>,
    pub allow_save: bool,
    pub allow_inventory_access: bool,
    pub allow_toolbar_interactions: bool,
    pub item_spacing: Option<f64>,
    pub image_rounded_corners: Option<bool>,
    /// Стиль перехода в эту ноду (переопределяет глобальный квеста).
    pub transition_mode: Option<String>,
    pub template_ref: Option<String>,
    pub template_version: Option<i64>,
    pub is_template_master: bool,
}

impl SavedNode {
    /// Связана ли нода с мастер-шаблоном (любой режим).
    pub fn has_template_link(&self) -> bool {
        self.template_ref.as_deref().is_some_and(|r| !r.is_empty())
    }

    /// Является ли нода linked-инстансом (read-only от мастера).
    pub fn is_template_instance(&self) -> bool {
        self.has_template_link() && !self.is_template_master
    }

    /// Является ли нода мастером шаблона.
    pub fn is_template_master_node(&self) -> bool {
        self.has_template_link() && self.is_template_master
    }

    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();

        let id = obj
            .get("id")
            .and_then(Value::as_str)
            .map(str::to_string)
            .unwrap_or_else(|| format!("error_id_{}", Uuid::new_v4()));
        let title = obj
            .get("title")
            .and_then(Value::as_str)
            .map(str::to_string)
            .unwrap_or_else(|| "Нода без имени".to_string());

        let content = match obj.get("content") {
            Some(Value::Object(map)) => map.clone(),
            _ => {
                let mut m = Map::new();
                m.insert("items".to_string(), Value::Array(vec![]));
                m
            }
        };

        SavedNode {
            id,
            title,
            content,
            chapter_id: parse_string(obj.get("chapterId"), ""),
            x: parse_double(obj.get("x"), 0.0),
            y: parse_double(obj.get("y"), 0.0),
            color: obj.get("color").and_then(Value::as_i64),
            background_asset_id: obj
                .get("backgroundAssetId")
                .and_then(Value::as_str)
                .map(str::to_string),
            background_video_asset_id: obj
                .get("backgroundVideoAssetId")
                .and_then(Value::as_str)
                .map(str::to_string),
            background_video_volume: obj
                .get("backgroundVideoVolume")
                .map(|v| parse_double(Some(v), 0.0)),
            background_video_loop: obj.get("backgroundVideoLoop").and_then(Value::as_bool),
            background_video_muted: obj.get("backgroundVideoMuted").and_then(Value::as_bool),
            background_video_fit: obj
                .get("backgroundVideoFit")
                .and_then(Value::as_str)
                .map(str::to_string),
            background_blur: obj
                .get("backgroundBlur")
                .map(|v| parse_double(Some(v), 0.0)),
            script_asset_id: obj
                .get("scriptAssetId")
                .and_then(Value::as_str)
                .map(str::to_string),
            timer_duration: obj.get("timerDuration").map(|v| parse_double(Some(v), 0.0)),
            default_action_node_id: obj
                .get("defaultActionNodeId")
                .and_then(Value::as_str)
                .map(str::to_string),
            timer_hidden: obj.get("timerHidden").and_then(Value::as_bool),
            background_audio_id: obj
                .get("backgroundAudioId")
                .and_then(Value::as_str)
                .map(str::to_string),
            background_audio_volume: obj
                .get("backgroundAudioVolume")
                .map(|v| parse_double(Some(v), 0.0)),
            toolbar_mode: parse_string(obj.get("toolbarMode"), "inherit"),
            toolbar_position: parse_string(obj.get("toolbarPosition"), "bottom"),
            toolbar_style: obj.get("toolbarStyle").and_then(Value::as_object).cloned(),
            allow_save: parse_bool(obj.get("allowSave"), true),
            allow_inventory_access: parse_bool(obj.get("allowInventoryAccess"), true),
            allow_toolbar_interactions: parse_bool(obj.get("allowToolbarInteractions"), true),
            item_spacing: obj.get("itemSpacing").map(|v| parse_double(Some(v), 0.0)),
            image_rounded_corners: obj.get("imageRoundedCorners").and_then(Value::as_bool),
            transition_mode: obj
                .get("transitionMode")
                .and_then(Value::as_str)
                .map(str::to_string),
            template_ref: obj
                .get("templateRef")
                .and_then(Value::as_str)
                .map(str::to_string),
            template_version: obj.get("templateVersion").and_then(Value::as_i64),
            is_template_master: parse_bool(obj.get("isTemplateMaster"), false),
        }
    }

    pub fn to_json(&self) -> Value {
        // Dart: коллизии/пустые значения пропускаются (if ... != null / != default).
        let mut map = Map::new();
        map.insert("id".into(), json!(self.id));
        map.insert("chapterId".into(), json!(self.chapter_id));
        map.insert("title".into(), json!(self.title));
        map.insert("content".into(), Value::Object(self.content.clone()));
        map.insert("x".into(), json!(self.x));
        map.insert("y".into(), json!(self.y));
        if self.color.is_some() {
            map.insert("color".into(), json!(self.color));
        }
        if self.background_asset_id.is_some() {
            map.insert("backgroundAssetId".into(), json!(self.background_asset_id));
        }
        if self.background_video_asset_id.is_some() {
            map.insert(
                "backgroundVideoAssetId".into(),
                json!(self.background_video_asset_id),
            );
        }
        if self.background_video_volume.is_some() {
            map.insert(
                "backgroundVideoVolume".into(),
                json!(self.background_video_volume),
            );
        }
        if self.background_video_loop.is_some() {
            map.insert(
                "backgroundVideoLoop".into(),
                json!(self.background_video_loop),
            );
        }
        if self.background_video_muted.is_some() {
            map.insert(
                "backgroundVideoMuted".into(),
                json!(self.background_video_muted),
            );
        }
        if self.background_video_fit.is_some() {
            map.insert(
                "backgroundVideoFit".into(),
                json!(self.background_video_fit),
            );
        }
        if self.background_blur.is_some() {
            map.insert("backgroundBlur".into(), json!(self.background_blur));
        }
        if self.script_asset_id.is_some() {
            map.insert("scriptAssetId".into(), json!(self.script_asset_id));
        }
        if self.timer_duration.is_some() {
            map.insert("timerDuration".into(), json!(self.timer_duration));
        }
        if self.default_action_node_id.is_some() {
            map.insert(
                "defaultActionNodeId".into(),
                json!(self.default_action_node_id),
            );
        }
        if let Some(v) = self.timer_hidden {
            map.insert("timerHidden".into(), json!(v));
        }
        if self.background_audio_id.is_some() {
            map.insert("backgroundAudioId".into(), json!(self.background_audio_id));
        }
        if self.background_audio_volume.is_some() {
            map.insert(
                "backgroundAudioVolume".into(),
                json!(self.background_audio_volume),
            );
        }
        if self.toolbar_mode != "inherit" {
            map.insert("toolbarMode".into(), json!(self.toolbar_mode));
        }
        if self.toolbar_position != "bottom" {
            map.insert("toolbarPosition".into(), json!(self.toolbar_position));
        }
        if self.toolbar_style.is_some() {
            map.insert("toolbarStyle".into(), json!(self.toolbar_style));
        }
        if !self.allow_save {
            map.insert("allowSave".into(), json!(false));
        }
        if !self.allow_inventory_access {
            map.insert("allowInventoryAccess".into(), json!(false));
        }
        if !self.allow_toolbar_interactions {
            map.insert("allowToolbarInteractions".into(), json!(false));
        }
        if self.item_spacing.is_some() {
            map.insert("itemSpacing".into(), json!(self.item_spacing));
        }
        if self.image_rounded_corners.is_some() {
            map.insert(
                "imageRoundedCorners".into(),
                json!(self.image_rounded_corners),
            );
        }
        if self.transition_mode.is_some() {
            map.insert("transitionMode".into(), json!(self.transition_mode));
        }
        if self.template_ref.is_some() {
            map.insert("templateRef".into(), json!(self.template_ref));
        }
        if self.template_version.is_some() {
            map.insert("templateVersion".into(), json!(self.template_version));
        }
        if self.is_template_master {
            map.insert("isTemplateMaster".into(), json!(true));
        }
        Value::Object(map)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn transition_mode_round_trip() {
        let n = SavedNode::from_json(&json!({
            "id": "n1",
            "chapterId": "ch1",
            "title": "Узел",
            "content": {"items": []},
            "transitionMode": "dark",
        }));
        assert_eq!(n.transition_mode.as_deref(), Some("dark"));
        assert_eq!(n.to_json()["transitionMode"], "dark");
    }

    #[test]
    fn transition_mode_default_none() {
        let n = SavedNode::from_json(&json!({
            "id": "n1",
            "chapterId": "ch1",
            "title": "Узел",
            "content": {"items": []},
        }));
        assert!(n.transition_mode.is_none());
        assert!(n.to_json().get("transitionMode").is_none());
    }
}

/// Паритет: `CameraState` из saved_node.dart.
#[derive(Debug, Clone, PartialEq)]
pub struct CameraState {
    pub offset_x: f64,
    pub offset_y: f64,
    pub scale: f64,
}

impl CameraState {
    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();
        CameraState {
            offset_x: parse_double(obj.get("offsetX"), 0.0),
            offset_y: parse_double(obj.get("offsetY"), 0.0),
            scale: parse_double(obj.get("scale"), 1.0),
        }
    }

    pub fn to_json(&self) -> Value {
        json!({
            "offsetX": self.offset_x,
            "offsetY": self.offset_y,
            "scale": self.scale,
        })
    }
}
