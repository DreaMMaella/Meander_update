//! Модель контента ноды (`ContentItem`), кнопки модалок и стиля кнопок.
//!
//! JSON-паритет: `packages/mnd_core/lib/models/content_item.dart`.

use std::collections::HashMap;

use serde_json::{Map, Value, json};
use uuid::Uuid;

use super::json_utils::{parse_bool, parse_double};

/// Стиль кнопки (модульная сетка).
///
/// Паритет: `ButtonStyleConfig` из content_item.dart.
#[derive(Debug, Clone, PartialEq)]
pub struct ButtonStyleConfig {
    pub preset_id: String,
    pub preset_name: Option<String>,
    pub horizontal_modules: i64,
    pub vertical_modules: i64,
    pub center_modules: i64,
    pub module_size: f64,
    pub auto_center_by_text: bool,
    pub fill_color_value: i64,
    pub border_color_value: i64,
    pub text_color_value: i64,
    pub corner_asset: Option<String>,
    pub h_asset: Option<String>,
    pub v_asset: Option<String>,
    pub center_asset: Option<String>,
    // Текст (null = авто как раньше: 16px, обычный вес, без разрядки)
    pub text_size: Option<f64>,
    pub text_weight: Option<i64>,
    pub letter_spacing: Option<f64>,
    pub font_family: Option<String>,
    // Форма плоской кнопки (null = авто из module_size)
    pub border_radius: Option<f64>,
    pub border_width: Option<f64>,
    pub fill_opacity: Option<f64>,
    pub use_gradient: bool,
    pub gradient_start_color_value: Option<i64>,
    pub gradient_end_color_value: Option<i64>,
    pub gradient_direction: Option<String>,
    // Тень (null = авто из border_color)
    pub shadow_color_value: Option<i64>,
    pub shadow_opacity: Option<f64>,
    pub shadow_blur: Option<f64>,
    pub shadow_offset_x: Option<f64>,
    pub shadow_offset_y: Option<f64>,
    // Паддинги (null = авто из модулей)
    pub padding_h: Option<f64>,
    pub padding_v: Option<f64>,
}

impl Default for ButtonStyleConfig {
    fn default() -> Self {
        ButtonStyleConfig {
            preset_id: "custom".into(),
            preset_name: None,
            horizontal_modules: 6,
            vertical_modules: 3,
            center_modules: 10,
            module_size: 12.0,
            auto_center_by_text: true,
            fill_color_value: 0xFF1A2336,
            border_color_value: 0xFF26C6DA,
            text_color_value: 0xFF26C6DA,
            corner_asset: None,
            h_asset: None,
            v_asset: None,
            center_asset: None,
            text_size: None,
            text_weight: None,
            letter_spacing: None,
            font_family: None,
            border_radius: None,
            border_width: None,
            fill_opacity: None,
            use_gradient: false,
            gradient_start_color_value: None,
            gradient_end_color_value: None,
            gradient_direction: None,
            shadow_color_value: None,
            shadow_opacity: None,
            shadow_blur: None,
            shadow_offset_x: None,
            shadow_offset_y: None,
            padding_h: None,
            padding_v: None,
        }
    }
}

impl ButtonStyleConfig {
    pub fn has_module_assets(&self) -> bool {
        [
            &self.corner_asset,
            &self.h_asset,
            &self.v_asset,
            &self.center_asset,
        ]
        .iter()
        .all(|a| a.as_deref().is_some_and(|s| !s.trim().is_empty()))
    }

    pub fn from_json(json: &Value) -> Self {
        let d = Self::default();
        let obj = json.as_object().cloned().unwrap_or_default();
        let as_str_or = |v: Option<&Value>, extra: &str| -> Option<String> {
            v.and_then(Value::as_str)
                .or_else(|| obj.get(extra).and_then(Value::as_str))
                .map(str::to_string)
        };
        ButtonStyleConfig {
            preset_id: obj
                .get("presetId")
                .and_then(Value::as_str)
                .unwrap_or(&d.preset_id)
                .to_string(),
            preset_name: obj
                .get("presetName")
                .and_then(Value::as_str)
                .map(str::to_string),
            horizontal_modules: obj
                .get("horizontalModules")
                .and_then(Value::as_i64)
                .unwrap_or(d.horizontal_modules),
            vertical_modules: obj
                .get("verticalModules")
                .and_then(Value::as_i64)
                .unwrap_or(d.vertical_modules),
            center_modules: obj
                .get("centerModules")
                .and_then(Value::as_i64)
                .unwrap_or(d.center_modules),
            module_size: obj
                .get("moduleSize")
                .and_then(Value::as_f64)
                .unwrap_or(d.module_size),
            auto_center_by_text: obj
                .get("autoCenterByText")
                .and_then(Value::as_bool)
                .unwrap_or(d.auto_center_by_text),
            fill_color_value: obj
                .get("fillColor")
                .and_then(Value::as_i64)
                .unwrap_or(d.fill_color_value),
            border_color_value: obj
                .get("borderColor")
                .and_then(Value::as_i64)
                .unwrap_or(d.border_color_value),
            text_color_value: obj
                .get("textColor")
                .and_then(Value::as_i64)
                .unwrap_or(d.text_color_value),
            corner_asset: as_str_or(obj.get("cornerAsset"), "cornerAssetPath"),
            h_asset: as_str_or(obj.get("hAsset"), "horizontalAsset"),
            v_asset: as_str_or(obj.get("vAsset"), "verticalAsset"),
            center_asset: as_str_or(obj.get("centerAsset"), "centerAssetPath"),
            text_size: obj.get("textSize").and_then(Value::as_f64),
            text_weight: obj.get("textWeight").and_then(Value::as_i64),
            letter_spacing: obj.get("letterSpacing").and_then(Value::as_f64),
            font_family: obj
                .get("fontFamily")
                .and_then(Value::as_str)
                .map(str::to_string),
            border_radius: obj.get("borderRadius").and_then(Value::as_f64),
            border_width: obj.get("borderWidth").and_then(Value::as_f64),
            fill_opacity: obj.get("fillOpacity").and_then(Value::as_f64),
            use_gradient: obj
                .get("useGradient")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            gradient_start_color_value: obj.get("gradientStartColor").and_then(Value::as_i64),
            gradient_end_color_value: obj.get("gradientEndColor").and_then(Value::as_i64),
            gradient_direction: obj
                .get("gradientDirection")
                .and_then(Value::as_str)
                .map(str::to_string),
            shadow_color_value: obj.get("shadowColor").and_then(Value::as_i64),
            shadow_opacity: obj.get("shadowOpacity").and_then(Value::as_f64),
            shadow_blur: obj.get("shadowBlur").and_then(Value::as_f64),
            shadow_offset_x: obj.get("shadowOffsetX").and_then(Value::as_f64),
            shadow_offset_y: obj.get("shadowOffsetY").and_then(Value::as_f64),
            padding_h: obj.get("paddingH").and_then(Value::as_f64),
            padding_v: obj.get("paddingV").and_then(Value::as_f64),
        }
    }

    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("presetId".into(), json!(self.preset_id));
        if self.preset_name.is_some() {
            map.insert("presetName".into(), json!(self.preset_name));
        }
        map.insert("horizontalModules".into(), json!(self.horizontal_modules));
        map.insert("verticalModules".into(), json!(self.vertical_modules));
        map.insert("centerModules".into(), json!(self.center_modules));
        map.insert("moduleSize".into(), json!(self.module_size));
        map.insert("autoCenterByText".into(), json!(self.auto_center_by_text));
        map.insert("fillColor".into(), json!(self.fill_color_value));
        map.insert("borderColor".into(), json!(self.border_color_value));
        map.insert("textColor".into(), json!(self.text_color_value));
        if self.corner_asset.is_some() {
            map.insert("cornerAsset".into(), json!(self.corner_asset));
        }
        if self.h_asset.is_some() {
            map.insert("hAsset".into(), json!(self.h_asset));
        }
        if self.v_asset.is_some() {
            map.insert("vAsset".into(), json!(self.v_asset));
        }
        if self.center_asset.is_some() {
            map.insert("centerAsset".into(), json!(self.center_asset));
        }
        if let Some(v) = self.text_size {
            map.insert("textSize".into(), json!(v));
        }
        if let Some(v) = self.text_weight {
            map.insert("textWeight".into(), json!(v));
        }
        if let Some(v) = self.letter_spacing {
            map.insert("letterSpacing".into(), json!(v));
        }
        if self.font_family.is_some() {
            map.insert("fontFamily".into(), json!(self.font_family));
        }
        if let Some(v) = self.border_radius {
            map.insert("borderRadius".into(), json!(v));
        }
        if let Some(v) = self.border_width {
            map.insert("borderWidth".into(), json!(v));
        }
        if let Some(v) = self.fill_opacity {
            map.insert("fillOpacity".into(), json!(v));
        }
        if self.use_gradient {
            map.insert("useGradient".into(), json!(true));
        }
        if let Some(v) = self.gradient_start_color_value {
            map.insert("gradientStartColor".into(), json!(v));
        }
        if let Some(v) = self.gradient_end_color_value {
            map.insert("gradientEndColor".into(), json!(v));
        }
        if self.gradient_direction.is_some() {
            map.insert("gradientDirection".into(), json!(self.gradient_direction));
        }
        if let Some(v) = self.shadow_color_value {
            map.insert("shadowColor".into(), json!(v));
        }
        if let Some(v) = self.shadow_opacity {
            map.insert("shadowOpacity".into(), json!(v));
        }
        if let Some(v) = self.shadow_blur {
            map.insert("shadowBlur".into(), json!(v));
        }
        if let Some(v) = self.shadow_offset_x {
            map.insert("shadowOffsetX".into(), json!(v));
        }
        if let Some(v) = self.shadow_offset_y {
            map.insert("shadowOffsetY".into(), json!(v));
        }
        if let Some(v) = self.padding_h {
            map.insert("paddingH".into(), json!(v));
        }
        if let Some(v) = self.padding_v {
            map.insert("paddingV".into(), json!(v));
        }
        Value::Object(map)
    }
}

