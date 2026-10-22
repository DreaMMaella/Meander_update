// Редактор формул на широком окне: поле и палитра стоят рядом, а не стопкой.
// На телефоне проверка та же, но с точностью до наоборот — колонкой.

import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: ExpressionEditorScreen(initialValue: '1 + 2', questId: 'q'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('на широком окне поле слева, палитра справа', (tester) async {
    await _pump(tester, const Size(1400, 900));

    final field = tester.getRect(find.byType(TextField));
    final padRect = tester.getRect(find.text('7'));
    // Рядом, а не друг под другом: центр палитры правее центра поля.
    expect(padRect.center.dx, greaterThan(field.center.dx));
    expect(field.width, greaterThan(600));
  });

  testWidgets('на телефоне остаётся стопкой: палитра под полем', (
    tester,
  ) async {
    await _pump(tester, const Size(390, 844));

    final field = tester.getRect(find.byType(TextField));
    final padRect = tester.getRect(find.text('7'));
    expect(padRect.top, greaterThan(field.bottom));
  });

  testWidgets('на ПК формулу набирают с клавиатуры', (tester) async {
    await _pump(tester, const Size(1400, 900));

    await tester.enterText(find.byType(TextField), '9 * 9');
    expect(find.text('9 * 9'), findsOneWidget);
  });
}
