//! FFI-слой статического валидатора квеста.
//!
//! Обёртка над `mnd_core::validation::analyze_quest`. Результат —
//! JSON-строка `ValidationReport` (`stats` + `diagnostics`), которую
//! клиент парсит Dart-моделью `QuestValidationReport`.

use mnd_core::validation::analyze_quest;

/// Статический анализ каталога квеста `quests/<quest_id>/` в `quest_root`.
///
/// Возвращает JSON-отчёт `ValidationReport` (всегда валидный JSON, даже при
/// ошибках чтения — в этом случае в `diagnostics` будет `MissingConfig`).
pub fn run_quest_validation(quest_id: String, quest_root: String) -> String {
    serde_json::to_string(&analyze_quest(&quest_id, &quest_root))
        .unwrap_or_else(|_| r#"{"stats":{"quest_id":"","nodes":0,"templates":0,"scripts":0,"items":0,"warnings":0,"errors":0},"diagnostics":[]}"#.to_string())
}

/// Версия отчёта валидации (для клиентской миграции формата).
pub fn quest_validation_schema_version() -> u32 {
    1
}
