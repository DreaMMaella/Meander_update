//! Блок `while` / `while_loop` — цикл с прогрессивной сложностью.
//!
//! Режимы выбираются по содержимому блока (приоритет сверху вниз):
//!
//! 1. **Условие** — непустое `expression`:
//!    {"type":"while","expression":"HP > 0","max_iterations":1000,"children":[…]}
//!    Легаси-поведение: пока выражение истинно. Старые квесты не меняются.
//!
//! 2. **Диапазон** — задан `to` (`до`): классический for
//!    {"type":"while","loop_var":"i","from":1,"to":10,"step":2,"children":[…]}
//!    Шаг по умолчанию 1; отрицательный шаг идёт вниз.
//!
//! 3. **Простой повтор** — задан `count` (`times`/`повторений`/`раз`):
//!    {"type":"while","count":100,"children":[…]}
//!    Максимум простоты: одно число.
//!
//! 4. Ничего не задано → пропуск с warning'ом в лог.
//!
//! Опционально `loop_var` (`переменная`/`счётчик`) — имя переменной, в которую
//! на каждой итерации пишется текущий номер повтора (для диапазона — значение
//! счётчика). Доступна детям как `{имя}`.
//!
//! `max_iterations` (опционально) — страховка от бесконечного цикла,
//! применяется во всех режимах (по умолчанию 10 000).

use serde_json::Value;

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::ExecutorError;
use crate::executor::evaluate_expression;
use crate::expression::to_bool;

pub struct WhileLoop;

impl WhileLoop {
    fn run_children(
        &self,
        ctx: &mut BlockContext<'_>,
        children: &[Value],
        iteration: f64,
    ) -> Result<Option<String>, ExecutorError> {
        if let Some(var) = &self.loop_var(ctx) {
            // Целые значения храним как целые (конвенция assign_variable).
            let value = if iteration.fract() == 0.0 {
                Value::from(iteration as i64)
            } else {
                Value::from(iteration)
            };
            ctx.game_state.set_variable(var, value);
        }
        for child in children {
            if let Some(child_map) = child.as_object()
                && let Some(res) = ctx.executor.execute_block_recursively(
                    child_map,
                    ctx.game_state,
                    ctx.controller,
                    ctx.quest_id,
                    ctx.lua,
                )?
            {
                return Ok(Some(res));
            }
        }
        Ok(None)
    }

    fn loop_var(&self, ctx: &BlockContext<'_>) -> Option<String> {
        let raw = ctx.string_field(&["loop_var", "counter_var", "переменная", "счётчик"], "");
        let trimmed = raw.trim().to_string();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    }

    /// Непустое поле хотя бы по одному из ключей.
    fn any_field_present(&self, ctx: &BlockContext<'_>, keys: &[&str]) -> bool {
        keys.iter().any(|k| {
            !ctx.string_field(std::slice::from_ref(k), "")
                .trim()
                .is_empty()
        })
    }
}

impl BlockHandler for WhileLoop {
    fn block_type(&self) -> &'static str {
        "while"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.controller.tick()?;

        let children = ctx
            .block
            .get("children")
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default();

        if children.is_empty() {
            ctx.executor.log("⚠️ while: нет children, пропуск");
            return Ok(None);
        }

        let max_iters = (ctx
            .num_field(&["max_iterations", "макс_итераций"], 10_000.0)
            .max(1.0)) as usize;

        // ── 1. Условие (легаси) ────────────────────────────────────────────
        let expression_raw = ctx.string_field(&["expression", "выражение"], "");
        if !expression_raw.trim().is_empty() {
            let mut count: usize = 0;
            loop {
                ctx.controller.tick()?;

                let cond_val = evaluate_expression(
                    Some(Value::String(expression_raw.clone())),
                    ctx.game_state,
                );
                if !to_bool(&cond_val) {
                    break;
                }

                count += 1;
                if count > max_iters {
                    ctx.executor.log(&format!(
                        "⚠️ while: превышен лимит итераций ({max_iters}), остановка"
                    ));
                    break;
                }

                let iteration = count as f64;
                if let Some(res) = self.run_children(ctx, &children, iteration)? {
                    return Ok(Some(res));
                }
            }
            ctx.executor
                .log(&format!("↻ while(условие): {count} итераций"));
            return Ok(None);
        }

        // ── 2. Диапазон: from..to с шагом ─────────────────────────────────
        if self.any_field_present(ctx, &["to", "до", "until"]) {
            let from = ctx.num_field(&["from", "от"], 1.0);
            let to = ctx.num_field(&["to", "до", "until"], 0.0);
            let mut step = ctx.num_field(&["step", "шаг"], 1.0);
            if step == 0.0 {
                step = 1.0;
            }

            let mut i = from;
            let mut count: usize = 0;
            while (step > 0.0 && i <= to) || (step < 0.0 && i >= to) {
                count += 1;
                if count > max_iters {
                    ctx.executor.log(&format!(
                        "⚠️ while: превышен лимит итераций ({max_iters}), остановка"
                    ));
                    break;
                }
                ctx.controller.tick()?;

                if let Some(res) = self.run_children(ctx, &children, i)? {
                    return Ok(Some(res));
                }
                i += step;
            }
            ctx.executor
                .log(&format!("↻ while(диапазон): {count} итераций"));
            return Ok(None);
        }

        // ── 3. Простой повтор N раз ───────────────────────────────────────
        let count_keys: &[&str] = &[
            "count",
            "times",
            "repeat",
            "повторений",
            "раз",
            "количество",
        ];
        if self.any_field_present(ctx, count_keys) {
            let total_f = ctx.num_field(count_keys, 0.0);
            let total = if total_f.is_finite() && total_f > 0.0 {
                (total_f.min(max_iters as f64)) as usize
            } else {
                0
            };
            if (total_f as usize) > max_iters {
                ctx.executor.log(&format!(
                    "⚠️ while: запрошено {} повторений, ограничено лимитом {max_iters}",
                    total_f as usize
                ));
            }

            for n in 1..=total {
                ctx.controller.tick()?;
                if let Some(res) = self.run_children(ctx, &children, n as f64)? {
                    return Ok(Some(res));
                }
            }
            ctx.executor
                .log(&format!("↻ while(повтор): {total} итераций"));
            return Ok(None);
        }

        // ── 4. Ничего не задано ───────────────────────────────────────────
        ctx.executor.log(
            "⚠️ while: не задан ни режим повторения (count/to), ни условие (expression) — пропуск",
        );
        Ok(None)
    }
}
