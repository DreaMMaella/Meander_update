//! Блок `go_to_node` — переход на другой узел.
//!
//! Поддерживает `=expression`, `{variable}` и прямые id.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, evaluate_expression, value_to_string};

pub struct GoToNode;

impl BlockHandler for GoToNode {
    fn block_type(&self) -> &'static str {
        "go_to_node"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.controller.tick()?;

        let raw_node_id = ctx.block.get("node_id");
        if let Some(raw) = raw_node_id {
            let mut expr = value_to_string(raw);
            let expr_trimmed = expr.trim().to_string();

            let is_formula = expr_trimmed.starts_with('=')
                || (expr_trimmed.contains('{') && expr_trimmed.contains('}'));

            if is_formula {
                if expr_trimmed.starts_with('=') {
                    expr = expr_trimmed["=".len()..].trim().to_string();
                }
                if !expr.trim().is_empty() {
                    let evaluated = evaluate_expression(
                        Some(serde_json::Value::String(expr.clone())),
                        ctx.game_state,
                    );
                    let resolved = value_to_string(&evaluated);
                    let resolved = resolved.trim().to_string();
                    if !resolved.is_empty() && resolved != "null" {
                        return Ok(Some(resolved));
                    }
                }
            }

            let clean_raw = expr_trimmed
                .trim_matches('"')
                .trim_matches('\'')
                .to_string();
            Ok(Some(clean_raw))
        } else {
            Ok(None)
        }
    }
}
