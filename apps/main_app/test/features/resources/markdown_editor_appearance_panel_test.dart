// «Поле для текста маленькое и неудобно вводить и редактировать; настройки по
// типу эффекта печати и другие штуки вынести куда-то отдельно».
//
// Над полем ввода стояли три строки (шрифт блока, размер, появление) —
// ~160 px из ~600 доступных, причём строка «Появление» вырастает вдвое, как
// только режим включён. Теперь это отдельная панель, которая открывается
// кнопкой в шапке и ничего не съедает у поля.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ: тесты проверяют поведение, а не разметку —
//  * «выбор из панели доезжает до результата» падает, если панель пишет в
//    локальную копию значений (или если `_result()` потерял поле, как в #286);
//  * «панель открывается кнопкой в шапке, а не лежит в теле экрана» падает,
//    если строки вернуть в Column над редактором — вместе с ним падает и
//    тест высоты поля.

import 'package:canvas_app/features/resources/screens/markdown_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Редактор на телефоне: 420×760 — та поверхность, на которой жалоба и
  /// видна (на широком окне строки не съедали бы столько места).
  ///
  /// `binding.setSurfaceSize` в этой связке Flutter 3.47 до MediaQuery не
  /// доходит (проверено: physicalSize остаётся 2400×1800), поэтому размер
  /// ставится на самом view, а dpr=1 делает цифры логическими пикселями.
  Future<void> openEditor(
    WidgetTester tester, {
    Size size = const Size(420, 760),
    String initialText = 'текст',
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MarkdownEditorScreen(initialText: initialText, questId: 'q1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Оформление текста'));
    await tester.pumpAndSettle();
  }

  double fieldHeight(WidgetTester tester) =>
      tester.getRect(find.byType(TextField)).height;

  bool badgeVisible(WidgetTester tester) {
    final badge = tester.widget<Badge>(
      find.ancestor(
        of: find.byIcon(Icons.tune_rounded),
        matching: find.byType(Badge),
      ),
    );
    return badge.isLabelVisible;
  }

  testWidgets('над полем ввода больше нет строк оформления', (tester) async {
    await openEditor(tester);

    expect(find.text('Появление'), findsNothing);
    expect(find.text('Размер'), findsNothing);
    expect(find.text('Шрифт блока: как в квесте'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('поле ввода получает освободившуюся высоту', (tester) async {
    await openEditor(tester);

    // 760 − шапка (~112) − нижняя панель (~52) − отступы (~32): остаётся
    // ~560. Со строками оформления было ~400, поэтому порог 480 — это
    // «выросли не просто на чуть-чуть».
    expect(fieldHeight(tester), greaterThanOrEqualTo(480));
  });

  testWidgets('панель открывается кнопкой в шапке и несёт все контролы', (
    WidgetTester tester,
  ) async {
    await openEditor(tester);
    await openPanel(tester);

    expect(find.text('Появление'), findsOneWidget);
    expect(find.text('Размер'), findsOneWidget);
    expect(find.text('Шрифт блока: как в квесте'), findsOneWidget);
    // Два ползунка: размер и скорость появления (скорость — только когда
    // режим включён, поэтому здесь один).
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('выбор из панели доезжает до результата редактора', (
    tester,
  ) async {
    MarkdownEditorResult? result;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 760);
    addTearDown(tester.view.reset);
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
                          initialText: 'текст',
                          questId: 'q1',
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

    await openPanel(tester);
    await tester.tap(find.text('Печать'));
    await tester.pump();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Закрыть и сохранить'));
    await tester.pumpAndSettle();

    expect(result?.textReveal, 'typewriter');
  });

  testWidgets('кнопка оформления подсвечивается, когда настройка задана', (
    tester,
  ) async {
    await openEditor(tester, initialText: 'текст');
    expect(badgeVisible(tester), isFalse, reason: 'дефолт — без точки');

    await openPanel(tester);
    await tester.tap(find.text('Плавно'));
    await tester.pump();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();

    expect(badgeVisible(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('на широком окне панель — диалог, а не шит', (tester) async {
    await openEditor(tester, size: const Size(1200, 800));
    final before = fieldHeight(tester);

    await openPanel(tester);
    expect(find.text('Оформление текста'), findsOneWidget);
    expect(find.text('Появление'), findsOneWidget);

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Появление'), findsNothing);
    // Диалог не должен был «съесть» редактор: высота поля та же.
    expect(fieldHeight(tester), closeTo(before, 1));
  });
}
