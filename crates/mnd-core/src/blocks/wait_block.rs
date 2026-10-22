//! Блок `wait` / `задержка` — пауза в скрипте.
//!
//! Создаёт pacing-checkpoint: клиент увидит промежуточное состояние
//! (используется для анимаций смены кадров).

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{
    ExecutorError, evaluate_expression, is_pacing_plumbing_key, push_effect,
    take_pending_audio_commands, value_to_string,
};

pub struct Wait;

impl BlockHandler for Wait {
    fn block_type(&self) -> &'static str {
        "wait"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.controller.tick()?;

        let expr = ctx
            .block
            .get("expression")
            .or_else(|| ctx.block.get("milliseconds"))
            .map(value_to_string)
            .unwrap_or_else(|| "0".into());

        let val = evaluate_expression(Some(serde_json::Value::String(expr)), ctx.game_state);
        let ms = val
            .as_f64()
            .or_else(|| value_to_string(&val).parse::<f64>().ok())
            .unwrap_or(0.0)
            .round() as i64;

        if ms > 0 {
            ctx.controller.record_wait(ms);

            let snapshot_vars = ctx
                .game_state
                .take_pacing_snapshot_variables()
                .into_iter()
                .filter(|(name, _)| !is_pacing_plumbing_key(name))
                .map(|(name, value)| {
                    (
                        name,
                        serde_json::json!(
                            serde_json::to_string(&value).unwrap_or_else(|_| "null".into())
                        ),
                    )
                })
                .collect::<serde_json::Value>();

            let snapshot_tables = ctx
                .game_state
                .take_pacing_snapshot_tables()
                .into_iter()
                .map(|(name, value)| {
                    (
                        name,
                        serde_json::json!(
                            serde_json::to_string(&value).unwrap_or_else(|_| "null".into())
                        ),
                    )
                })
                .collect::<serde_json::Value>();

            let pending_audio = take_pending_audio_commands(ctx.game_state);

            push_effect(
                ctx.game_state,
                "_internal_delay_queue",
                serde_json::json!({
                    "type": "delay",
                    "ms": ms,
                    "variables": snapshot_vars,
                    "tables": snapshot_tables,
                    "audio": pending_audio,
                }),
            );
        }

        Ok(None)
    }
}
