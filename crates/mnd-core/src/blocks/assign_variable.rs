//! Блок `assign_variable` / `создать_переменную` / `изменить_переменную`.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, evaluate_expression};
use crate::expression::{json_of_f64, to_num};

pub struct AssignVariable;

impl BlockHandler for AssignVariable {
    fn block_type(&self) -> &'static str {
        "assign_variable"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        let var_name = ctx
            .block
            .get("variable")
            .or_else(|| ctx.block.get("переменная"))
            .and_then(serde_json::Value::as_str)
            .map(String::from);
        let val = evaluate_expression(
            ctx.block
                .get("value")
                .or_else(|| ctx.block.get("значение"))
                .cloned(),
            ctx.game_state,
        );
        let operation = ctx
            .block
            .get("операция")
            .and_then(serde_json::Value::as_str);

        if let Some(var_name) = &var_name {
            let new_value = if let Some(op) = operation {
                let current = ctx
                    .game_state
                    .get_variable(var_name)
                    .cloned()
                    .unwrap_or(serde_json::Value::Null);
                let cur_num = to_num(&current).unwrap_or(0.0);
                let val_num = to_num(&val).unwrap_or(0.0);
                match op {
                    "прибавить" => json_of_f64(cur_num + val_num),
                    "отнять" => json_of_f64(cur_num - val_num),
                    _ => val.clone(),
                }
            } else {
                val.clone()
            };
            ctx.game_state.set_variable(var_name, new_value);
        }
        Ok(None)
    }
}
