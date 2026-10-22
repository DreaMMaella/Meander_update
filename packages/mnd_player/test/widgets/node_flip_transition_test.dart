import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/widgets/node_flip_transition.dart';

void main() {
  Widget wrap({
    required String id,
    required String tag,
    required ScrollController controller,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: NodeFlipTransition(
            presentationId: id,
            background: Container(color: const Color(0xFF1a1a2e)),
            child: KeyedSubtree(
              key: ValueKey('node_$id'),
              child: ListView.builder(
                controller: controller,
                itemCount: 5,
                itemBuilder: (_, i) => Text('$tag-$i'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // toImage — реальный async движка: даём ему завершиться через runAsync,
  // пока уходящая нода ещё в дереве (предзахват).
  Future<void> waitForCapture(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.text('A-0').evaluate().isEmpty) return;
    }
  }

  testWidgets('flip: захват сцены, переворот завершается новой нодой', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(id: 'a', tag: 'A', controller: controller));
    expect(find.text('A-0'), findsOneWidget);
    expect(find.text('B-0'), findsNothing);

    // Смена ноды — предзахват: уходящая сцена (фон + контент) поверх входящей.
    await tester.pumpWidget(wrap(id: 'b', tag: 'B', controller: controller));
    await tester.pump();

    // B на месте; A либо ещё в предзахвате, либо уже захвачен в картинку —
    // главное, что два ListView на одном контроллере не уронили фреймворк.
    expect(find.text('B-0'), findsOneWidget);

    // Захват завершился — уходящая нода выгружена, фолд играет из картинки.
    await waitForCapture(tester);
    expect(find.text('A-0'), findsNothing);
    expect(find.text('B-0'), findsOneWidget);

    // Дожимаем анимацию до конца.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('B-0'), findsOneWidget);

    // После переворота контроллер снова один (уходящая нода выгружена).
    expect(controller.positions.length, 1);
    expect(controller.hasClients, isTrue);
  });

  testWidgets('flip: без смены ноды переход не запускается', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(id: 'a', tag: 'A', controller: controller));
    // Та же нода, другой тег контента (live-reload той же ноды) — без перехода.
    await tester.pumpWidget(wrap(id: 'a', tag: 'A2', controller: controller));
    await tester.pump();
    expect(find.text('A2-0'), findsOneWidget);
    expect(find.text('A-0'), findsNothing);
  });
}
