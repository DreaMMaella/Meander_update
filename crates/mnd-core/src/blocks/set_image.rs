//! Блок `set_image` — сменить картинку у айтема (или слоя внутри стека).
//!
//! Движок не лезет в модель контента — у исполнителя к ней нет доступа. Вместо
//! этого он держит переопределения источника в служебной переменной
//! `_internal_item_sources` (`{itemId: source}`), а клиент читает её при
//! каждом разрешении пути картинки. Побочный эффект — значение живёт в
//! состоянии игры: попадает в сейв и восстанавливается из него.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{
    ExecutorError, ITEM_SOURCE_VAR, interpolate_placeholders_raw, value_to_string,
};
use serde_json::{Map, Value};

pub struct SetImage;

impl BlockHandler for SetImage {
    fn block_type(&self) -> &'static str {
        "set_image"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        let item_id = ctx
            .string_field(&["item_id", "айтем"], "")
            .trim()
            .to_string();
        let raw_source = ctx
            .block
            .get("source")
            .or_else(|| ctx.block.get("источник"));
        let source = match raw_source {
            None | Some(Value::Null) => String::new(),
            Some(value) => interpolate_placeholders_raw(&value_to_string(value), ctx.game_state)
                .trim()
                .to_string(),
        };

        if item_id.is_empty() || source.is_empty() {
            ctx.executor
                .log("⚠️ set_image без айтема или источника — пропуск");
            return Ok(None);
        }

        let mut overrides = match ctx.game_state.get_variable(ITEM_SOURCE_VAR).cloned() {
            Some(Value::Object(map)) => map,
            _ => Map::new(),
        };
        overrides.insert(item_id.clone(), Value::String(source.clone()));
        ctx.game_state
            .set_variable(ITEM_SOURCE_VAR, Value::Object(overrides));
        ctx.executor
            .log(&format!("🖼 set_image: {item_id} → {source}"));
        Ok(None)
    }
}
