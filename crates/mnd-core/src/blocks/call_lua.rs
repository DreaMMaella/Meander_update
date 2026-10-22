//! Блок `call_lua` — вызов Lua-функции.

use std::sync::{Arc, Mutex};

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::ExecutorError;
use crate::lua::LuaSession;

pub struct CallLua;

impl BlockHandler for CallLua {
    fn block_type(&self) -> &'static str {
        "call_lua"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        let function_name = ctx
            .block
            .get("function")
            .and_then(serde_json::Value::as_str)
            .map(str::trim)
            .unwrap_or_default();
        if function_name.is_empty() {
            return Err(ExecutorError::Lua(
                "блок call_lua без поля 'function'".into(),
            ));
        }

        let script_id = ctx
            .block
            .get("script_id")
            .and_then(serde_json::Value::as_str);
        let has_script_id = script_id.is_some_and(|s| !s.trim().is_empty());
        let script = if has_script_id {
            ctx.executor
                .load_lua_text(ctx.quest_id, script_id.unwrap_or_default())
        } else {
            ctx.block
                .get("script")
                .and_then(serde_json::Value::as_str)
                .map(String::from)
        };
        if has_script_id && script.is_none() {
            return Err(ExecutorError::Lua(format!(
                "файл .lua не найден: '{}'",
                script_id.unwrap_or_default()
            )));
        }

        let args = match ctx
            .block
            .get("args")
            .cloned()
            .unwrap_or(serde_json::Value::Null)
        {
            serde_json::Value::String(s) => {
                serde_json::from_str(&s).unwrap_or(serde_json::Value::String(s))
            }
            other => other,
        };

        if ctx.lua.is_none() {
            *ctx.lua = Some(Arc::new(Mutex::new(LuaSession::new())));
        }
        let mut session = ctx
            .lua
            .as_ref()
            .expect("lua создана")
            .lock()
            .expect("lua lock");
        session
            .call_function(ctx.game_state, script.as_deref(), function_name, args)
            .map_err(ExecutorError::Lua)
    }
}
