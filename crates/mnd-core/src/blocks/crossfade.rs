//! Блок `crossfade` — плавный переход аудио.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, evaluate_expression, push_audio_command, value_to_string};

pub struct Crossfade;

impl BlockHandler for Crossfade {
    fn block_type(&self) -> &'static str {
        "crossfade"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        let raw_duration = ctx.string_field(&["duration"], "2");
        let evaluated_duration = evaluate_expression(
            Some(serde_json::Value::String(raw_duration)),
            ctx.game_state,
        );
        let duration_value = evaluated_duration
            .as_f64()
            .or_else(|| value_to_string(&evaluated_duration).parse::<f64>().ok());
        let duration_ms = ((duration_value.unwrap_or(2.0)) * 1000.0).round() as i64;

        push_audio_command(
            ctx.game_state,
            serde_json::json!({"type": "fade_out", "ms": duration_ms}),
        );

        let children = ctx
            .block
            .get("children")
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default();
        if let Some(res) = ctx.execute_children(children)? {
            return Ok(Some(res));
        }

        push_audio_command(
            ctx.game_state,
            serde_json::json!({"type": "fade_in", "ms": duration_ms}),
        );
        Ok(None)
    }
}