/// Кнопка всплывающего окна.
#[derive(Debug, Clone, PartialEq)]
pub struct ModalButtonConfig {
    pub id: String,
    pub text: String,
    pub target_node_id: Option<String>,
    pub script_asset_id: Option<String>,
    pub is_primary: bool,
}

impl ModalButtonConfig {
    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();
        ModalButtonConfig {
            id: obj
                .get("id")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_else(|| Uuid::new_v4().to_string()),
            text: obj
                .get("text")
                .and_then(Value::as_str)
                .unwrap_or("Кнопка")
                .to_string(),
            target_node_id: obj
                .get("targetNodeId")
                .and_then(Value::as_str)
                .map(str::to_string),
            script_asset_id: obj
                .get("scriptAssetId")
                .and_then(Value::as_str)
                .map(str::to_string),
            is_primary: parse_bool(obj.get("isPrimary"), true),
        }
    }

    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("id".into(), json!(self.id));
        map.insert("text".into(), json!(self.text));
        if self.target_node_id.is_some() {
            map.insert("targetNodeId".into(), json!(self.target_node_id));
        }
        if self.script_asset_id.is_some() {
            map.insert("scriptAssetId".into(), json!(self.script_asset_id));
        }
        map.insert("isPrimary".into(), json!(self.is_primary));
        Value::Object(map)
    }
}

/// Одно поведение (триггер) контент-айтема.
///
/// JSON: `{"event": "onPress", "script": "scripts/btn.lua", "kind": "action"}`.
/// Заменяет старый `scriptTriggers: { "onPress": "scripts/btn.json" }`.
/// Для обратной совместимости при отсутствии `behaviours` они выводятся из
/// `scriptTriggers` (kind по умолчанию: `action`, для `onAppear` — без kind).
#[derive(Debug, Clone, PartialEq)]
pub struct ContentTrigger {
    /// Тип события: `onPress`, `onAppear`, `onReveal`, `onSubmit`, `onTimer`.
    pub event: String,
    /// Путь к скрипту (`.json` или `.lua`), опционально с `#fn=entry`.
    pub script: String,
    /// Роль триггера:
    /// * `action` (умолчание) — выполнить скрипт, возможен переход.
    /// * `visibility` — условие видимости (только condition, без execute).
    /// * `reveal` — autorun при появлении (без гейта видимости).
    pub kind: String,
}

impl ContentTrigger {
    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();
        ContentTrigger {
            event: obj
                .get("event")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            script: obj
                .get("script")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            kind: obj
                .get("kind")
                .and_then(Value::as_str)
                .unwrap_or("action")
                .to_string(),
        }
    }

    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("event".into(), json!(self.event));
        map.insert("script".into(), json!(self.script));
        if self.kind != "action" {
            map.insert("kind".into(), json!(self.kind));
        }
        Value::Object(map)
    }

    /// Вывести behaviours из старого `scriptTriggers` для обратной совместимости.
    pub fn from_legacy_triggers(triggers: &HashMap<String, String>) -> Vec<ContentTrigger> {
        triggers
            .iter()
            .filter(|(_, path)| !path.is_empty())
            .map(|(event, path)| ContentTrigger {
                event: event.clone(),
                script: path.clone(),
                kind: "action".to_string(),
            })
            .collect()
    }
}

/// Элемент контента ноды.
#[derive(Debug, Clone, PartialEq)]
pub struct ContentItem {
    pub id: String,
    pub item_type: String,
    pub text: Option<String>,
    pub content_markdown: Option<String>,
    pub target_node_id: Option<String>,
    pub resource_path: Option<String>,
    /// Шаблон источника картинки (тип `image`): `{pic}`, `res/{level}.png`.
    /// Значение подставляет движок; пусто — статический `resource_path`.
    pub resource_expr: Option<String>,
    /// Формулы числовых полей: имя поля (`padding`, `itemSpacing`, `textSize`,
    /// `borderRadius`, `duration`) → выражение целиком (`hp / 2 + 16`; фигурные
    /// скобки плеер съедает, так что текстовый вид `{hp}/2 + 16` тоже работает).
    /// Пустая карта и пустые значения не сериализуются. Статическое число в
    /// самом поле остаётся — это дефолт и превью редактора, формула перекрывает
    /// его в плеере. Тот же приём, что у `resource_expr` у картинки.
    pub numeric_exprs: Option<HashMap<String, String>>,
    pub script_asset_id: Option<String>,
    pub plugin_id: Option<String>,
    pub plugin_type_id: Option<String>,
    pub plugin_data: Option<Map<String, Value>>,
    pub modal_buttons: Option<Vec<ModalButtonConfig>>,
    pub script_triggers: Option<HashMap<String, String>>,
    /// Новый формат поведений (заменяет scriptTriggers).
    /// При отсутствии выводится из `scriptTriggers`.
    pub behaviours: Option<Vec<ContentTrigger>>,
    pub variable_name: Option<String>,
    pub placeholder_text: Option<String>,
    pub button_text: Option<String>,
    pub background_color_value: Option<i64>,
    pub padding: Option<f64>,
    pub border_radius: Option<f64>,
    /// Шрифт айтема: путь ресурса (`res/fonts/xx.ttf`); null — наследовать.
    pub font_family: Option<String>,
    pub children: Option<Vec<ContentItem>>,
    pub flex: i64,
    pub cross_axis_alignment: String,
    pub row_text_alignment: String,
    pub is_hidden: bool,
    /// Слой заблокирован в редакторе канваса; для плеера не значит ничего.
    pub locked: bool,
    /// Показывать ли обратный отсчёт в модалке с автозакрытием. Раньше этот
    /// флаг ездил в `scriptTriggers` (`{"showTimer": "true"}`), где валидация
    /// видела в нём ссылку на скрипт и ругалась «скрипт удалён».
    pub show_timer: bool,
    pub text_fit: String,
    /// Размер шрифта текста в px; None — движковый дефолт 16. Поле плеерское,
    /// но без него ядро вырежет размер при round-trip'е ноды.
    pub text_size: Option<f64>,
    /// Цвет обводки текста (ARGB-число, как `backgroundColor`). Движок её не
    /// рисует, но без полей round-trip ноды стерёл бы настройку.
    pub text_outline_color_value: Option<i64>,
    /// Толщина контура обводки в px; None — клиентский дефолт.
    pub text_outline_width: Option<f64>,
    /// Режим появления текста в плеере: `none` | `typewriter` | `fade`.
    /// Движок его не исполняет, но без поля round-trip ноды его сотрёт.
    pub text_reveal: String,
    /// Видимых символов в секунду для [Self::text_reveal]. Одно поле на оба
    /// режима: в `fade` длительность проявления блока = длина текста / скорость.
    pub reveal_speed: f64,
    pub item_spacing: Option<f64>,
    /// Высота «стека» (type == 'stack') в px; null → дефолт 200.
    pub stack_height: Option<f64>,
    /// Ширина холста «стека» в пикселях дизайна; null → дефолт 720, который
    /// задан на стороне клиента (`kStackDesignWidth`). Меняет и то, во сколько
    /// стек ужмётся на экране: дети заданы в этих px, а не в реальных.
    pub stack_width: Option<f64>,
    /// Закрепление стека на экране: `top` | `bottom` | `center` | `fill`;
    /// null — стек идёт в потоке контента и скроллится вместе с ним.
    pub stack_pin: Option<String>,
    /// Рамка закрепления на экране: те же восемь чисел, что у ребёнка стека,
    /// только вместо холста — вьюпорт ноды (логические px). None по якорю —
    /// выводится из [Self::stack_pin] (легаси-ярлык), None по смещению — 0.
    /// Клиент считает геометрию (`stackPinRect`); ядро обязано донести поля до
    /// плеера нетронутыми, иначе round-trip ноды их сотрёт.
    pub pin_anchor_left: Option<f64>,
    pub pin_anchor_top: Option<f64>,
    pub pin_anchor_right: Option<f64>,
    pub pin_anchor_bottom: Option<f64>,
    pub pin_offset_left: Option<f64>,
    pub pin_offset_top: Option<f64>,
    pub pin_offset_right: Option<f64>,
    pub pin_offset_bottom: Option<f64>,
    /// Модальное окно: затемнение ноды, перехват тапов, закрытие по тапу вне.
    pub stack_modal: Option<bool>,
    /// Плотность затемнения 0..1; None — клиентский дефолт.
    pub stack_scrim: Option<f64>,
    /// Закрывать ли окно тапом вне рамки; None — да.
    pub stack_dismiss_on_tap_outside: Option<bool>,
    /// Картинка-фон холста: путь ресурса, его имя или uuid — тем же языком,
    /// что `resourcePath` у слоя-картинки. None — фон только цветом. Файл
    /// ищет клиент (`QuestImageSource`), ядро обязано донести значение
    /// нетронутым: round-trip ноды не имеет права терять фон.
    pub stack_background_path: Option<String>,
    /// Как фон ложится в холст: `cover` | `contain` | `fill` | `tile`
    /// (мозаика — режим для текстур). Дефолт в JSON не пишется.
    pub stack_background_fit: String,
    /// Имя группы в редакторе канваса стека; для плеера не значит ничего.
    pub group_name: Option<String>,
    /// Название слоя в редакторе; для плеера не значит ничего.
    pub layer_name: Option<String>,
    /// Направляющие редактора канваса, в px от левого/верхнего края холста;
    /// для плеера не значат ничего — как [Self::layer_name].
    pub guides_x: Option<Vec<f64>>,
    pub guides_y: Option<Vec<f64>>,
    /// Позиционирование ребёнка внутри «стека» (Godot-модель):
    /// left = anchor_left * W + offset_left (и т.д.). Дефолт — центр.
    pub anchor_left: f64,
    pub anchor_top: f64,
    pub anchor_right: f64,
    pub anchor_bottom: f64,
    pub offset_left: f64,
    pub offset_top: f64,
    pub offset_right: f64,
    pub offset_bottom: f64,
    /// Прозрачность 0..1 (дефолт 1.0) и поворот вокруг центра бокса в
    /// градусах (дефолт 0). Дефолты в JSON не пишутся. Поворот — только
    /// отрисовка: rect ребёнка остаётся ось-выровненным.
    pub opacity: f64,
    pub rotation: f64,
    /// Масштаб слоя вокруг центра бокса, 1.0 — исходный вид. Как и поворот,
    /// только отрисовка: rect, снаппинг и хит-тест бокса не знают про него.
    pub scale: f64,
    pub child_image_rounded_corners: Option<bool>,
    pub wrap_text: bool,
    /// null — использовать квестовый уровень wrap.
    pub wrap_text_override: Option<bool>,
    pub button_style: Option<ButtonStyleConfig>,
    pub volume: f64,
    pub sender_name: Option<String>,
    pub is_incoming: bool,
    pub avatar_path: Option<String>,
    pub avatar_color: Option<i64>,
    pub animate_in: bool,
    // ── Видео (type == 'video') ───────────────────────────────────────────
    pub video_url: Option<String>,
    pub video_source_type: Option<String>, // asset | url | youtube
    pub video_poster_path: Option<String>,
    pub video_autoplay: Option<bool>,
    pub video_loop: Option<bool>,
    pub video_muted: Option<bool>,
    pub video_show_controls: Option<bool>,
    pub video_allow_fullscreen: Option<bool>,
    pub video_allow_seek: Option<bool>,
    pub video_fit: Option<String>, // contain | cover | fill
    pub video_start_ms: Option<i64>,
    pub video_end_ms: Option<i64>,
    pub video_block_progress: Option<bool>,
    pub template_ref: Option<String>,
    pub template_version: Option<i64>,
    pub is_template_master: bool,
}

