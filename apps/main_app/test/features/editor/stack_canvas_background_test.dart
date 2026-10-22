// Фон холста картинкой: режим укладки автор выбирает чипсами прямо в настройках
// стека, и выбор обязан доезжать до документа — иначе «мозаика» осталась бы
// декорацией интерфейса. Без фона лишних ручек не показываем, но сам вход
// («выбрать») остаётся.

import 'package:canvas_app/features/editor/screens/node_content/stack_canvas/stack_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

ContentItem _textChild() => ContentItem(
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
);

ContentItem _stack({String? backgroundPath, String fit = 'cover'}) =>
    ContentItem(
      id: 'stack-1',
      type: 'stack',
      stackHeight: 240,
      stackBackgroundPath: backgroundPath,
      stackBackgroundFit: fit,
      children: [_textChild()],
    );

void main() {
  late List<ContentItem> saved;

  Future<void> pumpCanvas(WidgetTester tester, ContentItem stack) async {
    saved = [];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StackCanvasScreen(
            stackItem: stack,
            questId: 'q-bg',
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
    await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
    await tester.pumpAndSettle();
  }

  Finder chip(String fit) => find.byKey(ValueKey('stack_background_fit_$fit'));

  testWidgets('чипс режима пишет fit в документ, картинку не трогает', (
    tester,
  ) async {
    await pumpCanvas(tester, _stack(backgroundPath: 'res/images/sunset.png'));
    await openStackSheet(tester);

    expect(chip('cover'), findsOneWidget);
    expect(chip('tile'), findsOneWidget);

    await tester.ensureVisible(chip('contain'));
    await tester.pumpAndSettle();
    await tester.tap(chip('contain'));
    await tester.pumpAndSettle();

    final written = saved.last;
    expect(written.stackBackgroundFit, 'contain');
    // Режим — надстройка над путём, а не замена.
    expect(written.stackBackgroundPath, 'res/images/sunset.png');
  });

  testWidgets('мозаика из документа показана выбранной', (tester) async {
    await pumpCanvas(
      tester,
      _stack(backgroundPath: 'res/images/tile.png', fit: 'tile'),
    );
    await openStackSheet(tester);

    expect(tester.widget<ChoiceChip>(chip('tile')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(chip('cover')).selected, isFalse);
  });

  testWidgets('без фона чипсов режима нет, кнопка выбора есть', (tester) async {
    await pumpCanvas(tester, _stack());
    await openStackSheet(tester);

    expect(chip('tile'), findsNothing);
    expect(find.byKey(const ValueKey('stack_background_pick')), findsOneWidget);
  });

  testWidgets('«убрать» снимает и путь, и режим', (tester) async {
    await pumpCanvas(
      tester,
      _stack(backgroundPath: 'res/images/tile.png', fit: 'contain'),
    );
    await openStackSheet(tester);

    await tester.ensureVisible(find.text('убрать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('убрать'));
    await tester.pumpAndSettle();

    final written = saved.last;
    expect(written.stackBackgroundPath, isNull);
    expect(written.stackBackgroundFit, 'cover');
  });
}
