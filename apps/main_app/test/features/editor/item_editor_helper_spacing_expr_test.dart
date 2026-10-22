// Экран контейнера возвращает формулу зазора всегда — пустой строкой, если её
// сняли, и `null`, если поля не касались (например, при автосейве другой
// настройки). Слияние обязано различать эти два случая: иначе правка любого
// другого поля ряда стирала бы авторскую формулу.

import 'package:canvas_app/features/editor/logic/item_editor_helper.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ContentItem row({double? spacing, String? expr}) => ContentItem(
    id: 'r1',
    type: 'row',
    itemSpacing: spacing,
    numericExprs: expr == null ? null : {'itemSpacing': expr},
  );

  test('null — экран не возвращал формулу, старая остаётся', () {
    final merged = ItemEditorHelper.withSpacingExpr(
      row(spacing: 10, expr: 'hp/2'),
      null,
    );

    expect(merged.numericExpr('itemSpacing'), 'hp/2');
    expect(merged.itemSpacing, 10);
  });

  test('пустая строка — автор снял формулу', () {
    final merged = ItemEditorHelper.withSpacingExpr(
      row(spacing: 10, expr: 'hp/2'),
      '',
    );

    expect(merged.numericExpr('itemSpacing'), isNull);
    expect(merged.numericExprs, isNull);
    expect(merged.itemSpacing, 10, reason: 'число из поля остаётся');
  });

  test('новое выражение заменяет старое', () {
    final merged = ItemEditorHelper.withSpacingExpr(
      row(spacing: 10, expr: 'hp/2'),
      ' min(40, hp) ',
    );

    expect(merged.numericExpr('itemSpacing'), 'min(40, hp)');
  });

  test('формула появляется на ряду, где её не было', () {
    final merged = ItemEditorHelper.withSpacingExpr(row(), '{gap}');

    expect(merged.numericExpr('itemSpacing'), '{gap}');
    expect(merged.itemSpacing, isNull);
  });
}
