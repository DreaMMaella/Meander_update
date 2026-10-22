// Размер шрифта текстового айтема: редактор markdown возвращает его в
// результате, а вызывателю, которому поле некуда применить (модалка хранит
// только строку), контрол не показываем.
//
// Строки оформления (шрифт/размер/появление) убраны из-под поля ввода в
// отдельную панель по кнопке в шапке, поэтому каждый тест сначала открывает
// панель.

import 'package:canvas_app/features/resources/screens/markdown_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Оформление текста'));
    await tester.pumpAndSettle();
  }

  Future<void> closePanel(WidgetTester tester) async {
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
  }

  Future<MarkdownEditorResult?> openAndClose(
    WidgetTester tester, {
    double? initialTextSize,
    bool supportsTextSize = true,
    bool dragSliderToCenter = false,
  }) async {
    MarkdownEditorResult? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await Navigator.push<MarkdownEditorResult>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => MarkdownEditorScreen(
                          initialText: 'привет',
                          questId: 'q1',
                          initialTextSize: initialTextSize,
                          supportsTextSize: supportsTextSize,
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (dragSliderToCenter) {
      await openPanel(tester);
      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);
      await tester.tapAt(tester.getRect(slider).center);
      await tester.pumpAndSettle();
      // Панель надо закрыть: стрелка выхода под ней недоступна.
      await closePanel(tester);
    }
    await tester.tap(find.byTooltip('Закрыть и сохранить'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('ползунок отдаёт выбранный размер в результате', (tester) async {
    final result = await openAndClose(tester, dragSliderToCenter: true);
    // Середина дорожки 8…64 с шагом 1 — ровно 36 px.
    expect(result?.textSize, 36.0);
  });

  testWidgets('начальный размер подписывает ползунок', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MarkdownEditorScreen(
            initialText: 'привет',
            questId: 'q1',
            initialTextSize: 24,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openPanel(tester);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 24.0);
    expect(find.text('24 px'), findsOneWidget);
  });

  testWidgets('без начального размера контрол показывает дефолт 16', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MarkdownEditorScreen(initialText: 'привет', questId: 'q1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openPanel(tester);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 16.0);
    expect(find.text('16 px'), findsOneWidget);
    // Сброса нет: значение и так дефолтное.
    expect(find.byTooltip('Сбросить размер'), findsNothing);
  });

  testWidgets('модалка без контрола размера', (tester) async {
    final result = await openAndClose(tester, supportsTextSize: false);
    expect(result?.textSize, isNull);
  });

  testWidgets('модалке не показываются размер и появление, но шрифт остаётся', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MarkdownEditorScreen(
            initialText: 'привет',
            questId: 'q1',
            supportsTextSize: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openPanel(tester);
    expect(find.text('Шрифт блока: как в квесте'), findsOneWidget);
    expect(find.text('Размер'), findsNothing);
    expect(find.text('Появление'), findsNothing);
  });
}
