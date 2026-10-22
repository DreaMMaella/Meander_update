//! Утилиты парсинга JSON в стиле Dart-хелперов ядра.
//!
//! Паритет с хелперами `_parseDouble`, `_parseBool`, `_parseString` из
//! `saved_node.dart` и `_stringOrNull` из `quest_descriptor.dart`.

use serde_json::Value;

/// `_parseDouble`: num → f64, строка → tryParse, иначе дефолт.
pub fn parse_double(v: Option<&Value>, default: f64) -> f64 {
    let Some(v) = v else { return default };
    match v {
        Value::Number(n) => n.as_f64().unwrap_or(default),
        Value::String(s) => s.trim().parse::<f64>().unwrap_or(default),
        _ => default,
    }
}

/// `_parseBool`: bool → itself; num → != 0; строка → 'true'/'1'/'yes' и т.д.
pub fn parse_bool(v: Option<&Value>, default: bool) -> bool {
    let Some(v) = v else { return default };
    match v {
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().map(|f| f != 0.0).unwrap_or(default),
        Value::String(s) => {
            let normalized = s.trim().to_lowercase();
            match normalized.as_str() {
                "true" | "1" | "yes" => true,
                "false" | "0" | "no" => false,
                _ => default,
            }
        }
        _ => default,
    }
}

/// `_parseString`: null → дефолт, иначе toString.
pub fn parse_string(v: Option<&Value>, default: &str) -> String {
    match v {
        None => default.to_string(),
        Some(Value::String(s)) => s.clone(),
        Some(other) => other.to_string(),
    }
}

/// `_stringOrNull`: toString().trim(); пусто → None.
pub fn string_or_null(v: Option<&Value>) -> Option<String> {
    let s = match v {
        None => return None,
        Some(Value::String(s)) => s.trim().to_string(),
        Some(other) => other.to_string().trim().to_string(),
    };
    if s.is_empty() { None } else { Some(s) }
}

/// `_stringOrFallback`: string_or_null ?? fallback.
pub fn string_or_fallback(v: Option<&Value>, fallback: &str) -> String {
    string_or_null(v).unwrap_or_else(|| fallback.to_string())
}

/// `_parseDate`: DateTime.tryParse-подобная валидация ISO-строки.
/// Храним оригинальную строку; невалидная → None.
pub fn parse_date(v: Option<&Value>) -> Option<String> {
    let s = v?.as_str()?;
    let trimmed = s.trim();
    if trimmed.is_empty() {
        return None;
    }
    // Минимальная ISO-подобная проверка: наличие цифр и T/:-.
    let has_digits = trimmed.chars().any(|c| c.is_ascii_digit());
    let has_iso_markers = trimmed.contains(['T', '-', ':', 'Z', '.']);
    if has_digits && has_iso_markers {
        Some(trimmed.to_string())
    } else {
        None
    }
}

/// Число из Value (int|double|string->num) в стиле Dart `num.tryParse`.
pub fn to_num(v: Option<&Value>) -> Option<f64> {
    match v {
        Some(Value::Number(n)) => n.as_f64(),
        Some(Value::String(s)) => s.trim().parse::<f64>().ok(),
        _ => None,
    }
}

/// Целый из Value (num -> int, bool -> 1/0).
pub fn to_int(v: Option<&Value>) -> Option<i64> {
    match v {
        Some(Value::Number(n)) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        Some(Value::Bool(b)) => Some(if *b { 1 } else { 0 }),
        Some(Value::String(s)) => s.trim().parse::<i64>().ok(),
        _ => None,
    }
}
