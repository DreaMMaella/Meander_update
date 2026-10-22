//! Блок `call_function` — вызов функции из внешнего скрипта.
//!
//! Поддерживает цикл-таймер: если функция уже на стеке вызовов,
//! планируется re-invoke через ms последнего `wait`.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{
    EventType, ExecutorError, check_script_event_type, has_executable_blocks_for_event,
    normalize_script_id, schedule_timer, value_to_string,
};

pub struct CallFunction;

impl BlockHandler for CallFunction {
    fn block_type(&self) -> &'static str {
        "call_function"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.controller.tick()?;

        let function_id = ctx
            .block
            .get("function_id")
            .and_then(serde_json::Value::as_str);
        let function_entry_raw = ctx
            .block
            .get("function_entry")
            .map(value_to_string)
            .unwrap_or_default()
            .trim()
            .to_string();
        let function_entry = if function_entry_raw.is_empty() {
            "main".to_string()
        } else {
            function_entry_raw
        };

        if let Some(function_id) = function_id {
            let normalized_id = normalize_script_id(function_id);
            let log = |msg: &str| ctx.executor.log(msg);

            log(&format!(
                "Calling function: {normalized_id}::{function_entry}"
            ));

            let script_path = ctx.executor.resolve_script_path(ctx.quest_id, function_id);
            if let Some(script_path) = script_path {
                if ctx.controller.contains_call(&script_path, &function_entry) {
                    let ms = ctx.controller.take_wait_ms();
                    if ms > 0 {
                        schedule_timer(ctx.game_state, &script_path, &function_entry, ms);
                        log(&format!(
                            "↻ Timer cycle: {normalized_id}::{function_entry} → scheduled in {ms} ms"
                        ));
                    } else {
                        log(&format!(
                            "❌ Recursive call without wait: {normalized_id}::{function_entry} — aborted"
                        ));
                    }
                    return Ok(None);
                }

                if let Some(nested) = ctx.executor.load_nested_script(&script_path) {
                    let has_function_blocks = has_executable_blocks_for_event(
                        &nested,
                        EventType::Function,
                        &Some(function_entry.clone()),
                        &None,
                        false,
                    );
                    let declared_event = check_script_event_type(&nested);

                    let mut candidates = vec![EventType::Function];
                    if !has_function_blocks {
                        candidates.push(declared_event);
                    }

                    let mut attempted: Vec<String> = vec![];
                    for candidate in candidates {
                        if attempted.contains(&candidate.name().to_string()) {
                            continue;
                        }
                        attempted.push(candidate.name().to_string());
                        let fn_name = if candidate == EventType::Function {
                            Some(function_entry.clone())
                        } else {
                            None
                        };
                        if !has_executable_blocks_for_event(
                            &nested, candidate, &fn_name, &None, false,
                        ) {
                            continue;
                        }

                        ctx.controller.enter_call(&script_path, &function_entry)?;
                        let res = ctx.executor.execute_with_controller(
                            &nested,
                            ctx.game_state,
                            ctx.controller,
                            ctx.quest_id,
                            candidate,
                            &fn_name,
                            &None,
                            false,
                            ctx.lua,
                        );
                        ctx.controller.exit_call();
                        let res = res?;
                        if let Some(node) = res {
                            log(&format!(
                                "Function returned transition: {node} [event={}]",
                                candidate.name()
                            ));
                            return Ok(Some(node));
                        }
                    }
                }
            } else {
                log(&format!("Function script not found: {function_id}"));
            }
        }
        Ok(None)
    }
}