impl ContentItem {
    pub fn has_template_link(&self) -> bool {
        self.template_ref.as_deref().is_some_and(|r| !r.is_empty())
    }

    pub fn is_template_instance(&self) -> bool {
        self.has_template_link() && !self.is_template_master
    }

    pub fn is_template_master_item(&self) -> bool {
        self.has_template_link() && self.is_template_master
    }

    /// Все поведения айтема (новый формат или из старых scriptTriggers).
    pub fn resolved_behaviours(&self) -> Vec<ContentTrigger> {
        if let Some(ref behs) = self.behaviours
            && !behs.is_empty()
        {
            return behs.clone();
        }
        if let Some(ref triggers) = self.script_triggers {
            return ContentTrigger::from_legacy_triggers(triggers);
        }
        Vec::new()
    }

    fn color_from_int(v: Option<&Value>) -> Option<i64> {
        match v {
            Some(Value::Number(n)) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
            _ => None,
        }
    }

    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();

        let children = obj.get("children").and_then(Value::as_array).map(|a| {
            a.iter()
                .filter_map(Value::as_object)
                .map(|m| ContentItem::from_json(&Value::Object(m.clone())))
                .collect::<Vec<_>>()
        });

        let modal_buttons = obj.get("modalButtons").and_then(Value::as_array).map(|a| {
            a.iter()
                .filter_map(Value::as_object)
                .map(|m| ModalButtonConfig::from_json(&Value::Object(m.clone())))
                .collect::<Vec<_>>()
        });

        let legacy_wrap_text = parse_bool(obj.get("wrapText"), true);
        let item_type = obj
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();

        let wrap_text_override = if obj.contains_key("wrapTextOverride") {
            obj.get("wrapTextOverride").and_then(Value::as_bool)
        } else if (item_type == "button" || item_type == "input") && !legacy_wrap_text {
            Some(false)
        } else {
            None
        };

        let button_style = obj.get("buttonStyle").map(ButtonStyleConfig::from_json);

        let resource_path = obj
            .get("resourcePath")
            .and_then(Value::as_str)
            .or_else(|| obj.get("imagePath").and_then(Value::as_str))
            .map(str::to_string);

        let resource_expr = obj
            .get("resourceExpr")
            .and_then(Value::as_str)
            .map(str::to_string);

        // Пробел по краям съедаем сразу: значение читает плеер как шаблон, а
        // «нет формулы» должно отличаться от «формула — пустая строка».
        let numeric_exprs: Option<HashMap<String, String>> = obj
            .get("numericExprs")
            .and_then(Value::as_object)
            .map(|o| {
                o.iter()
                    .filter_map(|(k, v)| {
                        let expr = v.as_str()?.trim();
                        (!expr.is_empty()).then(|| (k.clone(), expr.to_string()))
                    })
                    .collect()
            })
            .filter(|map: &HashMap<String, String>| !map.is_empty());

