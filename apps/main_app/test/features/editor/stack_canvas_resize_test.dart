// Регрессия «создаю такой стек — он начинает вечно расширяться».
//
// Документ владельца: холст 720×220, `stackPin: custom`, якоря рамки 0..1 по
// обеим осям (обе галки «Растянуть» включены), три картинки-слоя. В его окне
// 720×761 холст вписан по ширине, поэтому тяга за нижний край удваивает
// пиксели пальца: холст центрирован, и прирост высоты достаётся обоим краям.
//
// Инвариант, который этот тест и сторожит: множители жеста (масштаб
// экран→мир и коэффициент «вдвое») снимаются ОДИН РАЗ на старте тяги.
// Пересчёт от живой высоты переворачивает флаг на середине жеста —
// накопленная дельта вдруг сбрасывается вдвое, и холст прыгает на сотни px
// туда-сюда; именно это выглядело как «расширяется сам».

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

  /// Окно владельца: 720×761 — в нём шит и показывает рамку «В 761».
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

  /// Высота холста из плашки, которая живёт только во время тяги.
  double badgeHeight(WidgetTester tester) {
    final text = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('canvas_size_badge')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    final match = RegExp(r'^\d+ × (\d+) px$').firstMatch(text);
    expect(match, isNotNull, reason: 'плашка размеров: $text');
    return double.parse(match!.group(1)!);
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

  String fieldByLabel(WidgetTester tester, String label) => tester
      .widget<TextField>(find.widgetWithText(TextField, label).first)
      .controller!
      .text;

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Холст и фон стека'));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(360, 4));
    await tester.pumpAndSettle();
  }

  /// Тяга нижнего края на [pixels] экранных px; возвращает высоты холста после
  /// каждого шага пальца.
  Future<List<double>> dragBottomEdge(
    WidgetTester tester,
    double pixels, {
    double step = 10,
  }) async {
    final handle = find.byKey(const ValueKey('canvas_edge_handle'));
    expect(handle, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    final heights = <double>[];
    for (var moved = 0.0; moved < pixels; moved += step) {
      await gesture.moveBy(Offset(0, step));
      await tester.pump();
      heights.add(badgeHeight(tester));
    }
    await gesture.up();
    await tester.pump();
    return heights;
  }

  testWidgets('тяга за нижний край растёт ровно за пальцем и не прыгает', (
    tester,
  ) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    // Холст 720 в окне 720 → масштаб 1 и «вписан по ширине» → коэффициент 2.
    final heights = await dragBottomEdge(tester, 300);
    expect(heights.first, closeTo(240, 1), reason: '$heights');
    for (var i = 1; i < heights.length; i++) {
      expect(
        heights[i],
        greaterThanOrEqualTo(heights[i - 1]),
        reason: 'шаг $i: холст сжался посреди тяги — $heights',
      );
    }
    expect(heights.last, closeTo(820, 1), reason: '$heights');
    expect(saved, hasLength(1));
    expect(saved.last.stackCanvasHeight, closeTo(820, 1));
  });

  testWidgets('повторные короткие тяги: шаг пальца даёт один и тот же прирост, '
      'холст не откатывается', (tester) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    // В окне 720×761 тело канваса 720 высотой, поэтому холст шириной 720
    // сидит на границе «вписан по ширине» при высоте 720. Доводим его
    // вплотную — дальше и рождается скачок.
    var previous = (await dragBottomEdge(tester, 240)).last;
    expect(previous, closeTo(700, 2));
    for (var round = 0; round < 6; round++) {
      final heights = await dragBottomEdge(tester, 30, step: 10);
      final steps = [
        heights.first - previous,
        for (var i = 1; i < heights.length; i++) heights[i] - heights[i - 1],
      ];
      // Флаг «вписан по ширине» и масштаб заморожены на старте жеста,
      // поэтому прирост на шаг одинаковый весь жест. Без заморозки ровно
      // здесь он переворачивается: последние шаги дают минус.
      for (final d in steps) {
        expect(
          d,
          closeTo(steps.first, 2),
          reason: 'раунд $round приросты $steps, высоты $heights',
        );
        expect(
          d,
          greaterThan(0),
          reason: 'раунд $round: тяга вниз сжала холст — $heights',
        );
      }
      previous = heights.last;
    }
    // Шесть тяг по 30 px пальца после границы: холст растёт, но не
    // explodes — максимум вдвое быстрее пальца.
    expect(previous, lessThanOrEqualTo(700 + 180 * 2 + 2));
    expect(previous, greaterThanOrEqualTo(700 + 180 - 2));
  });

  testWidgets('удержание ручки без движения пальца холст не растит', (
    tester,
  ) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    final handle = find.byKey(const ValueKey('canvas_edge_handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    final once = badgeHeight(tester);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset.zero);
      await tester.pump();
    }
    expect(badgeHeight(tester), once);
    await gesture.up();
    await tester.pump();
    expect(saved.last.stackCanvasHeight, closeTo(once, 1));
  });

  testWidgets('шит «холст и фон» 6 раз туда-сюда не трогает документ', (
    tester,
  ) async {
    useOwnerWindow(tester);
    await pumpCanvas(tester, buildStack());
    for (var i = 0; i < 6; i++) {
      await openSheet(tester);
      expect(fieldByLabel(tester, 'Ширина холста'), '720');
      expect(fieldByLabel(tester, 'Высота холста'), '220');
      expect(pinField(tester, 'pin_w'), '720');
      // Рамка при растянутой высоте = экран, а не холст: это и есть «В 761».
      expect(double.parse(pinField(tester, 'pin_h')), greaterThan(400));
      await closeSheet(tester);
    }
    expect(saved, isEmpty);
  });

  testWidgets('десятикратный ввод 761 в «Высота холста» не расползается', (
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
      expect(fieldByLabel(tester, 'Высота холста'), '761');
    }
    for (final item in saved) {
      expect(item.stackCanvasHeight, closeTo(761, 1));
    }
    expect(saved.length, lessThanOrEqualTo(2));
  });
}

/// Поле рамки отдаёт текст с округлением — сравниваем по числу.
Matcher closeToText(String value) => _CloseToParsed(value);

class _CloseToParsed extends Matcher {
  _CloseToParsed(this.expected);
  final String expected;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      (item as String).contains(expected);

  @override
  Description describe(Description description) =>
      description.add('contains $expected');
}
