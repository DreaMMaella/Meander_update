//! Блок `table_operation` — операции с таблицами.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::ExecutorError;

pub struct TableOperation;

impl BlockHandler for TableOperation {
    fn block_type(&self) -> &'static str {
        "table_operation"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.executor
            .execute_table_operation(ctx.block, ctx.game_state)
    }
}
