// Числовая формула (`{hp}/2 + 16` в поле отступа) считается движком целиком,
// поэтому перед вызовом её надо привести к выражению: фигурные скобки съедаются
// (автор пишет их по образу `{текст}`), а результат движка надо привести к
// числу — движок отвечает и строкой, и именем ненайденной переменной.
// Здесь — чистые помощники резолвера; вычисление и откат на статическое число
// проверяются в test/widgets/numeric_formula_widget_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/utils/text_variable_resolver.dart'
    show normalizeNumericFormula, numericValueOf;

void main() {
  group('normalizeNumericFormula', () {
    test('скобки съедаются, арифметика остаётся как есть', () {
      expect(normalizeNumericFormula('{hp}/2 + 16'), 'hp/2 + 16');
      expect(normalizeNumericFormula('hp / 2 + 16'), 'hp / 2 + 16');
      expect(normalizeNumericFormula('min(40, hp)'), 'min(40, hp)');
    });

    test('двойные скобки схлопываются до одинарных', () {
      // `{{hp}}` — текстовый маркер экранирования; для числа он то же самое.
      expect(normalizeNumericFormula('{{hp}}/2'), 'hp/2');
    });

    test('пробелы по краям не значимы, пустая формула остаётся пустой', () {
      expect(normalizeNumericFormula('  {hp}  '), 'hp');
      expect(normalizeNumericFormula('   '), isEmpty);
    });
  });

  group('numericValueOf', () {
    test('число и строка с числом — это значение', () {
      expect(numericValueOf(10), 10.0);
      expect(numericValueOf(12.5), 12.5);
      expect(numericValueOf('8'), 8.0);
      expect(numericValueOf(' 12.5 '), 12.5);
      expect(numericValueOf(-3), -3.0);
    });

    test(
      'всё остальное — «значения нет», вызывающий берёт статическое число',
      () {
        for (final bad in [
          null,
          'null',
          'gap',
          'закат',
          '16 px',
          true,
          const [],
          const {},
        ]) {
          expect(numericValueOf(bad), isNull, reason: '$bad');
        }
      },
    );

    test('bool не превращается в 1 или 0', () {
      // `visible = true` в формуле отступа — ошибка автора, а не «1 px».
      expect(numericValueOf(true), isNull);
      expect(numericValueOf(false), isNull);
    });
  });
}
