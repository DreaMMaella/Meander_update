//! FFI-слой для скриптового исполнителя.

use std::collections::HashMap;

use flutter_rust_bridge::frb;

use crate::api::models::EventType;
use crate::api::runtime::ScriptRuntimeState;

use mnd_core::executor::{self, ScriptExecutor};
use mnd_core::runtime::ScriptRuntime;

// ---------------------------------------------------------------------------
// Конфигурация
// ---------------------------------------------------------------------------

pub fn configure_engine(json_config: String) {
    let config: serde_json::Value = serde_json::from_str(&json_config).unwrap_or_default();
    let debug_logs = config
        .get("debug_logs_enabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let exec_config = executor::ExecutorConfig {
        expression_engine: None,
        asset_store: None,
        logger: None,
        debug_logs_enabled: debug_logs,
    };
    executor::configure(exec_config);
}

// ---------------------------------------------------------------------------
// Дельта-результат execute
// ---------------------------------------------------------------------------

/// Результат `execute_script` в формате дельты.
///
/// Содержит только ИЗМЕНЁННЫЕ относительно входного состояния переменные
/// и таблицы. Клиент применяет их точечно и не перезаписывает то, что
/// скрипт не трогал. Это исключает «воскрешение» устаревших значений
/// при повторных execute с созданием свежего стейта.
#[frb]
pub struct ScriptExecuteResult {
    /// Id узла перехода (go_to_node), если блок вернул результат.
    pub transition: Option<String>,
    /// ИЗМЕНЁННЫЕ переменные: key → JSON-строка значения.
    pub set_variable: HashMap<String, String>,
    /// ИЗМЕНЁННЫЕ таблицы: name → (key → JSON-строка значения).
    pub set_table: HashMap<String, HashMap<String, String>>,
}

fn diff_variables(
    input: &HashMap<String, String>,
    final_state: &ScriptRuntimeState,
) -> HashMap<String, String> {
    let mut diff = HashMap::new();
    for (k, v) in final_state.all_variables() {
        let final_json = serde_json::to_string(v).unwrap_or_default();
        let input_json = input.get(k);
        if input_json != Some(&final_json) {
            diff.insert(k.clone(), final_json);
        }
    }
    diff
}

fn diff_tables(
    input: &HashMap<String, HashMap<String, String>>,
    final_state: &ScriptRuntimeState,
) -> HashMap<String, HashMap<String, String>> {
    let mut diff = HashMap::new();
    for (name, table) in final_state.all_tables() {
        let mut final_data: HashMap<String, String> = table
            .data
            .iter()
            .filter(|(k, _)| !k.starts_with("__"))
            .map(|(k, v)| (k.clone(), serde_json::to_string(v).unwrap_or_default()))
            .collect();
        let mut full_table_json = table.to_json();
        if let Some(data_obj) = full_table_json
            .get_mut("data")
            .and_then(|d| d.as_object_mut())
        {
            data_obj.retain(|k, _| !k.starts_with("__"));
        }
        final_data.insert(
            "__table_full_json__".to_string(),
            serde_json::to_string(&full_table_json).unwrap_or_default(),
        );
        let input_data = input.get(name);
        if input_data != Some(&final_data) {
            diff.insert(name.clone(), final_data);
        }
    }
    diff
}

// ---------------------------------------------------------------------------
// Операции
// ---------------------------------------------------------------------------

pub fn check_script_event_type(script_json: String) -> String {
    let script: serde_json::Value = serde_json::from_str(&script_json).unwrap_or_default();
    executor::check_script_event_type(script.as_object().unwrap_or(&serde_json::Map::new()))
        .name()
        .to_string()
}

pub fn has_executable_blocks(
    script_json: String,
    event_type: EventType,
    function_name: Option<String>,
    content_item_id: Option<String>,
    allow_target_mismatch_fallback: bool,
) -> bool {
    let script: serde_json::Value = serde_json::from_str(&script_json).unwrap_or_default();
    executor::has_executable_blocks_for_event(
        script.as_object().unwrap_or(&serde_json::Map::new()),
        event_type.into(),
        &function_name,
        &content_item_id,
        allow_target_mismatch_fallback,
    )
}

pub fn evaluate_condition(
    script_json: String,
    state: &mut ScriptRuntimeState,
    event_type: EventType,
    function_name: Option<String>,
    content_item_id: Option<String>,
    allow_target_mismatch_fallback: bool,
    allow_state_mutation: bool,
) -> bool {
    let script: serde_json::Value = serde_json::from_str(&script_json).unwrap_or_default();
    executor::evaluate_condition(
        script.as_object().unwrap_or(&serde_json::Map::new()),
        state,
        event_type.into(),
        &function_name,
        &content_item_id,
        allow_target_mismatch_fallback,
        allow_state_mutation,
    )
}

