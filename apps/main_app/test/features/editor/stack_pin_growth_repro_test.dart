// Воспроизведение «стек начнёт вечно расширяться» на стороне РЕДАКТОРА.
//
// Тот же документ, что принёс владелец: холст 720×220, stackPin custom, якоря
// рамки 0..1 по обеим осям (обе галки «Растянуть» включены), три картинки-слоя
// с якорями 0 и дробными offset'ами. Шит «Стек · холст и фон» при таком
// документе показывает рамку на всю высоту окна — у владельца В 761.
//
// Тест ничего не чинит. Он гоняет редактор по кругу и печатает цифры:
//   1) открыть/закрыть шит ×6          — док не должен меняться;
//   2) галки «Растянуть» ×6 по осям    — рамка не должна расползаться;
//   3) поле «Высота холста» = 761 ×10  — экранные px в поля холста;
//   4) драг нижней ручки холста        — сколько px холста на 1 px пальца;
//   5) драг без движения пальца        — рост сам по себе, без жеста.
//
// Размеры читаются из полей самого шита («Ширина/Высота холста» — документные
// stackWidth/stackHeight, pin_w/pin_h — рамка) и из плашки canvas_size_badge,
// которая живёт только во время тяги.

import 'package:canvas_app/features/editor/screens/node_content/stack_canvas/stack_canvas_screen.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final Map<String, Object?> _stackJson = {
  'type': 'stack',
  'id': '9de15891-db1f-4d94-bfb1-f088395c556b',
  'borderRadius': 0.0,
  'stackHeight': 220.0,
  'stackPin': 'custom',
  'pinAnchorLeft': 0.0,
  'pinAnchorTop': 0.0,
  'pinAnchorRight': 1.0,
  'pinAnchorBottom': 1.0,
  'pinOffsetLeft': 0.0,
  'pinOffsetTop': 0.0,
  'pinOffsetRight': 0.0,
  'pinOffsetBottom': 0.0,
  'flex': 1,
  'crossAxisAlignment': 'center',
  'rowTextAlignment': 'center',
  'textFit': 'auto',
  'wrapText': true,
  'animateIn': true,
  'children': [
    _childJson('c1', 163.26, 208.94),
    _childJson('c2', 208.94, 254.63),
    _childJson('c3', 254.63, 300.31),
  ],
};

Map<String, Object?> _childJson(String id, double left, double right) => {
  'type': 'image',
  'id': id,
  'resourcePath': 'res/images/18f5630e-4052-43d0-829b-2be328219a4a.png',
  'flex': 1,
  'anchorLeft': 0.0,
  'anchorTop': 0.0,
  'anchorRight': 0.0,
  'anchorBottom': 0.0,
  'offsetLeft': left,
  'offsetRight': right,
  'offsetTop': 88.0,
  'offsetBottom': 132.0,
};

ContentItem buildStack() =>
    ContentItem.fromJson(Map<String, dynamic>.from(_stackJson));

