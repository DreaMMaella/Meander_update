//! Блок `set_blur` — размытие фона.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, evaluate_expression, value_to_string};

pub struct SetBlur;

impl BlockHandler for SetBlur {
    fn block_type(&self) -> &'static str {
        "set_blur"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.controller.tick()?;
        let target = ctx.string_field(&["target"], "node");
        let raw_blur = ctx
            .block
            .get("blur")
            .cloned()
            .unwrap_or(serde_json::json!(10.0));
        let evaluated_blur = evaluate_expression(Some(raw_blur.clone()), ctx.game_state);
        let blur_value = evaluated_blur
            .as_f64()
            .or_else(|| value_to_string(&evaluated_blur).parse::<f64>().ok());
        if let Some(blur) = blur_value
            && (target == "node" || target == "quest" || target == "tag")
        {
            ctx.game_state
                .set_variable("_internal_background_blur", serde_json::json!(blur));
        }
        Ok(None)
    }
}
