//! Декларативный UI-спек плагина.
//!
//! Плагин **не** строит Flutter-виджеты и не может подмешать исполняемый код:
//! он присылает JSON-дерево из фиксированного набора типов, который клиент
//! рисует своим (проревьюенным) рендерером. Отсюда — валидация на входе в ядро:
//! неизвестный тип, слишком глубокое/широкое дерево или «строка, похожая на
//! код» отклоняются до того, как дойдут до UI.
//!
//! Свойства — только скаляры (строки/числа/булевы) плюс `children` у
//! контейнеров и `row`-шаблон у `list`/`grid`: вложенные объекты-стили
//! запрещены, чтобы спеку нечего было «протащить» в рендерер.
//!
//! Строковые свойства проходят через тот же подстановщик `{переменных}`, что и
//! текст квеста (`resolveTextVariables` в клиенте), поэтому плагин может
//! привязать надпись к состоянию игры без какого-либо кода на стороне Dart.

use serde_json::Value;

use crate::policy::Limits;

/// Типы виджетов, которые умеет рисовать клиент.
pub const WIDGET_TYPES: &[&str] = &[
    "column", "row", "stack", "box", "card", "list", "grid", "scroll", "text", "heading",
    "caption", "badge", "icon", "image", "input", "button", "chip", "switch", "slider", "progress",
    "divider", "spacer",
];

/// Контейнеры: единственный тип, которому разрешено иметь `children`.
pub const CONTAINERS: &[&str] = &[
    "column", "row", "stack", "box", "card", "list", "grid", "scroll",
];

/// Свойства-колбэки: значение — имя функции плагина, а не код.
pub const HANDLER_PROPS: &[&str] = &["onPress", "onTap", "onChange", "onSubmit"];

/// Контейнеры с шаблоном строки: свойство `row` — один вложенный виджет.
pub const TEMPLATED: &[&str] = &["list", "grid"];

fn is_templated(t: &str) -> bool {
    TEMPLATED.contains(&t)
}

/// Максимум свойств на узел и детей у контейнера: защита от «раздутого» spec.
const MAX_PROPS_PER_NODE: usize = 20;
const MAX_CHILDREN_PER_NODE: usize = 64;

fn is_widget_type(t: &str) -> bool {
    WIDGET_TYPES.contains(&t)
}

fn is_container(t: &str) -> bool {
    CONTAINERS.contains(&t)
}

/// Имя Lua-функции: только латиница/цифры/подчёркивание, не «код».
fn is_identifier(raw: &str) -> bool {
    let mut chars = raw.chars();
    match chars.next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.')
}

