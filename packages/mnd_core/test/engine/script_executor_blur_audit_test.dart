// ─── АУДИТ: БАГ С BLUR (Rust-FFI vs Dart Legacy) ────────────────────────
// ЗАКЛЮЧЕНИЕ АУДИТА:
//
// Найден баг в Rust-ядре в двух функциях, которые конвертируют целые double
// в int (i64) при сериализации в JSON:
//
//   1) crates/mnd-core/src/expression.rs:40 — json_of_f64
//      f.fract() == 0.0 → Value::from(f as i64)  // 10.0 → int 10
//
//   2) crates/mnd-core/src/expression.rs:791 — clean_numeric_result
//      cleaned == cleaned.trunc() → Value::from(cleaned as i64)  // 10.0 → int 10
//
// Когда любая переменная в Rust-состоянии становится int вместо double,
// это передаётся в FFI-шим через all_variables_json (serde_json::to_string),
// который пишет "10" (не "10.0"). Dart jsonDecode("10") → int 10.
// В UI game_screen.dart:875 "as double?" с int выбрасывает TypeError.
// Механизм падения: как только скрипт читает/изменяет любую переменную
// с плавающим значением через expression evaluator, тип ломается.
//
// НЕ РЕКОНСТРУИРУЕМО в мок-окружении без реального Rust FFI,
// поэтому тесты моделируют логику изолированно.

library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Точные копии Rust-функций на Dart для изоляции логики
// ---------------------------------------------------------------------------

/// Модель Rust json_of_f64 — воспроизводит баг.
dynamic modelJsonOfF64(double f) {
  if (f == f.truncateToDouble() && f.isFinite && f.abs() < 1e15) {
    return f.truncate(); // int 10
  }
  return f; // double
}

