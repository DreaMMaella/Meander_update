// Редактор: событие-функция должна быть опознываемой прямо в шапке блока.
//
// Скрипт, прикреплённый к ноде, движок запускает на «входе в ноду» и «показе
// контента». Событие-функция — исключение: оно живёт только на вызове извне.
// Подсказка в теле не спасает, когда блок свёрнут (а новые блоки часто и
// оставляют свёрнутыми), поэтому имя и метка вынесены в шапку.

import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/widgets/event_block_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<EventBlock> pumpEvent(
  WidgetTester tester, {
  required EventBlock block,
  double width = 900,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: EventBlockWidget(
                block: block,
                questId: 'q1',
                onBlockDrop: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return block;
}

void main() {
  testWidgets('событие-функция показывает имя в шапке', (tester) async {
    await pumpEvent(
      tester,
      block: EventBlock(
        eventType: EventType.function,
        functionName: 'openDoor',
      ),
    );

    // Одна копия имени в шапке, вторая — в поле «Функция».
    expect(find.text('openDoor'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('имя видно и в свёрнутом блоке', (tester) async {
    await pumpEvent(
      tester,
      block: EventBlock(
        eventType: EventType.function,
        functionName: 'openDoor',
      ),
    );

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();

    expect(find.text('openDoor'), findsOneWidget);
    // Тело со старой подсказкой скрыто — метка из шапки остаётся единственной.
    expect(find.textContaining('Запускается только по вызову'), findsNothing);
  });

  testWidgets('обычное событие чипа не получает', (tester) async {
    await pumpEvent(
      tester,
      block: EventBlock(eventType: EventType.onNodeEnter),
    );

    expect(find.text('openDoor'), findsNothing);
    expect(find.byIcon(Icons.call_missed_outgoing_rounded), findsNothing);
  });

  testWidgets('на узком экране чип не устраивает переполнение', (tester) async {
    await pumpEvent(
      tester,
      width: 320,
      block: EventBlock(
        eventType: EventType.function,
        functionName: 'veryLongFunctionNameThatWillNotFit',
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.call_missed_outgoing_rounded), findsOneWidget);
  });
}
