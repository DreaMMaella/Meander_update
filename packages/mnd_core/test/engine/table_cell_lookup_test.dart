// Резолв ячеек таблиц из текста: {t["колонка"][N]} и {t[N]["колонка"]},
// где N — визуальный (1-based) номер строки.
//
// Проверяется Rust-ядро (FFI).

library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/engine/script_executor.dart';
import 'package:mnd_core/models/quest_table.dart';
import 'package:mnd_core/runtime/in_memory_script_runtime_state.dart';
import 'package:mnd_core/src/gen/frb_generated.dart' as gen;

final String? _soPath = () {
  final env = Platform.environment['MND_FFI_SO'];
  if (env != null && File(env).existsSync()) return env;
  for (final c in [
    '../../target/release/libmnd_ffi.so',
    '../target/release/libmnd_ffi.so',
  ]) {
    if (File(c).existsSync()) return File(c).absolute.path;
  }
  return null;
}();

final String _skipReason = _soPath == null
    ? 'libmnd_ffi.so не найден. Соберите: cargo build -p mnd-ffi --release'
    : '';

QuestTable _sampleTable() => QuestTable(
      name: 'rfd',
      columns: const ['тест', 'ыа', 'ыав'],
      rows: [
        {'тест': 'res/images/9e3735b6.png', 'ыа': '{ID}', 'ыав': ''},
        {'тест': 'тест', 'ыа': '', 'ыав': ''},
        {'тест': 'в', 'ыа': '', 'ыав': ''},
      ],
      data: const {'ключ': 'значение из data'},
    );

InMemoryScriptRuntimeState _state() =>
    InMemoryScriptRuntimeState(tables: {'rfd': _sampleTable()});

void main() {
  if (_soPath != null) {
    setUpAll(() async {
      await gen.RustLib.init(
        externalLibrary: ExternalLibrary.open(_soPath!),
      );
    });
  }

  group('Резолв ячеек таблиц: Rust-ядро (FFI)',
      skip: _soPath == null ? _skipReason : null, () {
    test('колонка сначала, 1-based строки', () {
      final s = _state();
      expect(ScriptExecutor.evaluateExpression('rfd["тест"][1]', s),
          'res/images/9e3735b6.png');
      expect(ScriptExecutor.evaluateExpression('rfd["тест"][2]', s), 'тест');
      expect(ScriptExecutor.evaluateExpression('rfd["тест"][3]', s), 'в');
    });

    test('строка сначала, потом колонка', () {
      final s = _state();
      expect(ScriptExecutor.evaluateExpression('rfd[1]["тест"]', s),
          'res/images/9e3735b6.png');
      expect(ScriptExecutor.evaluateExpression('rfd[2]["тест"]', s), 'тест');
    });

    test('пустая ячейка → пустая строка', () {
      final s = _state();
      expect(ScriptExecutor.evaluateExpression('rfd["ыав"][3]', s), '');
    });

    test('приоритет data и null за пределами', () {
      final s = _state();
      expect(ScriptExecutor.evaluateExpression('rfd["ключ"]', s),
          'значение из data');
      expect(ScriptExecutor.evaluateExpression('rfd["нет"][1]', s), isNull);
      expect(ScriptExecutor.evaluateExpression('rfd["тест"][99]', s), isNull);
      expect(ScriptExecutor.evaluateExpression('rfd[0]["тест"]', s), isNull);
    });

    test('{rfd.rows[1].тест} и {rfd.columns[1]}', () {
      final s = _state();
      expect(ScriptExecutor.evaluateExpression('rfd.rows[1].тест', s),
          'res/images/9e3735b6.png');
      expect(ScriptExecutor.evaluateExpression('rfd.columns[1]', s), 'тест');
    });
  });
}