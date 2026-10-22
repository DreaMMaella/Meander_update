//! Audio blocks: play_sound, stop_sound, play_music, stop_music, pause_resume.

use serde_json::Value;

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::{ExecutorError, push_audio_command, value_to_string};

macro_rules! audio_block {
    ($name:ident, $block_type:literal) => {
        pub struct $name;
        impl BlockHandler for $name {
            fn block_type(&self) -> &'static str {
                $block_type
            }
            fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
                ctx.controller.tick()?;
                execute(ctx)
            }
        }
    };
}

audio_block!(PlaySound, "play_sound");
audio_block!(StopSound, "stop_sound");
audio_block!(PlayMusic, "play_music");
audio_block!(StopMusic, "stop_music");
audio_block!(PauseResume, "pause_resume");

fn execute(ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
    let block_type = ctx
        .block
        .get("type")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("");
    match block_type {
        "play_sound" => {
            // Новые JSON-скрипты используют snake_case, но экспортёр/старые
            // скрипты могли сохранить camelCase. Принимаем оба варианта,
            // иначе блок штатно исполняется, но не создаёт аудиокоманду.
            let audio_id = ctx
                .block
                .get("audio_id")
                .or_else(|| ctx.block.get("audioId"));
            let clamped = ctx.eval_volume(1.0);
            if let Some(audio_id) = audio_id {
                push_audio_command(
                    ctx.game_state,
                    serde_json::json!({
                        "type": "play_sound",
                        "audio_id": value_to_string(audio_id),
                        "volume": clamped,
                    }),
                );
            }
        }
        "stop_sound" => {
            let target = ctx.string_field(&["target"], "all");
            let audio_id = ctx.block.get("audio_id");
            let stop_target = if target == "all" {
                "all".to_string()
            } else if let Some(audio_id) = audio_id {
                value_to_string(audio_id)
            } else {
                return Ok(None);
            };
            push_audio_command(
                ctx.game_state,
                serde_json::json!({"type": "stop_sound", "target": stop_target}),
            );
        }
        "play_music" => {
            let audio_id = ctx
                .block
                .get("audio_id")
                .or_else(|| ctx.block.get("audioId"));
            let loop_ = ctx
                .block
                .get("loop")
                .cloned()
                .unwrap_or(serde_json::json!(true));
            let global = ctx
                .block
                .get("global")
                .cloned()
                .unwrap_or(serde_json::json!(false));
            let clamped = ctx.eval_volume(1.0);
            if let Some(audio_id) = audio_id {
                let id_str = value_to_string(audio_id);
                push_audio_command(
                    ctx.game_state,
                    serde_json::json!({
                        "type": "play_music",
                        "audio_id": id_str,
                        "loop": loop_,
                        "volume": clamped,
                        "global": global,
                    }),
                );
                // Персистентный слот активной скриптовой музыки: попадает в
                // сейв, чтобы после загрузки сохранения клиент мог возобновить
                // трек (NodeView.background_audio несёт только музыку ноды/главы).
                ctx.game_state
                    .set_variable("_internal_active_script_bgm_id", serde_json::json!(id_str));
                ctx.game_state.set_variable(
                    "_internal_active_script_bgm_volume",
                    serde_json::json!(clamped),
                );
                ctx.game_state
                    .set_variable("_internal_active_script_bgm_loop", loop_);
            }
        }
        "stop_music" => {
            push_audio_command(ctx.game_state, serde_json::json!({"type": "stop_music"}));
            // Активная скриптовая музыка остановлена — из сейва её возобновлять не нужно.
            ctx.game_state
                .set_variable("_internal_active_script_bgm_id", Value::Null);
            ctx.game_state
                .set_variable("_internal_active_script_bgm_volume", Value::Null);
            ctx.game_state
                .set_variable("_internal_active_script_bgm_loop", Value::Null);
        }
        "pause_resume" => {
            let target = ctx.string_field(&["target"], "all");
            let action = ctx.string_field(&["action"], "toggle");
            push_audio_command(
                ctx.game_state,
                serde_json::json!({"type": "pause_resume", "target": target, "action": action}),
            );
        }
        _ => {}
    }
    Ok(None)
}
