// Редактор видео собирает айтем с нуля, поэтому формулы слоя — его
// забота: чужие поля (`padding`, `textSize`, …) уходят как были, скругление
// редактор ведёт сам. Здесь тот сценарий, на котором всё ломалось: слой в
// стеке с формулой отступа и формулой скругления, автор жмёт «Настроить
// видео» и «Сохранить» — формулы должны остаться, а снятая формула скругления
// не должна оставить в документе пустой ключ.

import 'package:canvas_app/features/editor/screens/node_content/video_editor_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/resources/services/resource_providers.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem _video({Map<String, String>? exprs}) => ContentItem(
  id: 'v1',
  type: 'video',
  videoUrl: 'https://example.com/a.mp4',
  videoSourceType: 'url',
  borderRadius: 12,
  padding: 8,
  numericExprs: exprs,
);

void main() {
  late ContentItem? popped;

  Future<void> openEditor(
    WidgetTester tester,
    ContentItem existing, {
    Size surface = const Size(800, 900),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    popped = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          questResourceNamesProvider(
            'q-video',
          ).overrideWith((ref) async => const <String, String>{}),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.push<ContentItem>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => VideoEditorScreen(
                          questId: 'q-video',
                          existingItem: existing,
                        ),
                      ),
                    );
                  },
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
  }

  testWidgets('нетронутый редактор сохраняет формулу скругления', (
    tester,
  ) async {
    await openEditor(tester, _video(exprs: {'borderRadius': 'hp / 4'}));
    await save(tester);

    expect(popped, isNotNull);
    expect(popped!.numericExpr('borderRadius'), 'hp / 4');
    expect(popped!.id, 'v1', reason: 'слой остаётся собой');
  });

  testWidgets('снятая формула скругления уходит, чужие остаются', (
    tester,
  ) async {
    await openEditor(
      tester,
      _video(exprs: {'borderRadius': 'hp / 4', 'padding': 'gap'}),
    );

    final clearButton = find.byTooltip('Снять формулу');
    await reveal(tester, clearButton);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();
    await save(tester);

    expect(popped!.numericExpr('borderRadius'), isNull);
    // Не {'borderRadius': ''}: пустое значение движок читал бы как формулу.
    expect(popped!.numericExprs, isNot(contains('')));
    expect(popped!.numericExpr('padding'), 'gap');
    expect(popped!.borderRadius, 12, reason: 'число-фоллбэк на месте');
  });

  testWidgets('формула из пикера доезжает до айтема', (tester) async {
    // Широкое окно: на телефоне поле формул набирается палитрой, а тест
    // печатает в него.
    await openEditor(tester, _video(), surface: const Size(1400, 900));

    final formulaButton = find.byIcon(Icons.functions);
    await reveal(tester, formulaButton);
    await tester.tap(formulaButton);
    await tester.pumpAndSettle();
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
    await save(tester);

    expect(popped!.numericExpr('borderRadius'), 'hp / 4');
    expect(popped!.borderRadius, 12);
  });
}
