//! Блок `set_volume` — громкость контента/тега.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, evaluate_expression, value_to_string};

pub struct SetVolume;

impl BlockHandler for SetVolume {
    fn block_type(&self) -> &'static str {
        "set_volume"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.controller.tick()?;
        let target = ctx.string_field(&["target"], "contentAudio");
        let raw_volume = ctx
            .block
            .get("volume")
            .cloned()
            .unwrap_or(serde_json::json!(1.0));
        let evaluated_volume = evaluate_expression(Some(raw_volume), ctx.game_state);
        let volume_value = evaluated_volume
            .as_f64()
            .or_else(|| value_to_string(&evaluated_volume).parse::<f64>().ok());
        if let Some(volume) = volume_value {
            let clamped = volume.clamp(0.0, 1.0);
            match target.as_str() {
                "contentAudio" => ctx
                    .game_state
                    .set_variable("_internal_node_content_volume", serde_json::json!(clamped)),
                "tagAudio" => ctx
                    .game_state
                    .set_variable("_internal_tag_volume", serde_json::json!(clamped)),
                _ => {}
            }
        }
        Ok(None)
    }
}
