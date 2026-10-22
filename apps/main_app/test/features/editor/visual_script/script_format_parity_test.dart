/// Golden-паритет Dart↔Rust нормализации скриптов (план 020-B3).
///
/// Читает ТЕ ЖЕ фикстуры, что и Rust-тест `script_format::golden_tests`:
/// `crates/mnd-core/tests/fixtures/script_format/*.json`.
/// Требует собранного .so (см. regression_ffi_test) — иначе skip.
library;

import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/features/editor/screens/visual_script_editor/parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/engine/script_format.dart' as core;

import '../../../helpers/ffi_so_path.dart' as helpers;

void main() {
  final soPath = helpers.resolveFfiSoPath();
  if (soPath == null) {
    test('skipped: нет .so', () {
      markTestSkipped('libmnd_ffi.so не собран');
    });
    return;
  }

  setUpAll(() => helpers.soInit(soPath));

  final dir = Directory(
    '../../crates/mnd-core/tests/fixtures/script_format',
  );
  final fixtures = dir.existsSync()
      ? dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
      : <File>[];

  test('фикстуры на месте', () {
    expect(fixtures.length, greaterThanOrEqualTo(6));
  });

  for (final file in fixtures) {
    test('parity: ${file.uri.pathSegments.last}', () async {
      final case_ = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final input = case_['input'] as Map<String, dynamic>;
      final canonical = case_['canonical'];

      // 1. Ядро нормализует вход до канона.
      final viaCore = await core.ScriptFormat.normalize(input);
      expect(viaCore, canonical, reason: 'Rust normalize');

      // 2. Dart-фолбэк даёт тот же канон.
      final viaDart = {
        'blocks': ScriptParser.normalizeScriptBlocks(
          (input['blocks'] as List? ?? []),
        ),
      };
      expect(viaDart['blocks'], canonical['blocks'],
          reason: 'Dart normalize fallback');

      // 3. Валидация ядра не рождает ошибок на валидных фикстурах.
      final report = await core.ScriptFormat.validate(canonical as Map<String, dynamic>);
      expect(report.errors, isEmpty, reason: 'unexpected errors');
    });
  }
}
