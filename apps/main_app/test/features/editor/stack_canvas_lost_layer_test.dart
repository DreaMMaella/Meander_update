// Слой, которого нет на холсте: нулевой размер либо целиком за краем.
// Такие слои невидимы и в редакторе, и в игре, а документ при этом целый —
// значит молча переписывать файл нельзя. Панель слоёв обязана показать
// находку и дать одну кнопку на лечение.

import 'package:canvas_app/features/editor/screens/node_content/stack_canvas/stack_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

/// Обычный слой: 100×40 у левого верхнего угла.
ContentItem _okChild() => ContentItem(
  id: 'ok',
  type: 'text',
  text: 'виден',
  anchorLeft: 0,
  anchorTop: 0,
  anchorRight: 0,
  anchorBottom: 0,
  offsetLeft: 16,
  offsetTop: 8,
  offsetRight: 116,
  offsetBottom: 48,
);

/// Нулевой размер: рамки нет, и кнопка в плеере не рисуется.
ContentItem _zeroChild() => ContentItem(
  id: 'gone',
  type: 'button',
  text: 'Идти',
  anchorLeft: 0,
  anchorTop: 0,
  anchorRight: 0,
  anchorBottom: 0,
  offsetLeft: 10,
  offsetTop: 10,
  offsetRight: 10,
  offsetBottom: 10,
);

/// Целиком за правым краем холста (720 px по умолчанию).
ContentItem _offCanvasChild() => ContentItem(
  id: 'far',
  type: 'text',
  text: 'далеко',
  anchorLeft: 0,
  anchorTop: 0,
  anchorRight: 0,
  anchorBottom: 0,
  offsetLeft: 5000,
  offsetTop: 8,
  offsetRight: 5100,
  offsetBottom: 48,
);

ContentItem _stackWith(List<ContentItem> children) =>
    ContentItem(id: 'stack-1', type: 'stack', children: children);

void main() {
  late List<ContentItem> saved;

  Future<void> pumpCanvas(
    WidgetTester tester,
    List<ContentItem> children,
  ) async {
    saved = [];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StackCanvasScreen(
            stackItem: _stackWith(children),
            questId: 'q-lost',
            nodeId: 'n-lost',
            onAutoSave: (payload) async {
              saved.add(payload['item']! as ContentItem);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // Иконка слоёв в панели — тоже layers, поэтому по подсказке кнопки.
    await tester.tap(
      find.byTooltip(
        'Панель слоёв: z-порядок (долгое нажатие на строку), '
        'видимость, замок, выбор',
      ),
    );
    await tester.pumpAndSettle();
  }

  ContentItem savedChild(WidgetTester tester, String id) =>
      saved.last.children!.firstWhere((child) => child.id == id);

  testWidgets('нулевой слой помечен, а нормальный — нет', (tester) async {
    await pumpCanvas(tester, [_okChild(), _zeroChild()]);

    expect(find.byKey(const ValueKey('layer_lost_gone')), findsOneWidget);
    expect(find.byKey(const ValueKey('layer_lost_ok')), findsNothing);
    expect(find.textContaining('1 слой не видно'), findsOneWidget);
  });

  testWidgets('уехавший за край тоже находится', (tester) async {
    await pumpCanvas(tester, [_offCanvasChild()]);
    expect(find.byKey(const ValueKey('layer_lost_far')), findsOneWidget);
    expect(find.textContaining('1 слой не видно'), findsOneWidget);
  });

  testWidgets('висящий на границе холста — нормальная вёрстка, не поломка', (
    tester,
  ) async {
    await pumpCanvas(tester, [
      ContentItem(
        id: 'edge',
        type: 'text',
        text: 'у края',
        anchorLeft: 0,
        anchorTop: 0,
        anchorRight: 0,
        anchorBottom: 0,
        offsetLeft: 660,
        offsetTop: 8,
        offsetRight: 760,
        offsetBottom: 48,
      ),
    ]);
    expect(find.byKey(const ValueKey('layer_lost_edge')), findsNothing);
    expect(find.byKey(const ValueKey('layers_lost_hint')), findsNothing);
  });

  testWidgets('тап по значку возвращает слой в центр холста одним шагом', (
    tester,
  ) async {
    await pumpCanvas(tester, [_okChild(), _zeroChild()]);
    final before = saved.length;

    await tester.tap(find.byKey(const ValueKey('layer_lost_tap_gone')));
    await tester.pumpAndSettle();

    // Холст по умолчанию 720×220, дефолтный новый слой — 160×44 по центру.
    final fixed = savedChild(tester, 'gone');
    expect(
      fixed.stackChildRect(720, 220),
      const Rect.fromLTRB(280, 88, 440, 132),
    );
    // Якоря лечение не трогает — иначе «прижат к краю» стал бы свободным.
    expect(fixed.anchorLeft, 0);
    expect(fixed.anchorBottom, 0);
    // Соседний слой и текст кнопки целы.
    expect(
      savedChild(tester, 'ok').stackChildRect(720, 220),
      const Rect.fromLTRB(16, 8, 116, 48),
    );
    expect(fixed.text, 'Идти');
    // Одно правка — один шаг истории, не два.
    expect(saved.length, before + 1);
    expect(find.byKey(const ValueKey('layer_lost_gone')), findsNothing);
    expect(find.byKey(const ValueKey('layers_lost_hint')), findsNothing);
  });
}
