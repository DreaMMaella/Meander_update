import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/widgets/delay_block_widget.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/widgets/event_block_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Карточка события с одним вложенным блоком «Ждать» внутри.
///
/// [eventCalls] собирает операции, пришедшие в меню САМОГО события — если они
/// появляются при тапе по вложенному блоку, значит операция над «одним блоком»
/// ушла в целое событие.
Future<void> _pumpEventWithOneChild(
  WidgetTester tester,
  EventBlock event,
  List<String> eventCalls,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                child: EventBlockWidget(
                  block: event,
                  questId: 'q1',
                  onBlockDrop: (_, _) {},
                  onMenuAction: (a) => eventCalls.add('EVENT:$a'),
                  onDelete: () => eventCalls.add('EVENT:delete'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('тап по вложенному блоку дублирует его, а не целое событие', (
    tester,
  ) async {
    final event = EventBlock(children: [DelayBlock(expression: '500')]);
    final eventCalls = <String>[];
    await _pumpEventWithOneChild(tester, event, eventCalls);

    await tester.tap(find.text('Ждать').first);
    await tester.pumpAndSettle();
    expect(find.text('Дублировать блок'), findsOneWidget);

    await tester.tap(find.text('Дублировать блок'));
    await tester.pumpAndSettle();

    expect(event.children, hasLength(2));
    // Меню события не должно открываться вообще: операция касалась одного
    // блока внутри события, а не события целиком.
    expect(eventCalls, isEmpty);
  });

  testWidgets('шапка события называет операцию операцией над событием', (
    tester,
  ) async {
    final event = EventBlock(children: [DelayBlock(expression: '500')]);
    await _pumpEventWithOneChild(tester, event, <String>[]);

    await tester.tap(find.text('При входе в ноду').first);
    await tester.pumpAndSettle();

    expect(find.text('Дублировать событие'), findsOneWidget);
    expect(find.text('Удалить событие'), findsOneWidget);
    expect(find.text('Дублировать блок'), findsNothing);
  });

  testWidgets('тап по телу события не открывает меню всего события', (
    tester,
  ) async {
    final event = EventBlock(children: [DelayBlock(expression: '500')]);
    await _pumpEventWithOneChild(tester, event, <String>[]);

    // Мёртвая зона вложенной раскладки: полоса вставки/отступ над карточкой
    // блока. Раньше тап здесь доставал до жеста карточки-родителя и открывал
    // меню целого события.
    final childTop = tester.getRect(find.byType(DelayBlockWidget)).top;
    await tester.tapAt(Offset(350, childTop + 18));
    await tester.pumpAndSettle();

    expect(find.text('Дублировать событие'), findsNothing);
  });

  test('blockOperationToast называет контейнер и его содержимое', () {
    expect(
      blockOperationToast(ScriptBlockMenuAction.duplicate, EventBlock()),
      'Событие продублировано со всем содержимым',
    );
    expect(
      blockOperationToast(ScriptBlockMenuAction.copy, ConditionBlock()),
      'Условие скопировано со всем содержимым',
    );
    expect(
      blockOperationToast(ScriptBlockMenuAction.cut, ForEachBlock()),
      'Цикл вырезан со всем содержимым',
    );
    expect(
      blockOperationToast(
        ScriptBlockMenuAction.duplicate,
        DelayBlock(expression: '500'),
      ),
      'Блок продублирован',
    );
  });
}
