/// Фасад канонизации/валидации скриптов в ядре (план 020-B).
///
/// Ядро — единственный источник правды о легаси-формах: алиасы типов,
/// title-события, milliseconds, variable/comparison-условия. Клиентский
/// parser.dart остаётся офлайн-fallback'ом; паритет гарантируется
/// golden-фикстурами `crates/mnd-core/tests/fixtures/script_format`.
library;

import 'dart:convert';

import 'package:mnd_core/src/gen/api/script_executor.dart' as gen;

class ScriptFormat {
  ScriptFormat._();

  /// Канонизация скрипта (идемпотентно). Возвращает JSON-строку.
  static Future<String> normalizeJson(String scriptJson) =>
      gen.normalizeScriptJson(scriptJson: scriptJson);

  /// Удобная обёртка: Map → нормализованный Map.
  static Future<Map<String, dynamic>> normalize(
    Map<String, dynamic> script,
  ) async {
    final out = await normalizeJson(jsonEncode(script));
    return jsonDecode(out) as Map<String, dynamic>;
  }

  /// Каноническое имя типа блока (null = тип неизвестен даже как алиас;
  /// такой блок всё равно сохранится as-is через UnknownBlock-семантику).
  static String? canonicalBlockType(String rawType) =>
      gen.canonicalBlockType(rawType: rawType);

  /// Структурная валидация: {errors:[…], warnings:[…]}.
  static Future<ScriptValidationReport> validate(
    Map<String, dynamic> script,
  ) async {
    final raw = await gen.validateScriptJson(scriptJson: jsonEncode(script));
    return ScriptValidationReport.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }
}

class ScriptValidationReport {
  final List<ScriptValidationIssue> errors;
  final List<ScriptValidationIssue> warnings;

  const ScriptValidationReport({required this.errors, required this.warnings});

  bool get isValid => errors.isEmpty;

  factory ScriptValidationReport.fromJson(Map<String, dynamic> json) {
    List<ScriptValidationIssue> parse(String key) =>
        (json[key] as List? ?? [])
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (m) => ScriptValidationIssue(
                code: m['code']?.toString() ?? '',
                path: m['path']?.toString() ?? '',
                message: m['message']?.toString() ?? '',
              ),
            )
            .toList();
    return ScriptValidationReport(
      errors: parse('errors'),
      warnings: parse('warnings'),
    );
  }
}

class ScriptValidationIssue {
  final String code;
  final String path;
  final String message;

  const ScriptValidationIssue({
    required this.code,
    required this.path,
    required this.message,
  });

  @override
  String toString() => '[$code] $path: $message';
}
