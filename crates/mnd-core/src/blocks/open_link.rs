//! Блок `open_link` — открыть внешнюю ссылку.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, interpolate_placeholders_raw, push_effect};

pub struct OpenLink;

impl BlockHandler for OpenLink {
    fn block_type(&self) -> &'static str {
        "open_link"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        let raw_url = ctx.string_field(&["url"], "");
        let url = interpolate_placeholders_raw(&raw_url, ctx.game_state)
            .trim()
            .to_string();
        if url.is_empty() {
            ctx.executor.log("⚠️ open_link без url — пропуск");
            return Ok(None);
        }
        if let Err(reason) = crate::network_safety::check_url(&url) {
            ctx.executor
                .log(&format!("🛡️ open_link заблокирован: {reason}"));
            return Ok(None);
        }
        push_effect(
            ctx.game_state,
            "_internal_external_commands",
            serde_json::json!({"type": "open_link", "url": url}),
        );
        Ok(None)
    }
}
