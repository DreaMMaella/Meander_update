// Числовые поля у ползунков слоя: прозрачность, поворот и масштаб нужно уметь
// ставить тапом по цифре, а не только попадать пальцем по линейке. Поле
// клампится к тем же границам и с тем же шагом, что ползунок, нетронутое поле
// не пишет шаг истории, а движение ползунка обновляет поле.

import 'package:canvas_app/features/editor/screens/node_content/stack_canvas/stack_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

ContentItem _textChild({
  double opacity = 1.0,
  double rotation = 0.0,
  double scale = 1.0,
  double? textSize,
}) => ContentItem(
  id: 'txt',
  type: 'text',
  text: 'привет',
  opacity: opacity,
  rotation: rotation,
  scale: scale,
  textSize: textSize,
  anchorLeft: 0,
  anchorTop: 0,
  anchorRight: 0,
  anchorBottom: 0,
  offsetLeft: 16,
  offsetTop: 8,
  offsetRight: 116,
  offsetBottom: 48,
);

ContentItem _stack(ContentItem child) => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [child],
);

PhysicalKeyboardKey? physOf(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.controlLeft) {
    return PhysicalKeyboardKey.controlLeft;
  }
  return null;
}

void main() {
  late List<ContentItem> saved;

  Future<void> pumpCanvas(WidgetTester tester, ContentItem child) async {
    saved = [];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StackCanvasScreen(
            stackItem: _stack(child),
            questId: 'q-style',
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

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    final ctrl = LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(ctrl, physicalKey: physOf(ctrl));
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(ctrl, physicalKey: physOf(ctrl));
    await tester.pump();
  }

  Future<void> openPropsSheet(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.keyA);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
  }

  /// Поле у ползунка: подпись живёт внутри InputDecorator того же TextField.
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  Future<void> type(WidgetTester tester, String label, String value) async {
    await tester.enterText(field(label), value);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  ContentItem savedChild(WidgetTester tester) => saved.last.children!.single;

  testWidgets('у ползунков есть поля с текущими значениями', (tester) async {
    await pumpCanvas(
      tester,
      _textChild(opacity: 0.4, rotation: 15, scale: 1.5),
    );
    await openPropsSheet(tester);

    expect(fieldText(tester, 'Прозрачность, %'), '40');
    expect(fieldText(tester, 'Поворот, °'), '15');
    expect(fieldText(tester, 'Масштаб, %'), '150');
    // Без размера шрифта в документе показываем то, чем реально рисуем.
    expect(fieldText(tester, 'Размер, px'), '16');
  });

  testWidgets('ввод числа пишет слой в документ', (tester) async {
    await pumpCanvas(tester, _textChild());
    await openPropsSheet(tester);
    await type(tester, 'Прозрачность, %', '37');

    expect(savedChild(tester).opacity, closeTo(0.37, 1e-9));
  });

  testWidgets('за границы клампит, а в поле остаётся фактическое значение', (
    tester,
  ) async {
    // Слой берём полупрозрачным: кламп к 100 % обязан быть видимой правкой,
    // иначе тест прошёл бы и на пустом документе.
    await pumpCanvas(tester, _textChild(opacity: 0.5));
    await openPropsSheet(tester);

    await type(tester, 'Прозрачность, %', '150');
    expect(savedChild(tester).opacity, 1.0);
    expect(fieldText(tester, 'Прозрачность, %'), '100');

    await type(tester, 'Поворот, °', '-200');
    expect(savedChild(tester).rotation, -180.0);
    expect(fieldText(tester, 'Поворот, °'), '-180');

    // Верхнюю границу масштаба не клампит к 100 %: слой увеличивают и до 400.
    await type(tester, 'Масштаб, %', '900');
    expect(savedChild(tester).scale, 4.0);
    expect(fieldText(tester, 'Масштаб, %'), '400');

    await type(tester, 'Масштаб, %', '5');
    expect(savedChild(tester).scale, 0.1);
    expect(fieldText(tester, 'Масштаб, %'), '10');
  });

  testWidgets('масштаб слоя уходит в документ', (tester) async {
    await pumpCanvas(tester, _textChild());
    await openPropsSheet(tester);
    await type(tester, 'Масштаб, %', '180');

    expect(savedChild(tester).scale, closeTo(1.8, 1e-9));
    expect(savedChild(tester).rotation, 0.0, reason: 'поворот не при чём');
  });

  testWidgets('нетронутое поле не плодит шаг истории', (tester) async {
    await pumpCanvas(tester, _textChild(opacity: 0.5, rotation: 20));
    await openPropsSheet(tester);

    await type(tester, 'Прозрачность, %', '50');
    await type(tester, 'Поворот, °', '20');
    expect(saved, isEmpty);
  });

  testWidgets('движение ползунка обновляет поле', (tester) async {
    await pumpCanvas(tester, _textChild());
    await openPropsSheet(tester);

    final slider = find.byType(Slider).first;
    // Шит свойств прокручиваем: под сеткой якорей ползунок не гарантированно
    // попадает в вьюпорт теста.
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(-100, 0));
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'Прозрачность, %'), isNot('100'));
    expect(savedChild(tester).opacity, lessThan(1.0));
  });
}
