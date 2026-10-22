// Числовые поля айтема (отступ, зазор ряда, размер текста, скругление) могут
// браться из формулы: `ContentItem.numericExprs` — карта имя поля → выражение,
// которое движок считает целиком. Здесь — только семантика модели: что пишется
// в JSON, что остаётся после чтения, и какой фолбэк берёт вызывающий, когда
// формула не сошлась. Само вычисление делает плеер (resolveItemNumeric).

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/content_item.dart';

void main() {
  ContentItem spacer({double? padding, Map<String, String>? exprs}) =>
      ContentItem(
        id: 's1',
        type: 'spacer',
        padding: padding,
        numericExprs: exprs,
      );

  group('numericExprs в JSON', () {
    test('формула переживает round-trip, без неё ключа нет', () {
      final bound = spacer().withNumericExpr('padding', '{hp}/2 + 16');

      final restored = ContentItem.fromJson(bound.toJson());

      expect(restored.numericExpr('padding'), '{hp}/2 + 16');
      expect(restored.padding, isNull);
      expect(spacer().toJson().containsKey('numericExprs'), isFalse);
    });

    test('пустые значения выкидываются при чтении', () {
      final fromDisk = ContentItem.fromJson({
        'id': 's1',
        'type': 'spacer',
        'numericExprs': {'padding': '   ', 'itemSpacing': ''},
      });

      // Без этого Rust-модель после round-trip вернула бы карту без них, и
      // автосейв показывал бы фантомные изменения.
      expect(fromDisk.numericExprs, isNull);
      expect(fromDisk.toJson().containsKey('numericExprs'), isFalse);
    });

    test('не-числовые значения сохраняются как строки выражения', () {
      final fromDisk = ContentItem.fromJson({
        'id': 's1',
        'type': 'spacer',
        'numericExprs': {'itemSpacing': 8},
      });

      expect(fromDisk.numericExpr('itemSpacing'), '8');
    });
  });

  group('withNumericExpr', () {
    test('пробелы съедаются, пустая строка снимает формулу', () {
      final bound = spacer().withNumericExpr('padding', '  min(40, hp)  ');
      expect(bound.numericExpr('padding'), 'min(40, hp)');

      expect(bound.withNumericExpr('padding', '').numericExprs, isNull);
      expect(bound.withNumericExpr('padding', null).numericExprs, isNull);
      expect(bound.withNumericExpr('padding', '  ').numericExprs, isNull);
    });

    test('копирует по имени поля и не трогает остальные', () {
      final both = spacer()
          .withNumericExpr('padding', 'hp')
          .withNumericExpr('borderRadius', 'hp/4');

      expect(both.numericExpr('padding'), 'hp');
      expect(both.numericExpr('borderRadius'), 'hp/4');

      final cleared = both.withNumericExpr('padding', null);
      expect(cleared.numericExpr('padding'), isNull);
      expect(cleared.numericExpr('borderRadius'), 'hp/4');
    });

    test('copyWith без force не затирает карту', () {
      final bound = spacer(exprs: {'padding': 'hp'});

      expect(bound.copyWith(padding: 30).numericExpr('padding'), 'hp');
    });
  });

  group('resolveNumeric', () {
    test('без формулы статическое значение берётся даже с вычисленным', () {
      final item = spacer(padding: 12);

      // Отрицательный контроль: если убрать проверку numericExpr, тут бы
      // пролезла формула чужого поля.
      expect(
        item.resolveNumeric('padding', evaluatedValue: 99, staticValue: 12),
        12.0,
      );
      expect(
        item.resolveNumeric('itemSpacing', evaluatedValue: 99, staticValue: 8),
        8.0,
      );
    });

    test('вычисленная формула важнее статического числа', () {
      final item = spacer(padding: 12).withNumericExpr('padding', 'hp/2');

      expect(
        item.resolveNumeric('padding', evaluatedValue: 30, staticValue: 12),
        30.0,
      );
    });

    test('null, NaN и бесконечность — откат на статическое число', () {
      final item = spacer(padding: 12).withNumericExpr('padding', 'hp/2');

      for (final bad in [null, double.nan, double.infinity]) {
        expect(
          item.resolveNumeric('padding', evaluatedValue: bad, staticValue: 12),
          12.0,
          reason: '$bad',
        );
      }
    });
  });
}
