//! Блок `http_request` — HTTP-запрос.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, interpolate_placeholders_raw, value_to_string};

pub struct HttpRequest;

impl BlockHandler for HttpRequest {
    fn block_type(&self) -> &'static str {
        "http_request"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        let method = ctx.string_field(&["method"], "GET").trim().to_uppercase();
        let raw_url = ctx.string_field(&["url"], "");
        let url = interpolate_placeholders_raw(&raw_url, ctx.game_state)
            .trim()
            .to_string();

        let mut headers: Vec<(String, String)> = Vec::new();
        if let Some(serde_json::Value::Object(obj)) = ctx.block.get("headers") {
            for (key, value) in obj {
                let raw = value_to_string(value);
                headers.push((
                    key.clone(),
                    interpolate_placeholders_raw(&raw, ctx.game_state),
                ));
            }
        }

        let body: Option<String> = match ctx.block.get("body") {
            Some(serde_json::Value::String(s)) => {
                Some(interpolate_placeholders_raw(s, ctx.game_state))
            }
            Some(serde_json::Value::Object(_)) | Some(serde_json::Value::Array(_)) => ctx
                .block
                .get("body")
                .map(|v| serde_json::to_string(v).unwrap_or_default()),
            _ => None,
        };

        let target_var = ctx
            .block
            .get("targetVariable")
            .and_then(serde_json::Value::as_str)
            .map(String::from);
        let status_var = ctx
            .block
            .get("statusVariable")
            .and_then(serde_json::Value::as_str)
            .map(String::from)
            .unwrap_or_else(|| {
                target_var
                    .as_deref()
                    .map(|t| format!("{t}_status"))
                    .unwrap_or_default()
            });

        if url.is_empty() {
            ctx.executor.log("⚠️ http_request без url — пропуск");
            return Ok(None);
        }

        match crate::http::perform_http_request(&method, &url, &headers, body.as_deref()) {
            Ok(resp) => {
                if let Some(target) = &target_var {
                    ctx.game_state
                        .set_variable(target, serde_json::Value::String(resp.body));
                }
                if !status_var.is_empty() {
                    ctx.game_state
                        .set_variable(&status_var, serde_json::json!(resp.status));
                }
                ctx.executor
                    .log(&format!("🌐 HTTP {method} {url} → {}", resp.status));
            }
            Err(err) => {
                ctx.executor
                    .log(&format!("🌐 HTTP {method} {url} → ОШИБКА: {err}"));
                if let Some(target) = &target_var {
                    ctx.game_state
                        .set_variable(target, serde_json::Value::String(String::new()));
                }
                if !status_var.is_empty() {
                    ctx.game_state
                        .set_variable(&status_var, serde_json::json!(0));
                }
            }
        }
        Ok(None)
    }
}