/// Проверить spec целиком. Ошибки собираются все сразу — так манифест
/// правится за один проход, а не итерацией «одна ошибка — один запуск».
pub fn validate(value: &Value, limits: &Limits) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    let mut nodes = 0usize;
    walk(value, 0, limits, &mut errors, &mut nodes);
    if nodes == 0 {
        errors.push("пустой UI-спек".to_string());
    }
    if nodes > limits.max_spec_nodes {
        errors.push(format!(
            "слишком большое дерево виджетов: {nodes} > {}",
            limits.max_spec_nodes
        ));
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn walk(value: &Value, depth: usize, limits: &Limits, errors: &mut Vec<String>, nodes: &mut usize) {
    let at = format!("узел #{nodes}");
    *nodes += 1;
    if depth > limits.max_spec_depth {
        errors.push(format!("{at}: глубина больше {}", limits.max_spec_depth));
        return;
    }
    let Some(map) = value.as_object() else {
        errors.push(format!("{at}: ожидается объект виджета"));
        return;
    };
    let kind = match map.get("type").and_then(Value::as_str) {
        Some(t) if is_widget_type(t) => t.to_string(),
        Some(t) => {
            errors.push(format!("{at}: неизвестный тип виджета '{t}'"));
            return;
        }
        None => {
            errors.push(format!("{at}: нет поля 'type'"));
            return;
        }
    };
    if map.len() > MAX_PROPS_PER_NODE + 2 {
        errors.push(format!("{at}: слишком много свойств"));
    }
    for (key, prop) in map {
        match key.as_str() {
            "type" => {}
            "children" => {
                if !is_container(&kind) {
                    errors.push(format!("{at}: '{kind}' не может иметь children"));
                    continue;
                }
                let Some(items) = prop.as_array() else {
                    errors.push(format!("{at}: children должен быть массивом"));
                    continue;
                };
                if items.len() > MAX_CHILDREN_PER_NODE {
                    errors.push(format!("{at}: слишком много детей"));
                    continue;
                }
                for child in items {
                    walk(child, depth + 1, limits, errors, nodes);
                }
            }
            "row" => {
                if !is_templated(&kind) {
                    errors.push(format!("{at}: '{kind}' не может иметь row-шаблон"));
                    continue;
                }
                walk(prop, depth + 1, limits, errors, nodes);
            }
            other => check_prop(other, prop, limits, errors, &at),
        }
    }
}

fn check_prop(name: &str, value: &Value, limits: &Limits, errors: &mut Vec<String>, at: &str) {
    if HANDLER_PROPS.contains(&name) {
        let raw = value.as_str().unwrap_or_default();
        if !is_identifier(raw) {
            errors.push(format!("{at}: {name} должен быть именем функции"));
        }
        return;
    }
    match value {
        Value::String(s) => {
            if s.len() > limits.max_text_len {
                errors.push(format!("{at}: строка '{name}' длиннее лимита"));
            }
            // Разрешены только одинарные `{placeholder}`-ы: двойная скобка —
            // признак попытки протащить код/JSON вместо привязки к переменной.
            if s.contains("{{") {
                errors.push(format!("{at}: '{name}' содержит недопустимую конструкцию"));
            }
        }
        Value::Null | Value::Bool(_) | Value::Number(_) => {}
        Value::Array(items) => {
            if items.len() > MAX_CHILDREN_PER_NODE {
                errors.push(format!("{at}: массив '{name}' слишком длинный"));
            }
            for item in items {
                if let Value::String(s) = item {
                    if s.len() > limits.max_text_len {
                        errors.push(format!("{at}: '{name}' содержит слишком длинную строку"));
                    }
                } else if !item.is_null() && !item.is_boolean() && !item.is_number() {
                    errors.push(format!("{at}: '{name}' — вложенные структуры не разрешены"));
                }
            }
        }
        Value::Object(_) => {
            errors.push(format!("{at}: свойство '{name}' — объект не разрешён"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn errs(value: &Value) -> Vec<String> {
        validate(value, &Limits::default()).unwrap_err()
    }

    #[test]
    fn accepts_a_real_hud_spec() {
        let spec = json!({
            "type": "column",
            "children": [
                {"type": "heading", "text": "Инвентарь"},
                {"type": "list", "items": "{inv}", "row": {"type": "text", "text": "{name} × {count}"}},
                {"type": "button", "label": "Закрыть", "onPress": "close_bag"}
            ]
        });
        assert_eq!(validate(&spec, &Limits::default()), Ok(()));
    }

    #[test]
    fn accepts_input_field_with_text_handlers() {
        let spec = json!({
            "type": "column",
            "children": [
                {"type": "input", "label": "Имя", "value": "{name}", "onSubmit": "ask_name"},
                {"type": "input", "password": true, "maxLength": 24, "onChange": "watch_code"}
            ]
        });
        assert_eq!(validate(&spec, &Limits::default()), Ok(()));
        // `input` — лист: вложенных виджетов у него быть не может.
        let errors = errs(&json!({"type": "input", "children": [{"type": "text", "text": "x"}]}));
        assert!(
            errors.iter().any(|e| e.contains("не может иметь children")),
            "{errors:?}"
        );
    }

    #[test]
    fn rejects_unknown_widget_and_code_like_handler() {
        let errors = errs(&json!({ "type": "webview" }));
        assert!(
            errors
                .iter()
                .any(|e| e.contains("неизвестный тип виджета 'webview'"))
        );

        let errors = errs(&json!({
            "type": "column",
            "children": [{ "type": "button", "onPress": "os.execute('rm -rf /')" }]
        }));
        assert!(
            errors.iter().any(|e| e.contains("именем функции")),
            "обработчик обязан быть именем, а не кодом: {errors:?}"
        );
    }

    #[test]
    fn row_template_is_allowed_only_on_list_and_grid() {
        let ok = json!({
            "type": "list",
            "items": "{inv}",
            "row": { "type": "row", "children": [{ "type": "text", "text": "{name}" }] }
        });
        assert_eq!(validate(&ok, &Limits::default()), Ok(()));
        let errors = errs(&json!({ "type": "text", "row": { "type": "text", "text": "x" } }));
        assert!(
            errors.iter().any(|e| e.contains("row-шаблон")),
            "{errors:?}"
        );
    }

    #[test]
    fn rejects_children_on_leaf_and_nested_objects() {
        let errors = errs(&json!({"type": "text", "text": "x", "children": []}));
        assert!(errors.iter().any(|e| e.contains("не может иметь children")));
        let errors = errs(&json!({"type": "text", "style": {"a": 1}}));
        assert!(errors.iter().any(|e| e.contains("объект не разрешён")));
    }

    #[test]
    fn rejects_trees_beyond_depth_limit() {
        let limits = Limits {
            max_spec_depth: 2,
            ..Limits::default()
        };
        let deep = json!({
            "type": "column",
            "children": [{
                "type": "column",
                "children": [{
                    "type": "column",
                    "children": [{"type": "text", "text": "ooops"}]
                }]
            }]
        });
        let errors = validate(&deep, &limits).unwrap_err();
        assert!(errors.iter().any(|e| e.contains("глубина")));
    }
}