/// Исполнить скрипт и вернуть дельту мутаций.
///
/// Stateless: входные переменные/таблицы передаются как JSON-строки,
/// результат — только ИЗМЕНЁННЫЕ переменные и таблицы + переход.
/// Клиент применяет дельту точечно и никогда не перезаписывает
/// неизменённые данные.
#[allow(clippy::too_many_arguments)]
pub fn execute_script(
    script_json: String,
    variables: HashMap<String, String>,
    tables: HashMap<String, HashMap<String, String>>,
    quest_id: String,
    event_type: EventType,
    function_name: Option<String>,
    content_item_id: Option<String>,
    allow_target_mismatch_fallback: bool,
    // Вложенные скрипты: path → JSON. Позволяет ядру резолвить
    // `call_script`/`call_function` блоки без файловой системы.
    embedded_scripts: HashMap<String, String>,
) -> ScriptExecuteResult {
    let mut state = ScriptRuntimeState::from_json(variables.clone(), tables.clone());
    let script: serde_json::Value = serde_json::from_str(&script_json).unwrap_or_default();

    let embedded: HashMap<String, serde_json::Value> = embedded_scripts
        .into_iter()
        .filter_map(|(k, v)| serde_json::from_str(&v).ok().map(|parsed| (k, parsed)))
        .collect();

    let transition = ScriptExecutor::new()
        .with_embedded_scripts(embedded)
        .execute(
            script.as_object().unwrap_or(&serde_json::Map::new()),
            &mut state,
            &quest_id,
            event_type.into(),
            &function_name,
            &content_item_id,
            allow_target_mismatch_fallback,
            &mut None,
        )
        .ok()
        .flatten();

    ScriptExecuteResult {
        transition,
        set_variable: diff_variables(&variables, &state),
        set_table: diff_tables(&tables, &state),
    }
}

pub fn evaluate_expression(input_json: String, state: &mut ScriptRuntimeState) -> String {
    let input: serde_json::Value = serde_json::from_str(&input_json).unwrap_or_default();
    let result = executor::evaluate_expression(Some(input), state);
    serde_json::to_string(&result).unwrap_or_else(|_| "null".into())
}

// ---------------------------------------------------------------------------
// Плоские (state-less) функции — передают переменные/таблицы как HashMap,
// не требуют мутабельного Rust-opaque state.
// Используются в синхронных точках клиента (build, parseText).
// ---------------------------------------------------------------------------

/// Вычислить выражение без мутабельного Rust-объекта.
/// Принимает переменные и таблицы как плоские JSON-строки.
/// Синхронная версия — вызывается из build/parseText.
#[frb(sync)]
pub fn evaluate_expression_flat(
    input_json: String,
    variables: HashMap<String, String>,
    tables: HashMap<String, HashMap<String, String>>,
) -> String {
    let mut state = ScriptRuntimeState::from_json(variables, tables);
    let input: serde_json::Value = serde_json::from_str(&input_json).unwrap_or_default();
    let result = executor::evaluate_expression(Some(input), &mut state);
    serde_json::to_string(&result).unwrap_or_else(|_| "null".into())
}

/// Определить тип события скрипта (плоская).
#[frb(sync)]
pub fn check_script_event_type_flat(script_json: String) -> String {
    check_script_event_type(script_json)
}

/// Проверить наличие исполнимых блоков (плоская).
#[frb(sync)]
pub fn has_executable_blocks_flat(
    script_json: String,
    event_type: EventType,
    function_name: Option<String>,
    content_item_id: Option<String>,
    allow_target_mismatch_fallback: bool,
) -> bool {
    has_executable_blocks(
        script_json,
        event_type,
        function_name,
        content_item_id,
        allow_target_mismatch_fallback,
    )
}

/// Вычислить условие без мутабельного Rust-объекта.
/// Синхронная версия — вызывается из ConditionalContentWrapper.build.
/// Результат плоского вызова `evaluate_condition_flat`: bool + дельта мутаций
/// прелюдии (паритет эталона: `evaluateCondition(allowStateMutation: true)`
/// применял прелюдию к состоянию клиента прямо в процессе оценки).
#[frb]
pub struct ScriptEvaluateResult {
    pub result: bool,
    /// ИЗМЕНЁННЫЕ переменные: key → JSON-строка значения.
    pub set_variable: HashMap<String, String>,
    /// ИЗМЕНЁННЫЕ таблицы: name → (key → JSON-строка значения).
    pub set_table: HashMap<String, HashMap<String, String>>,
}

