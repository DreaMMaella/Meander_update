import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/widgets/node_transition_switcher.dart';

void main() {
  Widget wrap(String mode, String id, String tag) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: NodeTransitionSwitcher(
            mode: mode,
            presentationId: id,
            child: ColoredBox(
              key: ValueKey('scene_$id'),
              color: const Color(0xFF223344),
              child: Center(child: Text(tag)),
            ),
          ),
        ),
      ),
    );
  }

  test('resolveNodeTransitionMode: канон + псевдонимы', () {
    expect(resolveNodeTransitionMode('fade'), 'fade');
    expect(resolveNodeTransitionMode('default'), 'fade');
    expect(resolveNodeTransitionMode('page'), 'page');
    expect(resolveNodeTransitionMode('dark'), 'dark');
    expect(resolveNodeTransitionMode('fadetoblack'), 'dark');
    expect(resolveNodeTransitionMode('slide'), 'slide');
    expect(resolveNodeTransitionMode('slide_up'), 'slideUp');
    expect(resolveNodeTransitionMode('zoom'), 'zoom');
    expect(resolveNodeTransitionMode('scale'), 'zoom');
    expect(resolveNodeTransitionMode('blur'), 'blur');
    expect(resolveNodeTransitionMode('wipe'), 'wipe');
    expect(resolveNodeTransitionMode('curtain'), 'wipe');
    expect(resolveNodeTransitionMode('fold'), 'flip');
    expect(resolveNodeTransitionMode(''), 'none');
    expect(resolveNodeTransitionMode('garbage'), 'none');
    expect(resolveNodeTransitionMode(null), 'none');
  });

  for (final mode in ['slide', 'slideUp', 'zoom', 'blur', 'wipe', 'dark']) {
    testWidgets('$mode: смена ноды проходит до финала', (tester) async {
      await tester.pumpWidget(wrap(mode, 'a', 'Нода А'));
      expect(find.text('Нода А'), findsOneWidget);

      await tester.pumpWidget(wrap(mode, 'b', 'Нода Б'));
      await tester.pump();
      // Во время анимации без падений (для dark новая нода появляется в
      // дереве только на середине, на старте её ещё нет — не проверяем).

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Нода Б'), findsOneWidget);
      expect(find.text('Нода А'), findsNothing);
    });
  }

  testWidgets('preview: смена режима автоматически проигрывает эффект', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NodeTransitionPreview(mode: 'none')),
      ),
    );
    expect(find.text('Нода А'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // Смена режима — пост-фрейм проигрывает переход автоматически.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NodeTransitionPreview(mode: 'slide')),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Нода Б'), findsOneWidget);

    // Кнопка ▶ проигрывает ещё раз (А ← → Б).
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Нода А'), findsOneWidget);
  });
}
