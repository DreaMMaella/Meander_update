// Редактор: у блока `set_visible` четыре действия, и все они читаемы.
//
// Смысловая пара «скрыть» / «убрать» — в разнице раскладки (место осталось /
// ряд схлопнулся), поэтому подписи нельзя терять. На узком экране
// SegmentedButton делит ширину между сегментами поровну: если подписи не
// хватает места, она либо режется многоточием (терпимо), либо переносится по
// буквам (вот это как раз баг — блок растягивается по высоте). Второй тест
// держит именно перенос: все подписи остаются в одну строку.

import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/widgets/set_visible_block_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _labels = ['Скрыть', 'Убрать', 'Показать', 'Переключить'];

Future<SetVisibleBlock> pumpBlock(
  WidgetTester tester, {
  required double width,
}) async {
  final block = SetVisibleBlock(itemId: 'photo');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SetVisibleBlockWidget(block: block, questId: 'q1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return block;
}

void main() {
  testWidgets('блока хватает на четыре действия', (tester) async {
    final block = await pumpBlock(tester, width: 900);

    for (final label in _labels) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Убрать'));
    await tester.pumpAndSettle();
    expect(block.mode, 'remove');

    await tester.tap(find.text('Скрыть'));
    await tester.pumpAndSettle();
    expect(block.mode, 'hide');
  });

  testWidgets('на узком экране подписи не переносятся по буквам', (
    tester,
  ) async {
    await pumpBlock(tester, width: 360);

    final oneLine = tester.getSize(find.text('Скрыть')).height;
    for (final label in _labels) {
      expect(
        tester.getSize(find.text(label)).height,
        oneLine,
        reason: '$label съехала на вторую строку',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
