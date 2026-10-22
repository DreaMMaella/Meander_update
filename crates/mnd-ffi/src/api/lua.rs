//! FFI-слой для контекстного автодополнения Lua (L3A, этап 3).
//!
//! Вызывает комплетор в ядре ([`mnd_core::lua::completion::lua_complete`]) и
//! возвращает JSON-массив подсказок. Сам по себе не хранит состояние —
//! редактор шлёт текущий буфер и позицию курсора каждый раз.

/// Контекстное автодополнение Lua для позиции курсора.
///
/// `source` — текущий текст буфера, `cursor_byte` — байтовая позиция курсора
/// (внутри исходника). Возвращает JSON-массив
/// `[{label, kind, insertText, detail}]`, отфильтрованный по набираемому
/// префиксу.
pub fn lua_complete(source: String, cursor_byte: usize) -> String {
    let value = mnd_core::lua::completion::lua_complete(&source, cursor_byte);
    serde_json::to_string(&value).unwrap_or_else(|_| "[]".to_string())
}
