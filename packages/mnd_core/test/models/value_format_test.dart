import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

void main() {
  group('formatScriptValue — Баг 4 (12.0 → «12», без .0)', () {
    test('num 12.0 отображается как «12»', () {
      expect(formatScriptValue(12.0), '12');
    });

    test('num 12 отображается как «12»', () {
      expect(formatScriptValue(12), '12');
    });

    test('дробное 12.5 остаётся «12.5»', () {
      expect(formatScriptValue(12.5), '12.5');
    });

    test('строка «12.0» отображается как «12»', () {
      expect(formatScriptValue('12.0'), '12');
    });

    test('строка «08:28» не трогается (время, не число)', () {
      expect(formatScriptValue('08:28'), '08:28');
    });

    test('строка «0.0» отображается как «0»', () {
      expect(formatScriptValue('0.0'), '0');
    });

    test('null → пустая строка', () {
      expect(formatScriptValue(null), '');
    });
  });
}