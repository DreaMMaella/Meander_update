//! Блок `for_each` / `при_каждом` — цикл по строкам таблицы.
//!
//! ```json
//! {
//!     "type": "for_each",
//!     "table": "enemies",
//!     "var_prefix": "row",
//!     "index_variable": "i",
//!     "children": [...]
//! }
//! ```
//!
//! `var_prefix` и `index_variable` необязательны: дефолты `row` и `i` — ровно
//! те, что подсказывает редактор. Пустое поле (= автор ничего не ввёл)
//! считается отсутствием поля, иначе переменные получили бы имена вида `_name`
//! и в тексте были бы недостижимы.
//!
//! Для таблицы `enemies` с колонками `name`, `hp`:
//!   Строка 0: `row_name = "Goblin"`, `row_hp = 10`, `i = 0`
//!   Строка 1: `row_name = "Orc"`,   `row_hp = 25`, `i = 1`

use crate::blocks::{BlockContext, BlockHandler};
use crate::executor::ExecutorError;

pub struct ForEach;

impl ForEach {
    /// Непустое поле: пропущенное и заполненное пробелами значения уходят в
    /// дефолт, а не в имя переменной.
    fn field(&self, ctx: &BlockContext<'_>, keys: &[&str], default: &str) -> String {
        let raw = ctx.string_field(keys, "").trim().to_string();
        if raw.is_empty() {
            default.to_string()
        } else {
            raw
        }
    }
}

impl BlockHandler for ForEach {
    fn block_type(&self) -> &'static str {
        "for_each"
    }

    fn execute(&self, ctx: &mut BlockContext<'_>) -> Result<Option<String>, ExecutorError> {
        ctx.controller.tick()?;

        let table_name = self.field(ctx, &["table", "таблица"], "");
        if table_name.is_empty() {
            ctx.executor.log("⚠️ for_each без table — пропуск");
            return Ok(None);
        }

        // Прямой поиск таблицы по имени (не evaluate — expression превращает
        // таблицу в строку всех строк через resolve_inline_token_value).
        let table_name = table_name.trim().to_string();

        // Клонируем таблицу, чтобы не держать borrow на game_state.
        let table = ctx.game_state.get_table(&table_name).cloned();
        let Some(table) = table else {
            ctx.executor
                .log(&format!("⚠️ for_each: таблица '{table_name}' не найдена"));
            return Ok(None);
        };

        let prefix = self.field(ctx, &["var_prefix", "префикс"], "row");
        let index_var = self.field(ctx, &["index_variable", "индекс"], "i");
        let children = ctx
            .block
            .get("children")
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default();

        if children.is_empty() {
            ctx.executor.log(&format!(
                "⚠️ for_each '{table_name}': нет children, пропуск"
            ));
            return Ok(None);
        }

        let columns = table.columns.clone();
        let rows = table.rows.clone();
        let rows_count = rows.len();

        for (i, row) in rows.iter().enumerate() {
            ctx.controller.tick()?;

            ctx.game_state
                .set_variable(&index_var, serde_json::json!(i));
            for col in &columns {
                let var_name = format!("{prefix}_{col}");
                let value = row
                    .get(col.as_str())
                    .cloned()
                    .unwrap_or(serde_json::Value::Null);
                ctx.game_state.set_variable(&var_name, value);
            }

            for child in &children {
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
        }

        // Текст ноды ищет `{row_name}` по имени переменной, а имена собираются
        // из столбцов: без них «цикл отработал, переменных нет» выглядит
        // магией. Лог говорит, какие имена получились.
        let names = if columns.is_empty() {
            String::from("столбцов нет")
        } else {
            columns
                .iter()
                .map(|c| format!("{prefix}_{c}"))
                .collect::<Vec<_>>()
                .join(", ")
        };
        ctx.executor.log(&format!(
            "↻ for_each '{table_name}': {rows_count} строк → {index_var}, {names}"
        ));
        Ok(None)
    }
}