        let mut item = ContentItem {
            id: obj
                .get("id")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_else(|| Uuid::new_v4().to_string()),
            item_type,
            text: obj.get("text").and_then(Value::as_str).map(str::to_string),
            content_markdown: obj
                .get("contentMarkdown")
                .and_then(Value::as_str)
                .map(str::to_string),
            target_node_id: obj
                .get("targetNodeId")
                .and_then(Value::as_str)
                .map(str::to_string),
            resource_path,
            resource_expr,
            numeric_exprs,
            script_asset_id: obj
                .get("scriptAssetId")
                .and_then(Value::as_str)
                .map(str::to_string),
            plugin_id: obj
                .get("pluginId")
                .and_then(Value::as_str)
                .map(str::to_string),
            plugin_type_id: obj
                .get("pluginTypeId")
                .and_then(Value::as_str)
                .map(str::to_string),
            plugin_data: obj.get("pluginData").and_then(Value::as_object).cloned(),
            modal_buttons,
            script_triggers: obj
                .get("scriptTriggers")
                .and_then(Value::as_object)
                .map(|o| {
                    o.iter()
                        .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
                        .collect()
                }),
            behaviours: parse_behaviours(&obj),
            variable_name: obj
                .get("variableName")
                .and_then(Value::as_str)
                .map(str::to_string),
            placeholder_text: obj
                .get("placeholderText")
                .and_then(Value::as_str)
                .map(str::to_string),
            button_text: obj
                .get("buttonText")
                .and_then(Value::as_str)
                .map(str::to_string),
            background_color_value: Self::color_from_int(obj.get("backgroundColor")),
            padding: obj.get("padding").and_then(Value::as_f64),
            border_radius: obj.get("borderRadius").and_then(Value::as_f64),
            font_family: obj
                .get("fontFamily")
                .and_then(Value::as_str)
                .map(str::to_string),
            children: children.filter(|c| !c.is_empty()),
            flex: obj.get("flex").and_then(Value::as_i64).unwrap_or(1),
            cross_axis_alignment: obj
                .get("crossAxisAlignment")
                .and_then(Value::as_str)
                .unwrap_or("center")
                .to_string(),
            row_text_alignment: obj
                .get("rowTextAlignment")
                .and_then(Value::as_str)
                .unwrap_or("center")
                .to_string(),
            is_hidden: parse_bool(obj.get("isHidden"), false),
            locked: parse_bool(obj.get("locked"), false),
            show_timer: parse_bool(obj.get("showTimer"), false),
            text_fit: obj
                .get("textFit")
                .and_then(Value::as_str)
                .unwrap_or("auto")
                .to_string(),
            text_size: obj.get("textSize").and_then(Value::as_f64),
            text_outline_color_value: Self::color_from_int(obj.get("textOutlineColor")),
            text_outline_width: obj.get("textOutlineWidth").and_then(Value::as_f64),
            text_reveal: parse_text_reveal(obj.get("textReveal")),
            reveal_speed: parse_reveal_speed(obj.get("revealSpeed")),
            item_spacing: obj.get("itemSpacing").and_then(Value::as_f64),
            stack_height: obj.get("stackHeight").and_then(Value::as_f64),
            stack_width: obj.get("stackWidth").and_then(Value::as_f64),
            stack_pin: parse_stack_pin(obj.get("stackPin")),
            pin_anchor_left: obj.get("pinAnchorLeft").and_then(Value::as_f64),
            pin_anchor_top: obj.get("pinAnchorTop").and_then(Value::as_f64),
            pin_anchor_right: obj.get("pinAnchorRight").and_then(Value::as_f64),
            pin_anchor_bottom: obj.get("pinAnchorBottom").and_then(Value::as_f64),
            pin_offset_left: obj.get("pinOffsetLeft").and_then(Value::as_f64),
            pin_offset_top: obj.get("pinOffsetTop").and_then(Value::as_f64),
            pin_offset_right: obj.get("pinOffsetRight").and_then(Value::as_f64),
            pin_offset_bottom: obj.get("pinOffsetBottom").and_then(Value::as_f64),
            stack_modal: obj.get("stackModal").and_then(Value::as_bool),
            stack_scrim: obj.get("stackScrim").and_then(Value::as_f64),
            stack_dismiss_on_tap_outside: obj
                .get("stackDismissOnTapOutside")
                .and_then(Value::as_bool),
            stack_background_path: parse_stack_background_path(obj.get("stackBackgroundPath")),
            stack_background_fit: parse_stack_background_fit(obj.get("stackBackgroundFit")),
            group_name: obj
                .get("groupName")
                .and_then(Value::as_str)
                .map(str::to_string),
            layer_name: obj
                .get("layerName")
                .and_then(Value::as_str)
                .map(str::to_string),
            guides_x: parse_guides(obj.get("guidesX")),
            guides_y: parse_guides(obj.get("guidesY")),
            anchor_left: parse_double(obj.get("anchorLeft"), 0.5),
            anchor_top: parse_double(obj.get("anchorTop"), 0.5),
            anchor_right: parse_double(obj.get("anchorRight"), 0.5),
            anchor_bottom: parse_double(obj.get("anchorBottom"), 0.5),
            offset_left: parse_double(obj.get("offsetLeft"), 0.0),
            offset_top: parse_double(obj.get("offsetTop"), 0.0),
            offset_right: parse_double(obj.get("offsetRight"), 0.0),
            offset_bottom: parse_double(obj.get("offsetBottom"), 0.0),
            opacity: parse_double(obj.get("opacity"), 1.0),
            rotation: parse_double(obj.get("rotation"), 0.0),
            scale: parse_double(obj.get("scale"), 1.0),
            child_image_rounded_corners: obj
                .get("childImageRoundedCorners")
                .and_then(Value::as_bool),
            wrap_text: legacy_wrap_text,
            wrap_text_override,
            button_style,
            volume: obj.get("volume").and_then(Value::as_f64).unwrap_or(1.0),
            sender_name: obj
                .get("senderName")
                .and_then(Value::as_str)
                .map(str::to_string),
            is_incoming: parse_bool(obj.get("isIncoming"), true),
            avatar_path: obj
                .get("avatarPath")
                .and_then(Value::as_str)
                .map(str::to_string),
            avatar_color: obj.get("avatarColor").and_then(Value::as_i64),
            animate_in: parse_bool(obj.get("animateIn"), true),
            video_url: obj
                .get("videoUrl")
                .and_then(Value::as_str)
                .map(str::to_string),
            video_source_type: obj
                .get("videoSourceType")
                .and_then(Value::as_str)
                .map(str::to_string),
            video_poster_path: obj
                .get("videoPosterPath")
                .and_then(Value::as_str)
                .map(str::to_string),
            video_autoplay: obj.get("videoAutoplay").and_then(Value::as_bool),
            video_loop: obj.get("videoLoop").and_then(Value::as_bool),
            video_muted: obj.get("videoMuted").and_then(Value::as_bool),
            video_show_controls: obj.get("videoShowControls").and_then(Value::as_bool),
            video_allow_fullscreen: obj.get("videoAllowFullscreen").and_then(Value::as_bool),
            video_allow_seek: obj.get("videoAllowSeek").and_then(Value::as_bool),
            video_fit: obj
                .get("videoFit")
                .and_then(Value::as_str)
                .map(str::to_string),
            video_start_ms: obj.get("videoStartMs").and_then(Value::as_i64),
            video_end_ms: obj.get("videoEndMs").and_then(Value::as_i64),
            video_block_progress: obj.get("videoBlockProgress").and_then(Value::as_bool),
            template_ref: obj
                .get("templateRef")
                .and_then(Value::as_str)
                .map(str::to_string),
            template_version: obj.get("templateVersion").and_then(Value::as_i64),
            is_template_master: parse_bool(obj.get("isTemplateMaster"), false),
        };
        // Флаг обратного отсчёта модалки исторически ехал в `scriptTriggers`
        // (`"showTimer": "true"`), хотя это не ссылка на скрипт. При чтении он
        // переезжает в своё поле и выпадает из карты: иначе валидация ищет
        // удалённый скрипт с именем «true», а редактор рисует занятый слот
        // триггера «showTimer». Так старые файлы квестов не теряют настройку.
        if let Some(triggers) = item.script_triggers.as_mut() {
            if triggers.remove("showTimer").as_deref() == Some("true") {
                item.show_timer = true;
            }
            if triggers.is_empty() {
                item.script_triggers = None;
            }
        }
        item
    }

    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("id".into(), json!(self.id));
        map.insert("type".into(), json!(self.item_type));
        if self.text.is_some() {
            map.insert("text".into(), json!(self.text));
        }
        if self.content_markdown.is_some() {
            map.insert("contentMarkdown".into(), json!(self.content_markdown));
        }
        if self.target_node_id.is_some() {
            map.insert("targetNodeId".into(), json!(self.target_node_id));
        }
        if self.resource_path.is_some() {
            map.insert("resourcePath".into(), json!(self.resource_path));
        }
        if self.resource_expr.is_some() {
            map.insert("resourceExpr".into(), json!(self.resource_expr));
        }
        // Пустую карту не отдаём: «нет формул» и «пустой объект» для Dart-зеркала
        // одно и то же, а лишний ключ мусорит в diff-ах сохранённых нод.
        if let Some(exprs) = &self.numeric_exprs
            && !exprs.is_empty()
        {
            map.insert("numericExprs".into(), json!(exprs));
        }
        if self.script_asset_id.is_some() {
            map.insert("scriptAssetId".into(), json!(self.script_asset_id));
        }
        if self.plugin_id.is_some() {
            map.insert("pluginId".into(), json!(self.plugin_id));
        }
        if self.plugin_type_id.is_some() {
            map.insert("pluginTypeId".into(), json!(self.plugin_type_id));
        }
        if self.plugin_data.is_some() {
            map.insert("pluginData".into(), json!(self.plugin_data));
        }
        if self.modal_buttons.is_some() {
            map.insert(
                "modalButtons".into(),
                json!(
                    self.modal_buttons
                        .as_ref()
                        .map(|b| { b.iter().map(|x| x.to_json()).collect::<Vec<_>>() })
                ),
            );
        }
        if self.script_triggers.is_some() {
            map.insert("scriptTriggers".into(), json!(self.script_triggers));
        }
        if let Some(behs) = &self.behaviours
            && !behs.is_empty()
        {
            map.insert(
                "behaviours".into(),
                json!(behs.iter().map(|b| b.to_json()).collect::<Vec<_>>()),
            );
        }
        if self.variable_name.is_some() {
            map.insert("variableName".into(), json!(self.variable_name));
        }
        if self.placeholder_text.is_some() {
            map.insert("placeholderText".into(), json!(self.placeholder_text));
        }
        if self.button_text.is_some() {
            map.insert("buttonText".into(), json!(self.button_text));
        }
        if self.background_color_value.is_some() {
            map.insert("backgroundColor".into(), json!(self.background_color_value));
        }
        if self.padding.is_some() {
            map.insert("padding".into(), json!(self.padding));
        }
        if self.border_radius.is_some() {
            map.insert("borderRadius".into(), json!(self.border_radius));
        }
        if self.font_family.is_some() {
            map.insert("fontFamily".into(), json!(self.font_family));
        }
        if self.children.is_some() {
            map.insert(
                "children".into(),
                json!(
                    self.children
                        .as_ref()
                        .map(|c| { c.iter().map(|x| x.to_json()).collect::<Vec<_>>() })
                ),
            );
        }
        map.insert("flex".into(), json!(self.flex));
        map.insert(
            "crossAxisAlignment".into(),
            json!(self.cross_axis_alignment),
        );
        map.insert("rowTextAlignment".into(), json!(self.row_text_alignment));
        map.insert("isHidden".into(), json!(self.is_hidden));
        map.insert("locked".into(), json!(self.locked));
        // Пишем только включённый флаг: false — это отсутствие ключа,
        // чтобы round-trip не плодил поле в каждом айтеме.
        if self.show_timer {
            map.insert("showTimer".into(), json!(true));
        }
        map.insert("textFit".into(), json!(self.text_fit));
        if let Some(v) = self.text_size {
            map.insert("textSize".into(), json!(v));
        }
        // Толщина без цвета — обводки нет, поэтому пишем их только вместе.
        if let Some(v) = self.text_outline_color_value {
            map.insert("textOutlineColor".into(), json!(v));
            if let Some(w) = self.text_outline_width {
                map.insert("textOutlineWidth".into(), json!(w));
            }
        }
        // Дефолты не пишем: «none» и 40 — это то, что было всегда; ключ
        // появляется, только когда автор включил проявление или крутил скорость.
        if self.text_reveal != "none" {
            map.insert("textReveal".into(), json!(self.text_reveal));
        }
        if (self.reveal_speed - 40.0).abs() > f64::EPSILON {
            map.insert("revealSpeed".into(), json!(self.reveal_speed));
        }
        if self.item_spacing.is_some() {
            map.insert("itemSpacing".into(), json!(self.item_spacing));
        }
        if self.stack_height.is_some() {
            map.insert("stackHeight".into(), json!(self.stack_height));
        }
        if self.stack_width.is_some() {
            map.insert("stackWidth".into(), json!(self.stack_width));
        }
        if let Some(pin) = &self.stack_pin {
            map.insert("stackPin".into(), json!(pin));
        }
        if self.pin_anchor_left.is_some() {
            map.insert("pinAnchorLeft".into(), json!(self.pin_anchor_left));
        }
        if self.pin_anchor_top.is_some() {
            map.insert("pinAnchorTop".into(), json!(self.pin_anchor_top));
        }
        if self.pin_anchor_right.is_some() {
            map.insert("pinAnchorRight".into(), json!(self.pin_anchor_right));
        }
        if self.pin_anchor_bottom.is_some() {
            map.insert("pinAnchorBottom".into(), json!(self.pin_anchor_bottom));
        }
        if self.pin_offset_left.is_some() {
            map.insert("pinOffsetLeft".into(), json!(self.pin_offset_left));
        }
        if self.pin_offset_top.is_some() {
            map.insert("pinOffsetTop".into(), json!(self.pin_offset_top));
        }
        if self.pin_offset_right.is_some() {
            map.insert("pinOffsetRight".into(), json!(self.pin_offset_right));
        }
        if self.pin_offset_bottom.is_some() {
            map.insert("pinOffsetBottom".into(), json!(self.pin_offset_bottom));
        }
        for (key, flag) in [
            ("stackModal", self.stack_modal),
            (
                "stackDismissOnTapOutside",
                self.stack_dismiss_on_tap_outside,
            ),
        ] {
            if let Some(value) = flag {
                map.insert(key.into(), json!(value));
            }
        }
        if self.stack_scrim.is_some() {
            map.insert("stackScrim".into(), json!(self.stack_scrim));
        }
        // Фон — пара полей: без пути режим не пишут, иначе стек без фона
        // таскал бы за собой бессмысленный ключ (как в Dart-кодеке).
        if let Some(path) = &self.stack_background_path {
            map.insert("stackBackgroundPath".into(), json!(path));
            if self.stack_background_fit != STACK_BACKGROUND_FIT_DEFAULT {
                map.insert(
                    "stackBackgroundFit".into(),
                    json!(&self.stack_background_fit),
                );
            }
        }
        if let Some(name) = &self.group_name {
            map.insert("groupName".into(), json!(name));
        }
        if let Some(name) = &self.layer_name {
            map.insert("layerName".into(), json!(name));
        }
        for (key, guides) in [("guidesX", &self.guides_x), ("guidesY", &self.guides_y)] {
            if let Some(guides) = guides {
                map.insert(key.into(), json!(guides));
            }
        }
        if (self.anchor_left - 0.5).abs() > f64::EPSILON {
            map.insert("anchorLeft".into(), json!(self.anchor_left));
        }
        if (self.anchor_top - 0.5).abs() > f64::EPSILON {
            map.insert("anchorTop".into(), json!(self.anchor_top));
        }
        if (self.anchor_right - 0.5).abs() > f64::EPSILON {
            map.insert("anchorRight".into(), json!(self.anchor_right));
        }
        if (self.anchor_bottom - 0.5).abs() > f64::EPSILON {
            map.insert("anchorBottom".into(), json!(self.anchor_bottom));
        }
        if self.offset_left.abs() > f64::EPSILON {
            map.insert("offsetLeft".into(), json!(self.offset_left));
        }
        if self.offset_top.abs() > f64::EPSILON {
            map.insert("offsetTop".into(), json!(self.offset_top));
        }
        if self.offset_right.abs() > f64::EPSILON {
            map.insert("offsetRight".into(), json!(self.offset_right));
        }
        if self.offset_bottom.abs() > f64::EPSILON {
            map.insert("offsetBottom".into(), json!(self.offset_bottom));
        }
        if (self.opacity - 1.0).abs() > f64::EPSILON {
            map.insert("opacity".into(), json!(self.opacity));
        }
        if self.rotation.abs() > f64::EPSILON {
            map.insert("rotation".into(), json!(self.rotation));
        }
        if (self.scale - 1.0).abs() > f64::EPSILON {
            map.insert("scale".into(), json!(self.scale));
        }
        if self.child_image_rounded_corners.is_some() {
            map.insert(
                "childImageRoundedCorners".into(),
                json!(self.child_image_rounded_corners),
            );
        }
        map.insert("wrapText".into(), json!(self.wrap_text));
        if self.wrap_text_override.is_some() {
            map.insert("wrapTextOverride".into(), json!(self.wrap_text_override));
        }
        if let Some(style) = &self.button_style {
            map.insert("buttonStyle".into(), style.to_json());
        }
        map.insert("volume".into(), json!(self.volume));
        if self.sender_name.is_some() {
            map.insert("senderName".into(), json!(self.sender_name));
        }
        map.insert("isIncoming".into(), json!(self.is_incoming));
        if self.avatar_path.is_some() {
            map.insert("avatarPath".into(), json!(self.avatar_path));
        }
        if self.avatar_color.is_some() {
            map.insert("avatarColor".into(), json!(self.avatar_color));
        }
        map.insert("animateIn".into(), json!(self.animate_in));
        if self.video_url.is_some() {
            map.insert("videoUrl".into(), json!(self.video_url));
        }
        if self.video_source_type.is_some() {
            map.insert("videoSourceType".into(), json!(self.video_source_type));
        }
        if self.video_poster_path.is_some() {
            map.insert("videoPosterPath".into(), json!(self.video_poster_path));
        }
        if self.video_autoplay.is_some() {
            map.insert("videoAutoplay".into(), json!(self.video_autoplay));
        }
        if self.video_loop.is_some() {
            map.insert("videoLoop".into(), json!(self.video_loop));
        }
        if self.video_muted.is_some() {
            map.insert("videoMuted".into(), json!(self.video_muted));
        }
        if self.video_show_controls.is_some() {
            map.insert("videoShowControls".into(), json!(self.video_show_controls));
        }
        if self.video_allow_fullscreen.is_some() {
            map.insert(
                "videoAllowFullscreen".into(),
                json!(self.video_allow_fullscreen),
            );
        }
        if self.video_allow_seek.is_some() {
            map.insert("videoAllowSeek".into(), json!(self.video_allow_seek));
        }
        if self.video_fit.is_some() {
            map.insert("videoFit".into(), json!(self.video_fit));
        }
        if self.video_start_ms.is_some() {
            map.insert("videoStartMs".into(), json!(self.video_start_ms));
        }
        if self.video_end_ms.is_some() {
            map.insert("videoEndMs".into(), json!(self.video_end_ms));
        }
        if self.video_block_progress.is_some() {
            map.insert(
                "videoBlockProgress".into(),
                json!(self.video_block_progress),
            );
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

/// Где на экране живёт стек (type == 'stack'). Пусто — в потоке контента.
/// `fill` — на всё доступное место: холст растягивается по ширине, а его
/// высота в px дизайна добирается так, чтобы масштаб по осям остался равным.
/// `left`/`right` — колонки у края: из них же собирается ряд панелей.
/// `custom` — рамку задают якоря и отступы закрепления (`pinAnchor*` +
/// `pinOffset*`), а не ярлык: без этого значения редактор не мог бы положить
/// панель в угол или в половину экрана.
pub const STACK_PIN_VALUES: [&str; 7] =
    ["top", "bottom", "left", "right", "center", "fill", "custom"];

/// Значение `stackPin`: только известный край, иначе `None` — автор мог
/// написать значение руками, а рендерер понимает ровно эти.
fn parse_stack_pin(value: Option<&Value>) -> Option<String> {
    let raw = value?.as_str()?.trim().to_lowercase();
    STACK_PIN_VALUES
        .iter()
        .copied()
        .find(|v| *v == raw)
        .map(str::to_string)
}

/// Режимы появления текста в плеере. Движок их не исполняет — он обязан
/// донести поле до клиента, иначе round-trip ноды сбросит авторскую настройку.
pub const TEXT_REVEAL_VALUES: [&str; 3] = ["none", "typewriter", "fade"];
pub const TEXT_REVEAL_DEFAULT: &str = "none";
pub const REVEAL_SPEED_DEFAULT: f64 = 40.0;
pub const REVEAL_SPEED_MIN: f64 = 5.0;
pub const REVEAL_SPEED_MAX: f64 = 200.0;

/// Значение `textReveal`: только известный режим, иначе дефолт — написанное
/// руками «Typewriter» не должно молча выключать анимацию.
fn parse_text_reveal(value: Option<&Value>) -> String {
    let raw = value
        .and_then(Value::as_str)
        .unwrap_or(TEXT_REVEAL_DEFAULT)
        .trim()
        .to_lowercase();
    TEXT_REVEAL_VALUES
        .iter()
        .copied()
        .find(|v| *v == raw)
        .unwrap_or(TEXT_REVEAL_DEFAULT)
        .to_string()
}

/// Скорость проявления: ноль или отрицательное число остановили бы анимацию
/// навсегда, поэтому значение зажимается в рабочий диапазон.
fn parse_reveal_speed(value: Option<&Value>) -> f64 {
    match value.and_then(Value::as_f64) {
        Some(v) => v.clamp(REVEAL_SPEED_MIN, REVEAL_SPEED_MAX),
        None => REVEAL_SPEED_DEFAULT,
    }
}

/// Режимы картинки-фона стека; `tile` — мозаика, режим текстур и паттернов.
pub const STACK_BACKGROUND_FIT_VALUES: [&str; 4] = ["cover", "contain", "fill", "tile"];
pub const STACK_BACKGROUND_FIT_DEFAULT: &str = "cover";

/// Значение `stackBackgroundFit`: только известный режим, иначе дефолт.
/// Клиент (`normalizeStackBackgroundFit`) чистит так же — обе стороны должны
/// одинаково реагировать на написанное руками «мозаика».
fn parse_stack_background_fit(value: Option<&Value>) -> String {
    let raw = value
        .and_then(Value::as_str)
        .map(str::trim)
        .map(str::to_lowercase)
        .unwrap_or_default();
    STACK_BACKGROUND_FIT_VALUES
        .iter()
        .copied()
        .find(|v| *v == raw)
        .unwrap_or(STACK_BACKGROUND_FIT_DEFAULT)
        .to_string()
}

/// Путь картинки-фона: пустая строка — «фона нет», а не «путь пустой», иначе
/// резолвер полез бы искать файл по пустому имени.
fn parse_stack_background_path(value: Option<&Value>) -> Option<String> {
    let raw = value?.as_str()?.trim();
    (!raw.is_empty()).then(|| raw.to_string())
}

/// Направляющие редактора: массив чисел. Отсутствующее поле, не-массив и
/// пустой массив — одно и то же (`None`), чтобы «нет направляющих» не ездило
/// через json пустым списком. Нечисловые элементы молча выкидываются:
/// редактирует человек, а не протокол.
fn parse_guides(value: Option<&Value>) -> Option<Vec<f64>> {
    let parsed: Vec<f64> = value?
        .as_array()?
        .iter()
        .filter_map(Value::as_f64)
        .collect();
    (!parsed.is_empty()).then_some(parsed)
}

/// Парсинг поля `behaviours` из JSON объекта айтема.
fn parse_behaviours(obj: &Map<String, Value>) -> Option<Vec<ContentTrigger>> {
    let arr = obj.get("behaviours")?.as_array()?;
    if arr.is_empty() {
        return None;
    }
    let result: Vec<ContentTrigger> = arr.iter().map(ContentTrigger::from_json).collect();
    if result.is_empty() {
        None
    } else {
        Some(result)
    }
}

#[cfg(test)]
mod content_trigger_tests {
    use super::*;
    use std::collections::HashMap;

    // ---------------------------------------------------------------------------
    // ContentTrigger JSON roundtrip
    // ---------------------------------------------------------------------------

    #[test]
    fn parse_basic_action_trigger() {
        let json = serde_json::json!({"event": "onPress", "script": "scripts/btn.lua"});
        let ct = ContentTrigger::from_json(&json);
        assert_eq!(ct.event, "onPress");
        assert_eq!(ct.script, "scripts/btn.lua");
        assert_eq!(ct.kind, "action"); // default
    }

    #[test]
    fn parse_visibility_trigger() {
        let json = serde_json::json!({
            "event": "onAppear",
            "script": "scripts/show.json",
            "kind": "visibility"
        });
        let ct = ContentTrigger::from_json(&json);
        assert_eq!(ct.event, "onAppear");
        assert_eq!(ct.kind, "visibility");
    }

    #[test]
    fn parse_reveal_trigger() {
        let json = serde_json::json!({
            "event": "onReveal",
            "script": "scripts/anim.json",
            "kind": "reveal"
        });
        let ct = ContentTrigger::from_json(&json);
        assert_eq!(ct.event, "onReveal");
        assert_eq!(ct.kind, "reveal");
    }

    #[test]
    fn parse_empty_json_defaults() {
        let ct = ContentTrigger::from_json(&serde_json::json!({}));
        assert_eq!(ct.event, "");
        assert_eq!(ct.script, "");
        assert_eq!(ct.kind, "action");
    }

    #[test]
    fn to_json_roundtrip_action() {
        let ct = ContentTrigger {
            event: "onPress".into(),
            script: "scripts/btn.json".into(),
            kind: "action".into(),
        };
        let json = ct.to_json();
        assert_eq!(json["event"], "onPress");
        assert_eq!(json["script"], "scripts/btn.json");
        // "kind": "action" should be omitted (it's the default)
        assert!(json.get("kind").is_none());
    }

    #[test]
    fn to_json_roundtrip_visibility() {
        let ct = ContentTrigger {
            event: "onAppear".into(),
            script: "scripts/show.json".into(),
            kind: "visibility".into(),
        };
        let json = ct.to_json();
        assert_eq!(json["kind"], "visibility");
    }

    // ---------------------------------------------------------------------------
    // Legacy scriptTriggers → ContentTrigger
    // ---------------------------------------------------------------------------

    #[test]
    fn from_legacy_triggers_converts_all_entries() {
        let mut triggers = HashMap::new();
        triggers.insert("onPress".into(), "scripts/btn.json".into());
        triggers.insert("onAppear".into(), "scripts/show.json".into());
        triggers.insert("onSubmit".into(), "scripts/input.json".into());

        let behs = ContentTrigger::from_legacy_triggers(&triggers);
        assert_eq!(behs.len(), 3);

        let press = behs.iter().find(|b| b.event == "onPress").unwrap();
        assert_eq!(press.script, "scripts/btn.json");
        assert_eq!(press.kind, "action");

        let appear = behs.iter().find(|b| b.event == "onAppear").unwrap();
        assert_eq!(appear.script, "scripts/show.json");
        assert_eq!(appear.kind, "action");
    }

    #[test]
    fn from_legacy_skips_empty_paths() {
        let mut triggers = HashMap::new();
        triggers.insert("onPress".into(), "".into());
        triggers.insert("onAppear".into(), "scripts/show.json".into());

        let behs = ContentTrigger::from_legacy_triggers(&triggers);
        assert_eq!(behs.len(), 1);
        assert_eq!(behs[0].event, "onAppear");
    }

    // ---------------------------------------------------------------------------
    // ContentItem.resolved_behaviours()
    // ---------------------------------------------------------------------------

    #[test]
    fn resolved_behaviours_prefers_new_format() {
        let item_json = serde_json::json!({
            "id": "b1",
            "type": "button",
            "behaviours": [
                {"event": "onPress", "script": "scripts/new.lua"}
            ],
            "scriptTriggers": {"onPress": "scripts/old.json"}
        });
        let item = ContentItem::from_json(&item_json);
        let behs = item.resolved_behaviours();
        assert_eq!(behs.len(), 1);
        assert_eq!(behs[0].script, "scripts/new.lua");
    }

    #[test]
    fn resolved_behaviours_falls_back_to_legacy() {
        let item_json = serde_json::json!({
            "id": "b1",
            "type": "button",
            "scriptTriggers": {"onPress": "scripts/old.json", "onAppear": "scripts/show.json"}
        });
        let item = ContentItem::from_json(&item_json);
        let behs = item.resolved_behaviours();
        assert_eq!(behs.len(), 2);
        // All should have kind=action from legacy
        assert!(behs.iter().all(|b| b.kind == "action"));
    }

    #[test]
    fn resolved_behaviours_empty_when_no_triggers() {
        let item_json = serde_json::json!({"id": "t1", "type": "text"});
        let item = ContentItem::from_json(&item_json);
        assert!(item.resolved_behaviours().is_empty());
    }

    #[test]
    fn resolved_behaviours_empty_when_behaviours_is_empty_array() {
        let item_json = serde_json::json!({
            "id": "b1",
            "type": "button",
            "behaviours": []
        });
        let item = ContentItem::from_json(&item_json);
        assert!(item.resolved_behaviours().is_empty());
    }

    #[test]
    fn to_json_includes_behaviours() {
        let item_json = serde_json::json!({
            "id": "b1",
            "type": "button",
            "behaviours": [
                {"event": "onPress", "script": "scripts/btn.lua"},
                {"event": "onAppear", "script": "scripts/show.json", "kind": "visibility"}
            ]
        });
        let item = ContentItem::from_json(&item_json);
        let json = item.to_json();
        let behs = json["behaviours"].as_array().unwrap();
        assert_eq!(behs.len(), 2);
        // action kind is omitted
        assert!(behs[0].get("kind").is_none());
        assert_eq!(behs[1]["kind"], "visibility");
    }

    #[test]
    fn to_json_omits_behaviours_when_none() {
        let item_json = serde_json::json!({
            "id": "t1",
            "type": "text",
            "scriptTriggers": {"onPress": "scripts/btn.json"}
        });
        let item = ContentItem::from_json(&item_json);
        let json = item.to_json();
        assert!(json.get("behaviours").is_none());
        assert!(json.get("scriptTriggers").is_some());
    }

    #[test]
    fn font_family_roundtrip_and_omitted_when_none() {
        // Заданный шрифт айтема переживает from_json → to_json.
        let item_json = serde_json::json!({
            "id": "t2",
            "type": "text",
            "text": "hello",
            "fontFamily": "res/fonts/display.ttf"
        });
        let item = ContentItem::from_json(&item_json);
        assert_eq!(item.font_family.as_deref(), Some("res/fonts/display.ttf"));
        let json = item.to_json();
        assert_eq!(json["fontFamily"], "res/fonts/display.ttf");

        // Без шрифта поле не пишется (обратная совместимость JSON).
        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "t3",
            "type": "text",
            "text": "hello"
        }));
        assert!(plain.font_family.is_none());
        assert!(plain.to_json().get("fontFamily").is_none());
    }

    #[test]
    fn stack_pin_roundtrip_and_unknown_value() {
        let pinned = ContentItem::from_json(&serde_json::json!({
            "id": "s1",
            "type": "stack",
            "stackPin": " Bottom ",
        }));
        assert_eq!(pinned.stack_pin.as_deref(), Some("bottom"));
        assert_eq!(pinned.to_json()["stackPin"], json!("bottom"));

        // Неизвестное значение — как «не закреплено»: плеер не должен
        // угадывать край.
        let junk = ContentItem::from_json(&serde_json::json!({
            "id": "s2",
            "type": "stack",
            "stackPin": "topLeft",
        }));
        assert_eq!(junk.stack_pin, None);
        assert!(junk.to_json().get("stackPin").is_none());

        let plain = ContentItem::from_json(&serde_json::json!({"id": "s3", "type": "stack"}));
        assert_eq!(plain.stack_pin, None);

        // `fill` — режим «на весь экран», тот же разбор, что и у краёв.
        let filled = ContentItem::from_json(&serde_json::json!({
            "id": "s4",
            "type": "stack",
            "stackPin": "FILL",
        }));
        assert_eq!(filled.stack_pin.as_deref(), Some("fill"));
        assert_eq!(filled.to_json()["stackPin"], json!("fill"));
    }

    /// Рамку закрепления считает клиент, но пройти через ядро она обязана
    /// целиком: `next_item` отдаёт плееру json, собранный здесь, и поле,
    /// которого нет в структуре, исчезает из квеста молча.
    #[test]
    fn stack_pin_box_roundtrip() {
        let stack = ContentItem::from_json(&serde_json::json!({
            "id": "s1",
            "type": "stack",
            "stackPin": "custom",
            "pinAnchorLeft": 0.0,
            "pinAnchorTop": 0.25,
            "pinAnchorRight": 0.5,
            "pinAnchorBottom": 0.25,
            "pinOffsetLeft": 8.0,
            "pinOffsetTop": -40.0,
            "pinOffsetRight": 0.0,
            "pinOffsetBottom": 120.0,
            "stackModal": true,
            "stackScrim": 0.4,
            "stackDismissOnTapOutside": false,
        }));
        let json = stack.to_json();
        // `custom` — легальное значение: без него ядро выкидывало бы
        // закрепление, и рамка, собранная редактором, доезжала до плеера
        // обычным слоем в потоке.
        assert_eq!(json["stackPin"], json!("custom"));
        assert_eq!(json["pinAnchorLeft"], json!(0.0));
        assert_eq!(json["pinAnchorRight"], json!(0.5));
        assert_eq!(json["pinOffsetTop"], json!(-40.0));
        assert_eq!(json["pinOffsetBottom"], json!(120.0));
        assert_eq!(json["stackModal"], json!(true));
        assert_eq!(json["stackScrim"], json!(0.4));
        assert_eq!(json["stackDismissOnTapOutside"], json!(false));

        // Незаданные поля не плодят нули в файле.
        let plain = ContentItem::from_json(&serde_json::json!({"id": "s2", "type": "stack"}));
        let plain_json = plain.to_json();
        for key in [
            "pinAnchorLeft",
            "pinOffsetLeft",
            "stackModal",
            "stackScrim",
            "stackDismissOnTapOutside",
        ] {
            assert!(plain_json.get(key).is_none(), "{key} не должен писаться");
        }
    }

    #[test]
    fn stack_width_roundtrip() {
        let stack = ContentItem::from_json(&serde_json::json!({
            "id": "s1",
            "type": "stack",
            "stackWidth": 360.0,
            "stackHeight": 640.0,
        }));
        assert_eq!(stack.stack_width, Some(360.0));
        assert_eq!(stack.stack_height, Some(640.0));

        // Дефолт не сериализуется: старый файл не обрастает нулями.
        let plain = ContentItem::from_json(&serde_json::json!({"id": "s2", "type": "stack"}));
        assert_eq!(plain.stack_width, None);
        assert!(plain.to_json().get("stackWidth").is_none());
    }

    #[test]
    fn stack_background_roundtrip_and_defaults() {
        let stack = ContentItem::from_json(&serde_json::json!({
            "id": "s1",
            "type": "stack",
            "stackBackgroundPath": "res/images/закат.png",
            // Регистр и пробелы — рука автора: ядро чистит их так же, как
            // клиент, иначе round-trip вернул бы «мозаику» нулём.
            "stackBackgroundFit": " TILE ",
        }));
        assert_eq!(
            stack.stack_background_path.as_deref(),
            Some("res/images/закат.png")
        );
        assert_eq!(stack.stack_background_fit, "tile");

        let json = stack.to_json();
        assert_eq!(json["stackBackgroundPath"], json!("res/images/закат.png"));
        assert_eq!(json["stackBackgroundFit"], json!("tile"));

        // Ни пути, ни режима по умолчанию в файле быть не должно.
        let plain = ContentItem::from_json(&serde_json::json!({"id": "s2", "type": "stack"}));
        assert_eq!(plain.stack_background_fit, "cover");
        let plain_json = plain.to_json();
        for key in ["stackBackgroundPath", "stackBackgroundFit"] {
            assert!(plain_json.get(key).is_none(), "{key} не должен писаться");
        }

        // Незнакомый режим и путь-пробел не оставляют следов: иначе «фона нет»
        // сериализовался бы как фон с битым источником.
        let junk = ContentItem::from_json(&serde_json::json!({
            "id": "s3",
            "type": "stack",
            "stackBackgroundPath": "   ",
            "stackBackgroundFit": "мозаика",
        }));
        assert!(junk.stack_background_path.is_none());
        assert_eq!(junk.stack_background_fit, "cover");
        assert!(junk.to_json().get("stackBackgroundFit").is_none());
    }

    #[test]
    fn stack_anchors_roundtrip_and_defaults() {
        // Стек с ребёнком, прижатым к верхнему левому углу со смещением.
        let json = serde_json::json!({
            "id": "s1",
            "type": "stack",
            "stackHeight": 240.0,
            "children": [{
                "id": "c1",
                "type": "text",
                "text": "hi",
                "anchorLeft": 0.0,
                "anchorTop": 0.0,
                "anchorRight": 0.0,
                "anchorBottom": 0.0,
                "offsetLeft": 12.0,
                "offsetTop": 8.0,
            }]
        });
        let stack = ContentItem::from_json(&json);
        assert_eq!(stack.stack_height, Some(240.0));
        let child = stack.children.as_ref().unwrap()[0].clone();
        assert_eq!(child.anchor_left, 0.0);
        assert_eq!(child.anchor_top, 0.0);
        assert_eq!(child.anchor_right, 0.0);
        assert_eq!(child.anchor_bottom, 0.0);
        assert_eq!(child.offset_left, 12.0);
        assert_eq!(child.offset_top, 8.0);
        assert_eq!(child.offset_right, 0.0);
        assert_eq!(child.offset_bottom, 0.0);

        let out = stack.to_json();
        assert_eq!(out["stackHeight"], 240.0);
        assert_eq!(out["children"][0]["offsetTop"], 8.0);
        // Дефолтные offsetRight/offsetBottom в JSON не пишутся.
        assert!(out["children"][0].get("offsetRight").is_none());

        // Без полей — дефолт «по центру».
        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "c2",
            "type": "text",
            "text": "hi"
        }));
        assert_eq!(plain.anchor_left, 0.5);
        assert_eq!(plain.anchor_top, 0.5);
        assert_eq!(plain.anchor_right, 0.5);
        assert_eq!(plain.anchor_bottom, 0.5);
        assert_eq!(plain.offset_left, 0.0);
        assert!(plain.to_json().get("anchorLeft").is_none());
    }

    #[test]
    fn text_size_survives_roundtrip_and_stays_absent_by_default() {
        let sized = ContentItem::from_json(&serde_json::json!({
            "id": "t1",
            "type": "text",
            "text": "привет",
            "textSize": 28.0,
        }));
        assert_eq!(sized.text_size, Some(28.0));
        assert_eq!(sized.to_json()["textSize"], json!(28.0));

        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "t2",
            "type": "text",
            "text": "привет",
        }));
        assert_eq!(plain.text_size, None);
        assert!(plain.to_json().get("textSize").is_none());
    }

    #[test]
    fn text_outline_survives_roundtrip_and_stays_absent_by_default() {
        let outlined = ContentItem::from_json(&serde_json::json!({
            "id": "t1",
            "type": "text",
            "text": "привет",
            "textOutlineColor": -16776961,
            "textOutlineWidth": 3.0,
        }));
        assert_eq!(outlined.text_outline_color_value, Some(-16776961));
        assert_eq!(outlined.text_outline_width, Some(3.0));
        assert_eq!(outlined.to_json()["textOutlineColor"], json!(-16776961));
        assert_eq!(outlined.to_json()["textOutlineWidth"], json!(3.0));

        // Толщина без цвета — обводки нет, и в json она не ездит одна.
        let width_only = ContentItem::from_json(&serde_json::json!({
            "id": "t2",
            "type": "text",
            "textOutlineWidth": 4.0,
        }));
        assert_eq!(width_only.text_outline_width, Some(4.0));
        assert!(width_only.to_json().get("textOutlineColor").is_none());
        assert!(width_only.to_json().get("textOutlineWidth").is_none());

        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "t3",
            "type": "text",
        }));
        assert_eq!(plain.text_outline_color_value, None);
        assert!(plain.to_json().get("textOutlineColor").is_none());
    }

    #[test]
    fn resource_expr_survives_roundtrip_and_stays_absent_by_default() {
        let bound = ContentItem::from_json(&serde_json::json!({
            "id": "i1",
            "type": "image",
            "resourcePath": "res/images/old.png",
            "resourceExpr": "{pic}",
        }));
        assert_eq!(bound.resource_expr.as_deref(), Some("{pic}"));
        assert_eq!(bound.to_json()["resourceExpr"], json!("{pic}"));
        assert_eq!(bound.to_json()["resourcePath"], json!("res/images/old.png"));

        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "i2",
            "type": "image",
            "resourcePath": "res/images/old.png",
        }));
        assert_eq!(plain.resource_expr, None);
        assert!(plain.to_json().get("resourceExpr").is_none());
    }

    #[test]
    fn numeric_exprs_survive_roundtrip_and_empty_ones_are_dropped() {
        let bound = ContentItem::from_json(&serde_json::json!({
            "id": "i1",
            "type": "spacer",
            "padding": 16.0,
            "numericExprs": {
                "padding": " {hp}/2 + 16 ",
                "itemSpacing": "",
            },
        }));
        // Пробел съеден, пустая формула не живёт в модели.
        let exprs = bound.numeric_exprs.clone().unwrap();
        assert_eq!(
            exprs.get("padding").map(String::as_str),
            Some("{hp}/2 + 16")
        );
        assert!(!exprs.contains_key("itemSpacing"));
        // Статическое число остаётся — на нём редактор рисует превью.
        assert_eq!(bound.padding, Some(16.0));
        assert_eq!(
            bound.to_json()["numericExprs"],
            json!({"padding": "{hp}/2 + 16"})
        );

        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "i2",
            "type": "spacer",
            "padding": 16.0,
            "numericExprs": {},
        }));
        assert_eq!(plain.numeric_exprs, None);
        assert!(plain.to_json().get("numericExprs").is_none());
    }

    #[test]
    fn opacity_rotation_and_scale_roundtrip_and_defaults() {
        let json = serde_json::json!({
            "id": "s1",
            "type": "stack",
            "children": [{
                "id": "c1",
                "type": "text",
                "text": "hi",
                "opacity": 0.4,
                "rotation": -30.0,
                "scale": 1.8,
            }]
        });
        let stack = ContentItem::from_json(&json);
        let child = stack.children.as_ref().unwrap()[0].clone();
        assert_eq!(child.opacity, 0.4);
        assert_eq!(child.rotation, -30.0);
        assert_eq!(child.scale, 1.8);

        let out = stack.to_json();
        assert_eq!(out["children"][0]["opacity"], 0.4);
        assert_eq!(out["children"][0]["rotation"], -30.0);
        assert_eq!(out["children"][0]["scale"], 1.8);

        // Старый файл без полей: непрозрачно и без поворота, в JSON не пишем.
        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "c2",
            "type": "text",
            "text": "hi"
        }));
        assert_eq!(plain.opacity, 1.0);
        assert_eq!(plain.rotation, 0.0);
        assert_eq!(plain.scale, 1.0);
        let plain_json = plain.to_json();
        assert!(plain_json.get("opacity").is_none());
        assert!(plain_json.get("rotation").is_none());
        assert!(plain_json.get("scale").is_none());
    }

    #[test]
    fn text_reveal_survives_roundtrip_and_stays_absent_by_default() {
        let typed = ContentItem::from_json(&serde_json::json!({
            "id": "r1",
            "type": "text",
            "text": "Привет",
            "textReveal": "typewriter",
            "revealSpeed": 18.0,
        }));
        assert_eq!(typed.text_reveal, "typewriter");
        assert_eq!(typed.reveal_speed, 18.0);
        let out = typed.to_json();
        assert_eq!(out["textReveal"], "typewriter");
        assert_eq!(out["revealSpeed"], 18.0);

        // Легаси-файл без полей: мгновенное появление, ключей в JSON нет —
        // иначе round-trip добавил бы их в каждый текстовый айтм квеста.
        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "r2",
            "type": "text",
            "text": "Привет",
        }));
        assert_eq!(plain.text_reveal, TEXT_REVEAL_DEFAULT);
        assert_eq!(plain.reveal_speed, REVEAL_SPEED_DEFAULT);
        let plain_json = plain.to_json();
        assert!(plain_json.get("textReveal").is_none());
        assert!(plain_json.get("revealSpeed").is_none());

        // Мусор и невозможные значения: неизвестный режим и нулевая скорость
        // не должны ронять анимацию в вечную.
        let junk = ContentItem::from_json(&serde_json::json!({
            "id": "r3",
            "type": "text",
            "textReveal": "Typewriter ",
            "revealSpeed": 0.0,
        }));
        assert_eq!(junk.text_reveal, "typewriter");
        assert_eq!(junk.reveal_speed, REVEAL_SPEED_MIN);
        let unknown = ContentItem::from_json(&serde_json::json!({
            "id": "r4",
            "type": "text",
            "textReveal": "slide",
        }));
        assert_eq!(unknown.text_reveal, TEXT_REVEAL_DEFAULT);
    }

    #[test]
    fn show_timer_roundtrip_and_default() {
        let on = ContentItem::from_json(&serde_json::json!({
            "id": "m1",
            "type": "modal",
            "showTimer": true,
        }));
        assert!(on.show_timer);
        assert_eq!(on.to_json()["showTimer"], json!(true));

        let off = ContentItem::from_json(&serde_json::json!({
            "id": "m2",
            "type": "modal",
        }));
        assert!(!off.show_timer);
        // false — это отсутствие ключа, round-trip не плодит поле в файле.
        assert!(off.to_json().get("showTimer").is_none());

        // Старые файлы модалки несли флаг в scriptTriggers. При чтении он
        // переезжает в поле и из карты выпадает.
        let legacy = ContentItem::from_json(&serde_json::json!({
            "id": "m3",
            "type": "modal",
            "scriptTriggers": {"showTimer": "true"},
        }));
        assert!(legacy.show_timer);
        assert!(legacy.script_triggers.is_none());
        assert_eq!(legacy.to_json()["showTimer"], json!(true));

        // Чужая запись в карте — не про таймер, она остаётся ссылкой.
        let mixed = ContentItem::from_json(&serde_json::json!({
            "id": "m4",
            "type": "modal",
            "scriptTriggers": {"showTimer": "true", "onPress": "scripts/a.json"},
        }));
        assert!(mixed.show_timer);
        assert_eq!(mixed.script_triggers.unwrap()["onPress"], "scripts/a.json");
    }

    #[test]
    fn locked_roundtrip_and_default() {
        let locked = ContentItem::from_json(&serde_json::json!({
            "id": "c1",
            "type": "text",
            "text": "hi",
            "locked": true,
        }));
        assert!(locked.locked);
        assert_eq!(locked.to_json()["locked"], json!(true));

        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "c2",
            "type": "text",
            "text": "hi"
        }));
        assert!(!plain.locked);
        // Как и isHidden: пишем поле всегда, чтобы Dart и Rust не расходились
        // в том, что считается «старым файлом».
        assert_eq!(plain.to_json()["locked"], json!(false));
    }

    #[test]
    fn group_name_roundtrip_and_default() {
        let grouped = ContentItem::from_json(&serde_json::json!({
            "id": "c1",
            "type": "text",
            "text": "hi",
            "groupName": "Группа 1",
        }));
        assert_eq!(grouped.group_name.as_deref(), Some("Группа 1"));
        assert_eq!(grouped.to_json()["groupName"], json!("Группа 1"));

        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "c2",
            "type": "text",
            "text": "hi"
        }));
        assert_eq!(plain.group_name, None);
        assert!(plain.to_json().get("groupName").is_none());
    }

    #[test]
    fn layer_name_roundtrip_and_default() {
        let named = ContentItem::from_json(&serde_json::json!({
            "id": "c1",
            "type": "text",
            "text": "hi",
            "layerName": "Шапка",
        }));
        assert_eq!(named.layer_name.as_deref(), Some("Шапка"));
        assert_eq!(named.to_json()["layerName"], json!("Шапка"));

        let plain = ContentItem::from_json(&serde_json::json!({
            "id": "c2",
            "type": "text",
            "text": "hi"
        }));
        assert_eq!(plain.layer_name, None);
        assert!(plain.to_json().get("layerName").is_none());
    }

    #[test]
    fn guides_roundtrip_and_empty_is_none() {
        let stack = ContentItem::from_json(&serde_json::json!({
            "id": "c1",
            "type": "stack",
            "guidesX": [120.5, 480],
            "guidesY": [300],
        }));
        assert_eq!(stack.guides_x.as_deref(), Some([120.5, 480.0].as_slice()));
        assert_eq!(stack.to_json()["guidesX"], json!([120.5, 480.0]));
        assert_eq!(stack.to_json()["guidesY"], json!([300.0]));

        for raw in [
            serde_json::json!({"id": "c2", "type": "stack"}),
            serde_json::json!({"id": "c3", "type": "stack", "guidesX": []}),
            serde_json::json!({"id": "c4", "type": "stack", "guidesX": "120"}),
        ] {
            let item = ContentItem::from_json(&raw);
            assert_eq!(item.guides_x, None, "{:?} — направляющих нет", raw);
            assert!(item.to_json().get("guidesX").is_none());
        }
    }

    #[test]
    fn guides_survive_json_roundtrip() {
        let stack = ContentItem::from_json(&serde_json::json!({
            "id": "c1",
            "type": "stack",
            "guidesX": [120.5, 480.0],
        }));
        let again = ContentItem::from_json(&stack.to_json());
        assert_eq!(again.guides_x.as_deref(), Some([120.5, 480.0].as_slice()));
    }
}
