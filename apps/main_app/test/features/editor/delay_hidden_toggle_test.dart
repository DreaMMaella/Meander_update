// Диалог задержки/таймера должен уметь ставить и снимать флаг «скрыть отсчёт»:
// плеер по `isHidden` ведёт задержку без прогресс-бара. Раньше этот переключатель
// жил в мёртвом диалоге `node_content_screen`, а живой возвращал только секунды.
// Срез #207 добавил туда же формулу длительности.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/editor/logic/item_editor_helper.dart';

void main() {
  late ({String seconds, bool hidden, String expr})? last;

  Future<void> openDialog({
    required WidgetTester tester,
    String? initialValue,
    bool initialHidden = false,
    String? initialExpr,
  }) async {
    last = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                last = await ItemEditorHelper.showDelayDialog(
                  context: context,
                  questId: 'q1',
                  initialValue: initialValue,
                  initialHidden: initialHidden,
                  initialExpr: initialExpr,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch)).value;

  testWidgets('диалог показывает снятый флаг', (tester) async {
    await openDialog(tester: tester, initialValue: '2.0');

    expect(switchValue(tester), isFalse);
  });

  testWidgets('диалог показывает установленный флаг', (tester) async {
    await openDialog(tester: tester, initialValue: '2.0', initialHidden: true);

    expect(switchValue(tester), isTrue);
  });

  testWidgets('ОК возвращает и секунды, и флаг', (tester) async {
    await openDialog(tester: tester, initialValue: '1,5');

    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();

    expect(last, isNotNull);
    expect(last!.seconds, '1.5');
    expect(last!.hidden, isTrue);
  });

  testWidgets('отмена ничего не возвращает', (tester) async {
    await openDialog(tester: tester, initialValue: '3.0', initialHidden: true);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(last, isNull);
  });

  testWidgets('без формулы строка пустая и крестика нет', (tester) async {
    await openDialog(tester: tester, initialValue: '2.0');

    expect(find.text('Не задана — используем число выше'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();

    expect(last!.expr, isEmpty);
  });

  testWidgets('формула показана и снимается крестиком', (tester) async {
    await openDialog(tester: tester, initialValue: '2.0', initialExpr: 'hp/2');

    expect(find.text('hp/2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();

    // Пустая строка — «автор снял формулу».
    expect(last!.expr, isEmpty);
    expect(last!.seconds, '2.0');
  });
}
