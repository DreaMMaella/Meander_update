// Триггерные слоты дочерних объектов стека: виджет общий с карточкой элемента
// в ноде, поэтому проверяем контракт напрямую — какой слот дёргается по какому
// тапу и когда показывается предупреждение «нажатие до движка не дойдёт».

import 'package:canvas_app/features/editor/widgets/trigger_slot_buttons.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem _item({
  String type = 'button',
  Map<String, String>? triggers,
  String? targetNodeId,
}) => ContentItem(id: 'i-1', type: type, scriptTriggers: triggers, targetNodeId: targetNodeId);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
}

void main() {
  testWidgets('пустые слоты: тап по глазку — onAppear, по пальцу — onPress', (
    tester,
  ) async {
    final tapped = <String>[];
    await _pump(
      tester,
      TriggerSlotButtons(item: _item(), onSlotTap: tapped.add),
    );

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.tap(find.byIcon(Icons.touch_app_outlined));
    expect(tapped, ['onAppear', 'onPress']);
  });

  testWidgets('у поля ввода слот нажатия — onSubmit', (tester) async {
    final tapped = <String>[];
    await _pump(
      tester,
      TriggerSlotButtons(
        item: _item(type: 'input'),
        onSlotTap: tapped.add,
        onSettings: () {},
      ),
    );

    expect(find.byIcon(Icons.input_rounded), findsOneWidget);
    expect(find.byIcon(Icons.touch_app_outlined), findsNothing);
    await tester.tap(find.byIcon(Icons.input_rounded));
    expect(tapped, ['onSubmit']);
  });

  testWidgets('занятый слот подсвечен, молния — «все триггеры»', (
    tester,
  ) async {
    await _pump(
      tester,
      TriggerSlotButtons(
        item: _item(triggers: const {'onAppear': 'scripts/a.json'}),
        onSettings: () {},
      ),
    );

    final eye = tester.widget<Icon>(find.byIcon(Icons.visibility_outlined));
    expect(eye.color, const Color(0xFFFFD54F));
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  // Разница между форматами: редактор показывал серый глазик, хотя плеер
  // скрипт выполнял — карточка читала только legacy `scriptTriggers`.
  testWidgets('слот занят через behaviours — глазок горит', (tester) async {
    final item = ContentItem(
      id: 'i-1',
      type: 'button',
      behaviours: const [
        ContentTrigger(event: 'onAppear', script: 'scripts/a.json'),
      ],
    );
    await _pump(
      tester,
      TriggerSlotButtons(item: item, onSettings: () {}),
    );

    final eye = tester.widget<Icon>(find.byIcon(Icons.visibility_outlined));
    expect(eye.color, const Color(0xFFFFD54F));
    expect(TriggerSlotButtons.hasSlot(item, 'onPress'), isFalse);
    expect(TriggerSlotButtons.hasAny(item), isTrue);
  });

  testWidgets('предупреждение рисуется только когда передан текст', (
    tester,
  ) async {
    await _pump(tester, TriggerSlotButtons(item: _item()));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    await _pump(
      tester,
      TriggerSlotButtons(
        item: _item(),
        warningTooltip: 'стек перехватывает нажатие',
      ),
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  group('stackChildPressWarning', () {
    const childWithPress = {'onPress': 'scripts/a.json'};

    test('стек без действия — ребёнок жив', () {
      expect(
        stackChildPressWarning(
          stack: _item(type: 'stack'),
          child: _item(triggers: childWithPress),
        ),
        isNull,
      );
    });

    test('стек со своим onPress глушит onPress ребёнка', () {
      expect(
        stackChildPressWarning(
          stack: _item(
            type: 'stack',
            triggers: const {'onPress': 'scripts/stack.json'},
          ),
          child: _item(triggers: childWithPress),
        ),
        isNotNull,
      );
    });

    test('переход к ноде у ребёнка тоже мёртв, если стек перехватил тап', () {
      expect(
        stackChildPressWarning(
          stack: _item(
            type: 'stack',
            triggers: const {'onPress': 'scripts/stack.json'},
          ),
          child: _item(targetNodeId: 'n-2'),
        ),
        isNotNull,
      );
    });

    test('onAppear ребёнка работает всегда — предупреждения нет', () {
      expect(
        stackChildPressWarning(
          stack: _item(
            type: 'stack',
            triggers: const {'onPress': 'scripts/stack.json'},
          ),
          child: _item(triggers: const {'onAppear': 'scripts/a.json'}),
        ),
        isNull,
      );
    });
  });
}
