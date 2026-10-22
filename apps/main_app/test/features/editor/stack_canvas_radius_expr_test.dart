// Формула скругления стека: в шите «Холст и фон стека» рядом с числом живёт
// ряд «Формула скругления». Проверяем то, ради чего он добавлен: строка из
// пикера доезжает до документа, число над ней остаётся запасным значением, а
// снятие формулы не оставляет в JSON пустого ключа.

import 'package:canvas_app/features/editor/screens/node_content/stack_canvas/stack_canvas_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

ContentItem _stack({String? radiusExpr}) => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  borderRadius: 12,
  numericExprs: radiusExpr == null ? null : {'borderRadius': radiusExpr},
  children: [
    ContentItem(
      id: 'txt',
      type: 'text',
      text: 'привет',
      anchorLeft: 0,
      anchorTop: 0,
      anchorRight: 0,
      anchorBottom: 0,
      offsetLeft: 16,
      offsetTop: 8,
      offsetRight: 116,
      offsetBottom: 48,
    ),
  ],
);

void main() {
  late List<ContentItem> saved;

  Future<void> pumpCanvas(
    WidgetTester tester,
    ContentItem stack, {
    Size surface = const Size(800, 600),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    saved = [];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StackCanvasScreen(
            stackItem: stack,
            questId: 'q-radius',
            nodeId: 'n-test',
            onAutoSave: (payload) async {
              saved.add(payload['item']! as ContentItem);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> openStackSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Холст и фон стека'));
    await tester.pumpAndSettle();
  }

  /// Ряд формулы стоит под полями холста: без прокрутки тап проходит мимо
  /// вьюпорта и ничего не нажимает.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  String radiusRowText(WidgetTester tester) => tester
      .widget<Text>(
        find
            .descendant(
              of: find.byType(Row),
              matching: find.textContaining('Формула скругления'),
            )
            .first,
      )
      .data!;

  testWidgets('формула из документа показывается в шите', (tester) async {
    await pumpCanvas(tester, _stack(radiusExpr: 'hp / 4'));
    await openStackSheet(tester);

    expect(radiusRowText(tester), contains('hp / 4'));
    expect(find.byTooltip('Снять формулу'), findsOneWidget);
  });

  testWidgets(
    'без формулы ряд честно говорит про число и не предлагает снять',
    (tester) async {
      await pumpCanvas(tester, _stack());
      await openStackSheet(tester);

      expect(radiusRowText(tester), contains('не задана'));
      expect(find.byTooltip('Снять формулу'), findsNothing);
    },
  );

  testWidgets('формула из пикера уходит в документ, число остаётся', (
    tester,
  ) async {
    // Широкое окно: на телефоне поле формул закрыто от клавиатуры и набирается
    // палитрой, а тест печатает именно в него.
    await pumpCanvas(tester, _stack(), surface: const Size(1400, 900));
    await openStackSheet(tester);

    final formulaButton = find.byIcon(Icons.functions);
    await reveal(tester, formulaButton);
    await tester.tap(formulaButton);
    await tester.pumpAndSettle();
    expect(find.byType(ExpressionEditorScreen), findsOneWidget);

    await tester.enterText(
      find
          .descendant(
            of: find.byType(ExpressionEditorScreen),
            matching: find.byType(TextField),
          )
          .first,
      'hp / 4',
    );
    await tester.tap(find.byTooltip('Готово'));
    await tester.pumpAndSettle();

    final stack = saved.last;
    expect(stack.numericExpr('borderRadius'), 'hp / 4');
    // Число в поле над рядом — фоллбэк, движок читает его когда формулы нет.
    expect(stack.borderRadius, 12);
    expect(stack.children!.length, 1, reason: 'содержимое шита не при чём');
  });

  testWidgets('снятие формулы не оставляет пустого ключа', (tester) async {
    await pumpCanvas(tester, _stack(radiusExpr: 'hp / 4'));
    await openStackSheet(tester);

    final clearButton = find.byTooltip('Снять формулу');
    await reveal(tester, clearButton);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    final stack = saved.last;
    expect(stack.numericExpr('borderRadius'), isNull);
    expect(stack.numericExprs, isNull);
    // Пустая карта не должна уезжать в JSON: иначе квест хранит
    // {"borderRadius":""} и движок считает её формулой.
    expect(stack.toJson().containsKey('numericExprs'), isFalse);
    expect(stack.borderRadius, 12);
    expect(radiusRowText(tester), contains('не задана'));
  });
}