#[frb(sync)]
#[allow(clippy::too_many_arguments)]
pub fn evaluate_condition_flat(
    script_json: String,
    variables: HashMap<String, String>,
    tables: HashMap<String, HashMap<String, String>>,
    event_type: EventType,
    function_name: Option<String>,
    content_item_id: Option<String>,
    allow_target_mismatch_fallback: bool,
    allow_state_mutation: bool,
) -> ScriptEvaluateResult {
    let mut state = ScriptRuntimeState::from_json(variables.clone(), tables.clone());
    let script: serde_json::Value = serde_json::from_str(&script_json).unwrap_or_default();
    let result = executor::evaluate_condition(
        script.as_object().unwrap_or(&serde_json::Map::new()),
        &mut state,
        event_type.into(),
        &function_name,
        &content_item_id,
        allow_target_mismatch_fallback,
        allow_state_mutation,
    );
    ScriptEvaluateResult {
        result,
        set_variable: diff_variables(&variables, &state),
        set_table: diff_tables(&tables, &state),
    }
}

// ---------------------------------------------------------------------------
// Утилиты
// ---------------------------------------------------------------------------

pub fn execute_table_operation(
    block_json: String,
    state: &mut ScriptRuntimeState,
) -> Option<String> {
    let block: serde_json::Value = serde_json::from_str(&block_json).unwrap_or_default();
    ScriptExecutor::new()
        .execute_table_operation(block.as_object().unwrap_or(&serde_json::Map::new()), state)
        .ok()
        .flatten()
}

pub fn evaluate_condition_logic(block_json: String, state: &mut ScriptRuntimeState) -> bool {
    let block: serde_json::Value = serde_json::from_str(&block_json).unwrap_or_default();
    executor::evaluate_condition_logic(block.as_object().unwrap_or(&serde_json::Map::new()), state)
}

pub fn values_equal(left_json: String, right_json: String) -> bool {
    let left: serde_json::Value = serde_json::from_str(&left_json).unwrap_or_default();
    let right: serde_json::Value = serde_json::from_str(&right_json).unwrap_or_default();
    mnd_core::expression::values_equal(&left, &right)
}

/// Канонизация скрипта: легаси-алиасы/поля → канонический формат.
/// Идемпотентно; возвращает JSON-строку.
pub fn normalize_script_json(script_json: String) -> String {
    match serde_json::from_str::<serde_json::Value>(&script_json) {
        Ok(mut v) => {
            mnd_core::script_format::normalize_script(&mut v);
            serde_json::to_string(&v).unwrap_or(script_json)
        }
        Err(_) => script_json,
    }
}

/// Каноническое имя типа блока (для автодополнения/валидации UI).
#[frb(sync)]
pub fn canonical_block_type(raw_type: String) -> Option<String> {
    let mut probe = serde_json::json!({"type": raw_type});
    // Переиспользуем таблицу алиасов: канонизация одного блока.
    if let Some(obj) = probe.as_object_mut() {
        mnd_core::script_format::normalize_block(obj);
    }
    probe
        .get("type")
        .and_then(serde_json::Value::as_str)
        .map(String::from)
}

/// Структурная валидация скрипта: {errors:[{code,path,message}], warnings:[…]}.
pub fn validate_script_json(script_json: String) -> String {
    let parsed: serde_json::Value =
        serde_json::from_str(&script_json).unwrap_or(serde_json::Value::Null);
    let empty = serde_json::Map::new();
    let map = parsed.as_object().unwrap_or(&empty);
    let issues = mnd_core::script_format::validate_script(map);
    let to_obj = |i: &mnd_core::script_format::ValidationIssue| {
        serde_json::json!({
            "code": i.code,
            "path": i.path,
            "message": i.message,
            "severity": match i.severity {
                mnd_core::script_format::Severity::Error => "error",
                mnd_core::script_format::Severity::Warning => "warning",
            },
        })
    };
    let report = serde_json::json!({
        "errors": issues.iter().filter(|i| i.severity == Severity::Error).map(to_obj).collect::<Vec<_>>(),
        "warnings": issues.iter().filter(|i| i.severity == Severity::Warning).map(to_obj).collect::<Vec<_>>(),
    });
    serde_json::to_string(&report).unwrap_or_else(|_| "{}".into())
}

use mnd_core::script_format::Severity;
