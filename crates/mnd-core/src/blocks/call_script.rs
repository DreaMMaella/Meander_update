//! Блок `call_script` — вызов вложенного скрипта.

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{
    EventType, ExecutorError, check_script_event_type, has_executable_blocks_for_event,
    normalize_script_id, schedule_timer,
};

pub struct CallScript;

impl BlockHandler for CallScript {
    fn block_type(&self) -> &'static str {
        "call_script"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        let script_id = ctx
            .block
            .get("script_id")
            .and_then(serde_json::Value::as_str);
        if let Some(script_id) = script_id {
            let normalized_id = normalize_script_id(script_id);
            let log = |msg: &str| ctx.executor.log(msg);
            log(&format!("Calling nested script: {normalized_id}"));

            if let Some(script_path) = ctx.executor.resolve_script_path(ctx.quest_id, script_id) {
                if ctx.controller.contains_call(&script_path, "*") {
                    let ms = ctx.controller.take_wait_ms();
                    if ms > 0 {
                        schedule_timer(ctx.game_state, &script_path, "*", ms);
                        log(&format!(
                            "↻ Timer cycle (script): {normalized_id} → scheduled in {ms} ms"
                        ));
                    } else {
                        log(&format!(
                            "❌ Recursive script call without wait: {normalized_id} — aborted"
                        ));
                    }
                    return Ok(None);
                }
                if let Some(nested) = ctx.executor.load_nested_script(&script_path) {
                    let declared_event = check_script_event_type(&nested);
                    let has_declared_blocks = has_executable_blocks_for_event(
                        &nested,
                        declared_event,
                        &None,
                        &None,
                        false,
                    );

                    let mut candidates = vec![declared_event];
                    if !has_declared_blocks {
                        candidates.extend([
                            EventType::Function,
                            EventType::OnNodeEnter,
                            EventType::OnContentAppear,
                            EventType::OnPress,
                        ]);
                    }

                    let mut attempted: Vec<String> = vec![];
                    for candidate in candidates {
                        if attempted.contains(&candidate.name().to_string()) {
                            continue;
                        }
                        attempted.push(candidate.name().to_string());
                        if !has_executable_blocks_for_event(&nested, candidate, &None, &None, false)
                        {
                            continue;
                        }

                        ctx.controller.enter_call(&script_path, candidate.name())?;
                        let res = ctx.executor.execute_with_controller(
                            &nested,
                            ctx.game_state,
                            ctx.controller,
                            ctx.quest_id,
                            candidate,
                            &None,
                            &None,
                            false,
                            ctx.lua,
                        );
                        ctx.controller.exit_call();
                        let res = res?;
                        if let Some(node) = res {
                            log(&format!(
                                "Nested script returned transition: {node} [event={}]",
                                candidate.name()
                            ));
                            return Ok(Some(node));
                        }
                    }
                }
            } else {
                log(&format!("Script not found: {script_id}"));
            }
        }
        Ok(None)
    }
}