void main() {
  late List<ContentItem> saved;

  /// Вьюпорт владельца: окно редактора 720×761 — в нём шит и показывает В 761.
  void useOwnerWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 761);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpCanvas(WidgetTester tester, ContentItem stack) async {
    saved = [];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StackCanvasScreen(
            stackItem: stack,
            questId: 'q-test',
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

  String pinField(WidgetTester tester, String key) => tester
      .widget<TextField>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(TextField),
            )
            .first,
      )
      .controller!
      .text;

  /// Поле шита по подписи (`InputDecoration.labelText`).
  String fieldByLabel(WidgetTester tester, String label) => tester
      .widget<TextField>(find.widgetWithText(TextField, label).first)
      .controller!
      .text;

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Холст и фон стека'));
    await tester.pumpAndSettle();
    // Шит — модальный bottom sheet: содержимое ниже сгиба подводим скроллом,
    // иначе тапы по галкам растяжения просто не долетают до виджета.
    for (final label in ['Растянуть по высоте', 'Растянуть по ширине']) {
      if (find.text(label).evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text(label).first);
        await tester.pumpAndSettle();
      }
    }
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(360, 4));
    await tester.pumpAndSettle();
  }

  /// Снимок того, что редактор считает текущими размерами.
  String probe(WidgetTester tester) =>
      'холст ${fieldByLabel(tester, 'Ширина холста')}×'
      '${fieldByLabel(tester, 'Высота холста')} | '
      'рамка ${pinField(tester, 'pin_w')}×${pinField(tester, 'pin_h')} | '
      'док stackWidth=${saved.isEmpty ? "-" : saved.last.stackWidth} '
      'stackHeight=${saved.isEmpty ? "-" : saved.last.stackHeight} | '
      'saves=${saved.length}';

  String badge(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => RegExp(r'^\d+ × \d+ px$').hasMatch(s))
      .join(',');

  testWidgets('редактор: шит открываем/закрываем 6 раз — холст и рамка', (
    tester,
  ) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    for (var i = 0; i < 6; i++) {
      await openSheet(tester);
      // ignore: avoid_print
      print('цикл $i: ${probe(tester)}');
      await closeSheet(tester);
    }
  });

  testWidgets('редактор: галки растяжения по высоте и ширине', (
    tester,
  ) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    await openSheet(tester);
    // ignore: avoid_print
    print('до всего: ${probe(tester)}');
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('Растянуть по высоте').first);
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('высота галка $i: ${probe(tester)}');
    }
    for (var i = 0; i < 6; i++) {
      await tester.ensureVisible(find.text('Растянуть по ширине').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Растянуть по ширине').first);
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('ширина галка $i: ${probe(tester)}');
    }
    await closeSheet(tester);
  });

  testWidgets('редактор: «Высота холста» = экранное 761 десять раз', (
    tester,
  ) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    await openSheet(tester);
    final heightCtl = find.widgetWithText(TextField, 'Высота холста').first;
    for (var i = 0; i < 10; i++) {
      await tester.enterText(heightCtl, '761');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('ввод 761, шаг $i: ${probe(tester)}');
    }
  });

  testWidgets('редактор: драг нижней ручки — сколько px холста на 1 px пальца',
      (tester) async {
        useOwnerWindow(tester);
        await pumpCanvas(tester, buildStack());
        final handle = find.byKey(const ValueKey('canvas_edge_handle'));
        expect(handle, findsOneWidget);
        final gesture = await tester.startGesture(tester.getCenter(handle));
        for (var i = 0; i < 30; i++) {
          await gesture.moveBy(const Offset(0, 10));
          await tester.pump();
          if (i % 3 == 2 || i < 3) {
            // ignore: avoid_print
            print('палец +${(i + 1) * 10} px → ${badge(tester)}');
          }
        }
        await gesture.up();
        await tester.pump();
        final doc = saved.isEmpty ? buildStack() : saved.last;
        // ignore: avoid_print
        print(
          'после отпускания: saves=${saved.length}, док '
          '${doc.stackCanvasWidth.toStringAsFixed(0)}×'
          '${doc.stackCanvasHeight.toStringAsFixed(0)}',
        );
      });

  testWidgets('редактор: несколько коротких драгов подряд (погоня за ручкой)', (
    tester,
  ) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    for (var round = 0; round < 6; round++) {
      final handle = find.byKey(const ValueKey('canvas_edge_handle'));
      final start = tester.getCenter(handle);
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
      }
      final during = badge(tester);
      await gesture.up();
      await tester.pump();
      // ignore: avoid_print
      print(
        'драг $round: палец +30 px от y=${start.dy.toStringAsFixed(0)} → '
        '$during, ручка теперь y='
        '${tester.getCenter(handle).dy.toStringAsFixed(0)}, '
        'saves=${saved.length}',
      );
    }
  });

  testWidgets('редактор: held-жест без движения пальца — рост сам', (
    tester,
  ) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    final handle = find.byKey(const ValueKey('canvas_edge_handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    // ignore: avoid_print
    print('один шаг пальца: ${badge(tester)}');
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset.zero);
      await tester.pump();
    }
    // ignore: avoid_print
    print('10 кадров без движения: ${badge(tester)}');
    await gesture.up();
    await tester.pump();
  });
}
