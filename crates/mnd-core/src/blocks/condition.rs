//! Блок `condition` / `условие` — if/then/else.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, evaluate_condition_logic};

pub struct Condition;

impl BlockHandler for Condition {
    fn block_type(&self) -> &'static str {
        "condition"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.controller.tick()?;

        let condition_result = evaluate_condition_logic(ctx.block, ctx.game_state);
        let key = if condition_result {
            if ctx.block.contains_key("then_blocks") {
                "then_blocks"
            } else {
                "если_да"
            }
        } else if ctx.block.contains_key("else_blocks") {
            "else_blocks"
        } else {
            "если_нет"
        };

        let children = ctx
            .block
            .get(key)
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default();

        ctx.execute_children(children)
    }
}
