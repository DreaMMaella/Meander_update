// Регрессия #328: перенос блока в любое место скрипта и обратно.
//
// Экран удаляет блок из дерева в момент drop (`_handleBlockDrop` ->
// removeBlockFromTree), а до общего обхода `nestedBlockLists` этот обход знал
// только про событие и условие. Блок, вытащенный из цикла, оставался в цикле
// копией: «переместить куда надо» превращалось в «появилось дубли».
import 'package:canvas_app/features/editor/screens/visual_script_editor/block_factory.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/widgets/event_block_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Долгое нажатие на источник и отпускание в точку [to] — тот же жест, что
/// делает палец в редакторе (LongPressDraggable с delay 150 мс).
Future<void> dragBlock(WidgetTester tester, Finder source, Offset to) async {
  final from = tester.getRect(source).center;
  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 250));
  for (int i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
    await tester.pump(const Duration(milliseconds: 30));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<EventBlock> pumpEvent(WidgetTester tester, EventBlock script) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              child: SingleChildScrollView(
                // Как экран: drop в чужой список вычёркивает блок из дерева.
                child: EventBlockWidget(
                  block: script,
                  questId: 'q1',
                  onBlockDrop: (dropped, _) =>
                      removeBlockFromTree(dropped.id, [script]),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return script;
}

List<Type> types(Iterable<VisualScriptBlock> blocks) =>
    blocks.map((b) => b.runtimeType).toList();

void main() {
  group('обход дерева блоков', () {
    test('видит детей цикла, for-each и кроссфейда', () {
      final inner = DelayBlock();
      final whileLoop = WhileBlock(count: '3', children: [inner]);
      final forEach = ForEachBlock(
        tableName: 'лавка',
        children: [SetVolumeBlock()],
      );
      final crossfade = CrossfadeBlock(children: [GoToNodeBlock()]);
      final tree = <VisualScriptBlock>[whileLoop, forEach, crossfade];

      expect(locateBlockInTree(inner.id, tree)?.index, 0);
      expect(locateBlockInTree(inner.id, tree)?.list, same(whileLoop.children));
      expect(
        locateBlockInTree(forEach.children.first.id, tree)?.list,
        same(forEach.children),
      );
      expect(
        locateBlockInTree(crossfade.children.first.id, tree)?.list,
        same(crossfade.children),
      );
      expect(locateBlockInTree('нет-такого', tree), isNull);
    });

    test('удаление из дерева вычеркивает блок из вложенного цикла', () {
      final inner = DelayBlock();
      final tree = <VisualScriptBlock>[
        WhileBlock(count: '2', children: [inner]),
      ];
      expect(removeBlockFromTree(inner.id, tree), isTrue);
      expect(tree.first, isA<WhileBlock>());
      expect((tree.first as WhileBlock).children, isEmpty);
      expect(removeBlockFromTree(inner.id, tree), isFalse);
    });
  });

  group('перетаскивание в живом скрипте', () {
    testWidgets('блок уходит из цикла наружу и не оставляёт копию', (
      tester,
    ) async {
      final loop = WhileBlock(count: '3', children: [GoToNodeBlock()]);
      final script = await pumpEvent(
        tester,
        EventBlock(
          eventType: EventType.onNodeEnter,
          children: [loop, DelayBlock()],
        ),
      );
      final cards = find.byType(BlockFactory);
      expect(cards, findsNWidgets(3));
      final movedId = loop.children.single.id;

      final inside = tester.getRect(cards.at(1));
      final after = tester.getRect(cards.at(2));
      await dragBlock(
        tester,
        cards.at(1),
        Offset(inside.center.dx, after.bottom + 6),
      );

      expect(loop.children, isEmpty, reason: 'цикл обязан отдать блок');
      expect(types(script.children), [WhileBlock, DelayBlock, GoToNodeBlock]);
      // Тот же блок, а не клон: перенос сохраняет id.
      expect(script.children.last.id, movedId);
    });

    testWidgets('блок переезжает на одну позицию вниз', (tester) async {
      final script = await pumpEvent(
        tester,
        EventBlock(
          eventType: EventType.onNodeEnter,
          children: [DelayBlock(), GoToNodeBlock(), SetVolumeBlock()],
        ),
      );
      final cards = find.byType(BlockFactory);
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      await dragBlock(
        tester,
        cards.at(0),
        Offset(first.center.dx, second.bottom + 6),
      );
      expect(types(script.children), [
        GoToNodeBlock,
        DelayBlock,
        SetVolumeBlock,
      ]);
      expect(script.children.length, 3, reason: 'без дублей');
    });

    testWidgets('зона вставки — весь зазор между карточками', (tester) async {
      await pumpEvent(
        tester,
        EventBlock(
          eventType: EventType.onNodeEnter,
          children: [DelayBlock(), GoToNodeBlock()],
        ),
      );
      final cards = find.byType(BlockFactory);
      final slot = find.byType(DragTarget<VisualScriptBlock>).last;
      final slotRect = tester.getRect(slot);
      final firstRect = tester.getRect(cards.at(0));
      final secondRect = tester.getRect(cards.at(1));

      // Широкая полоса: попадание по любой точке зазора, а не по 10 px в
      // центре. Узкая полоса и есть «не могу положить куда хочу».
      expect(slotRect.width, firstRect.width);
      expect(slotRect.height, greaterThanOrEqualTo(12));
      // #327: зазор между карточками не разъезжается — стоят плотно.
      expect(secondRect.top - firstRect.bottom, lessThanOrEqualTo(16));
    });
  });
}
