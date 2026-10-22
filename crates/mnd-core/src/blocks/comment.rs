//! Блок `comment` / `комментарий` — заметка автора. Не исполняется.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::ExecutorError;

pub struct Comment;

impl BlockHandler for Comment {
    fn block_type(&self) -> &'static str {
        "comment"
    }

    fn execute(&self, _ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        Ok(None)
    }
}