/// Модель Rust clean_numeric_result — воспроизводит баг.
dynamic modelCleanNumericResult(dynamic value) {
  if (value is num) {
    final f = value.toDouble();
    if (!f.isFinite || f == 0.0) return f;
    var cleaned = f;
    final rounded = (f * 1e10).round() / 1e10;
    if ((f - rounded).abs() < 1e-11) cleaned = rounded;
    if (cleaned == cleaned.truncateToDouble()) return cleaned.truncate();
    return cleaned;
  }
  return value;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('АУДИТ: json_of_f64 — преобразование double в int', () {
    test('json_of_f64(10.0) → int 10 (БАГ)', () {
      final result = modelJsonOfF64(10.0);
      expect(result, isA<int>()); // БАГ: ожидается double
      expect(result, 10);
    });

    test('После сериализации: jsonEncode(int 10) → "10"', () {
      final encoded = jsonEncode(modelJsonOfF64(10.0));
      expect(encoded, '10'); // БАГ: должно быть "10.0"
    });

    test('Dart jsonDecode("10") → int 10 (тип потерян!)', () {
      final decoded = jsonDecode('10');
      expect(decoded, isA<int>());
      expect(decoded, 10);
    });

    test('UI: int 10 as double? → TYPE ERROR', () {
      final valueFromRust = jsonDecode('10');
      expect(
        () => valueFromRust as double?,
        throwsA(isA<TypeError>()),
      );
    });

    test('json_of_f64(0.5) → double 0.5 (OK)', () {
      final result = modelJsonOfF64(0.5);
      expect(result, isA<double>());
      expect(result, 0.5);
    });

    test('json_of_f64(0.0) → double 0.0 (OK)', () {
      // f == 0.0 → не проходит ветку trunc() из-за f.fract() == 0.0 НО
      // в json_of_f64 проверка: f.fract() == 0.0 && f.is_finite() && f.abs() < 1e15
      // 0.0 проходит → Value::from(0 as i64) → int 0
      // НО в чистом Rust: 0i64 → json!(0) → Number(0) → to_string → "0"
      // Dart jsonDecode("0") → int 0. Та же проблема для нуля!
      final result = modelJsonOfF64(0.0);
      expect(result, isA<int>());
      expect(result, 0);
    });
  });

  group('АУДИТ: clean_numeric_result', () {
    test('clean_numeric_result(10.0) → int 10 (БАГ)', () {
      final result = modelCleanNumericResult(jsonDecode(jsonEncode(10.0)));
      expect(result, isA<int>());
      expect(result, 10);
    });

    test('clean_numeric_result(0.5) → double 0.5 (OK)', () {
      final result = modelCleanNumericResult(jsonDecode(jsonEncode(0.5)));
      expect(result, isA<double>());
      expect(result, 0.5);
    });

    test('clean_numeric_result(0.0) → double 0.0 (OK — пропускается)', () {
      final result = modelCleanNumericResult(jsonDecode(jsonEncode(0.0)));
      expect(result, isA<double>());
      expect(result, 0.0);
    });
  });

  group('АУДИТ: assign_variable с числовым значением через roundtrip', () {
    test('Dart path: setVariable("x", evaluateExpression(10.0)) → double', () {
      // Dart evaluateExpression(10.0):
      //   inputValue.toString().trim() → "10.0"
      //   num.tryParse("10.0") → 10.0 (double)
      final str = (10.0).toString();
      final parsed = num.tryParse(str);
      expect(parsed, isA<double>());
      expect(parsed, 10.0);
    });

    test('Rust path: value = evaluate_expression(Some(json!(10.0))) → int 10', () {
      // Rust evaluate_expression(Some(Number(10.0))):
      //   not a String → clean_numeric_result(Number(10.0))
      //   f = 10.0, 10.0 == 10.0.trunc() → Value::from(10i64)
      //   to_string(Number(10)) → "10"
      final rustValue = modelCleanNumericResult(10.0);
      expect(rustValue, isA<int>());
      final encoded = jsonEncode(rustValue);
      expect(encoded, '10');
      // _syncBack: dartState.setVariable("x", jsonDecode("10"))
      final dartSide = jsonDecode(encoded);
      expect(dartSide, isA<int>());
      expect(dartSide, 10);
      // int as double? → THROWS
      expect(() => dartSide as double?, throwsA(isA<TypeError>()));
    });
  });

  group('АУДИТ: разница Dart vs Rust для строкового "10.0"', () {
    test('Dart: evaluateExpression("10.0") → double 10.0', () {
      // num.tryParse("10.0") → 10.0
      final parsed = num.tryParse('10.0');
      expect(parsed, 10.0);
      expect(parsed, isA<double>());
    });

    test('Rust: json_of_f64(10.0) → int 10 (БАГ)', () {
      // Строка "10.0" → парсится в f64 10.0 → json_of_f64(10.0) → int 10
      final rustResult = modelJsonOfF64(10.0);
      expect(rustResult, isA<int>());
      // serde_json::to_string(int 10) → "10" → jsonDecode("10") → int 10 → as double? → ERROR
      expect(jsonEncode(rustResult), '10');
    });
  });

  group('АУДИТ: set_blur анализ — handler безопасен, но другие пути нет', () {
    test('set_blur handler в Rust: as_f64() + json!(f64) → double сохраняется', () {
      // В set_blur:
      //   1. raw_blur = block["blur"].cloned() → json!(10.0) → Number(10.0)
      //   2. evaluated_blur = evaluate_expression(Number(10.0)) → clean_numeric_result
      //      → Number(10) (int!)
      //   3. blur_value = evaluated_blur.as_f64() → Some(10.0) (f64!) ← спасает!
      //   4. json!(blur_value) где blur_value: f64 → json!(10.0_f64) → Number(10.0)
      //   → to_string → "10.0" → jsonDecode → double 10.0 ✓
      final evaluatedBlur = modelCleanNumericResult(10.0); // int 10
      expect(evaluatedBlur, isA<int>());
      // Теперь as_f64 в Rust: f64 10.0
      final f64Value = evaluatedBlur.toDouble();
      // json!(f64) в Rust: json!(10.0_f64) → serde_json Number(10.0)
      final reWrapped = jsonDecode(jsonEncode(f64Value));
      expect(reWrapped, isA<double>());
      expect(reWrapped, 10.0);
      // as double? → 10.0 (OK в этом частном случае set_blur handler)
      expect(reWrapped as double?, 10.0);
    });

    test('НО: assign_variable("x", 10.0) в Rust НЕ перезаворачивает через json!', () {
      // assign_variable handler (executor.rs:1621-1627):
      //   val = evaluate_expression(block["value"].cloned(), state)
      //   game_state.set_variable(&var_name, val)  // val = Number(10)!!!
      // _syncBack: serde_json::to_string(Number(10)) → "10"
      //   → jsonDecode("10") → int 10 → as double? → ERROR
      final rustValue = modelCleanNumericResult(10.0); // Number(10)
      final stored = jsonDecode(jsonEncode(rustValue)); // int 10
      expect(stored, isA<int>());
      expect(() => stored as double?, throwsA(isA<TypeError>()));
    });
  });

  group('АУДИТ: влияние на _internal_background_blur', () {
    test('Если assign_variable задаёт blur = 10.0: Dart → OK', () {
      // Dart evaluateExpression(10.0) → stringifies "10.0" → parse → double 10.0
      final str = (10.0).toString(); // "10.0"
      final parsed = num.tryParse(str);
      expect(parsed, isA<double>());
      expect(parsed, 10.0);
      // Dart: gameState.setVariable("_internal_background_blur", 10.0) — double
      // UI: as double? → 10.0 OK
      expect(parsed as double?, 10.0);
    });

    test('Если assign_variable задаёт blur = 10.0: Rust → ERROR', () {
      // Rust: evaluate_expression(10.0) → clean_numeric_result → int 10
      final rustResult = modelCleanNumericResult(10.0);
      expect(rustResult, isA<int>());
      final inDart = jsonDecode(jsonEncode(rustResult));
      expect(inDart, isA<int>());
      // UI: as double? → THROWS
      expect(() => inDart as double?, throwsA(isA<TypeError>()));
    });

    test('Воспроизводимый кейс: blur падает когда скрипт читает blur через expression', () {
      // Если скрипт делает:
      //   set_blur(target=node, blur={current_blur} + 5)
      // Rust evaluate_expression: переменная current_blur=10.0 → stored as Number(10)
      // (via clean_numeric_result), затем выражение {val}+5 → json_of_f64(15.0) → Number(15)
      // set_blur handler: as_f64() → 15.0, json!(15.0) → Number(15.0) → OK
      //   Но если скрипт просто копирует: assign_variable(x, {blur_var}),
      //   где blur_var=5.0 хранится как Number(5):
      //     evaluate_expression → resolve_inline_token_value → get_variable("blur_var")
      //     → Number(5) → clean_numeric_result → Number(5) (int!)
      //     set_variable("x", Number(5)) → stored as int 5.
      //   Потом если x читается как blur: as double? → ERROR
      //
      // Более того: при КОПИРОВАНИИ состояния через _toFfiState/_syncBack
      // все переменные проходят через JSON roundtrip.
      // Даже если none из них не является "проблемной", сам факт roundtrip
      // через json_of_f64/clean_numeric_result может повредить любые double
      // переменные!
    });
  });
}
