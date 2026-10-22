// Канвас-редактор стека: горячие клавиши, модификаторы перетаскивания,
// панель выравнивания, рамка выделения и то, что автосейв дёргается только
// на реальную правку.
// Точки жестов берём из реального layout'а (масштаб 1.111 и сдвиг по y —
// следствие того, как стек вписался в тестовые 800×600): проверяется тот же
// путь камера → FittedBox → координаты стека, по которому идёт палец.

import 'package:canvas_app/features/editor/logic/stack_canvas_ops.dart';
import 'package:canvas_app/features/editor/screens/node_content/stack_canvas/stack_canvas_screen.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem _child(String id, {double left = 16, double top = 8}) =>
    ContentItem(
      id: id,
      type: 'text',
      text: id,
      anchorLeft: 0,
      anchorTop: 0,
      anchorRight: 0,
      anchorBottom: 0,
      offsetLeft: left,
      offsetTop: top,
      offsetRight: left + 100,
      offsetBottom: top + 40,
    );

ContentItem _stack({double stackHeight = 240}) => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: stackHeight,
  children: [_child('a'), _child('b')],
);

ContentItem _stackSpread() => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [
    _child('a'),
    _child('b', left: 200, top: 60),
    _child('c', left: 340, top: 120),
  ],
);

/// a — с оформлением, b — голый: донор и получатель стиля лежат в знакомых
/// точках (центры на экране (73, 226) и (278, 284)).
ContentItem _stackStyled() => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [
    _child('a').copyWith(
      backgroundColor: const Color(0xFF123456),
      borderRadius: 12,
      opacity: 0.5,
    ),
    _child('b', left: 200, top: 60),
  ],
);

/// Один слой-картинка: у неё обводки быть не может, проверять будем отсутствием.
ContentItem _stackImage() => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [
    ContentItem(
      id: 'img',
      type: 'image',
      resourcePath: 'res/images/old.png',
      anchorLeft: 0,
      anchorTop: 0,
      anchorRight: 0,
      anchorBottom: 0,
      offsetLeft: 16,
      offsetTop: 8,
      offsetRight: 116,
      offsetBottom: 48,
    ),
  ],
);

/// Тот же расклад, что и [_stackSpread], но a и b уже в группе: геометрия
/// знакомая, поэтому точки тапов берутся из существующих тестов.
ContentItem _stackGrouped() => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [
    _child('a').copyWith(groupName: 'Группа 1'),
    _child('b', left: 200, top: 60).copyWith(groupName: 'Группа 1'),
    _child('c', left: 340, top: 120),
  ],
);

/// Один ребёнок — чтобы получить одиночное выделение без тапа по канвасу
/// (полоска свойств появляется только на одном выбранном объекте).
ContentItem _stackSingle() => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [_child('a')],
);

/// Тот же одиночный слой 100×40, но повёрнутый: картинка встаёт на бок, и
/// часть модельного rect'а остаётся пустой.
ContentItem _stackRotated([double rotation = 90]) => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [_child('a').copyWith(rotation: rotation)],
);

/// Слой целиком правее холста (720 px): в обычном режиме его не видно.
ContentItem _stackOutside() => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [_child('x', left: 760, top: 20)],
);

/// Слой, придвинутый к углу холста — туда, где лежит полоса линейки.
ContentItem _stackAtEdge({double left = 0, double top = 0}) => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [_child('a', left: left, top: top)],
);

/// Экранные точки сравниваем с допуском: layout отдаёт дробные пиксели.
Matcher nearOffset(Offset to, [double eps = 0.6]) => predicate<Offset>(
  (o) => (o - to).distance <= eps,
  'Offset ≈ ($to) ±$eps',
);

// HardwareKeyboard считает модификаторы по physical-коду, поэтому в тестах
// их передаём явно — иначе isControlPressed не поднимется.
PhysicalKeyboardKey? physOf(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.controlLeft) {
    return PhysicalKeyboardKey.controlLeft;
  }
  if (key == LogicalKeyboardKey.shiftLeft) return PhysicalKeyboardKey.shiftLeft;
  if (key == LogicalKeyboardKey.altLeft) return PhysicalKeyboardKey.altLeft;
  return null;
}

/// Значение поля геометрии в строке статуса выделенного слоя (x/y/w/h).
String ribbonField(WidgetTester tester, String part) => tester
    .widget<TextField>(find.byKey(ValueKey('rect_field_$part')))
    .controller!.text;

void main() {
  late List<ContentItem> saved;

  Future<void> pumpCanvas(WidgetTester tester, {ContentItem? stack}) async {
    saved = [];
    await tester.pumpWidget(
      // ProviderScope нужен: экран берёт из него имена ресурсов для подписей
      // слоёв. Без metadata квеста остаются имена файлов — на жесты это не
      // влияет.
      ProviderScope(
        child: MaterialApp(
          home: StackCanvasScreen(
            stackItem: stack ?? _stack(),
            questId: 'q-test',
            nodeId: 'n-test',
            // Время стоит: склейка серии стрелок в один шаг истории не должна
            // зависеть от того, успела ли машина уложиться в 700 мс между
            // двумя synthetic-событиями.
            sessionClock: () => DateTime(2026, 9, 20, 12),
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

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
    LogicalKeyboardKey? modifier2,
  }) async {
    final mods = [modifier, modifier2].nonNulls;
    for (final m in mods) {
      await tester.sendKeyDownEvent(m, physicalKey: physOf(m));
    }
    await tester.sendKeyEvent(key);
    for (final m in mods) {
      await tester.sendKeyUpEvent(m, physicalKey: physOf(m));
    }
    // Клавиатурное событие только помечает виджет грязным — перерисовку
    // ждём отдельным кадром, иначе find'еры видят старый статус-бар.
    await tester.pump();
  }

  Future<void> selectAll(WidgetTester tester) => press(
    tester,
    LogicalKeyboardKey.keyA,
    modifier: LogicalKeyboardKey.controlLeft,
  );

  Future<void> undo(WidgetTester tester) => press(
    tester,
    LogicalKeyboardKey.keyZ,
    modifier: LogicalKeyboardKey.controlLeft,
  );

  /// Закрыть шит тапом по затемняющему барьеру выше него: пока модальный
  /// route жив, фокус у него и Ctrl+Z до канваса не доходит.
  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(400, 10));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
  }

  IconButton? buttonOf(WidgetTester tester, IconData icon) {
    final buttons = tester.widgetList<IconButton>(
      find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
    );
    return buttons.isEmpty ? null : buttons.first;
  }

  IconButton? undoButton(WidgetTester tester) =>
      buttonOf(tester, Icons.undo_rounded);
  IconButton? redoButton(WidgetTester tester) =>
      buttonOf(tester, Icons.redo_rounded);

  /// Строка панели слоёв по подписи объекта.
  Finder layerTile(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(ListTile));

  Future<void> tapLayer(WidgetTester tester, String label, String tooltip) =>
      tester.tap(
        find.descendant(
          of: layerTile(label),
          matching: find.byTooltip(tooltip),
        ),
      );

  List<String> idsOf(ContentItem stack) =>
      stack.children!.map((c) => c.id).toList();

  List<double?> offsetsOf(ContentItem stack) =>
      stack.children!.map((c) => c.offsetLeft).toList();

  List<double?> topsOf(ContentItem stack) =>
      stack.children!.map((c) => c.offsetTop).toList();

  group('горячие клавиши канваса', () {
    testWidgets('Ctrl+A выделяет всех детей и не трогает автосейв', (
      tester,
    ) async {
      await pumpCanvas(tester);
      await selectAll(tester);

      expect(saved, isEmpty, reason: 'выделение — не правка документа');
      expect(undoButton(tester)?.onPressed, isNull, reason: 'история пуста');
      expect(find.textContaining('Текст · 16, 8 · 100×40'), findsOneWidget);
      expect(find.textContaining('ещё 1'), findsOneWidget);
    });

    testWidgets('стрелки двигают серией в один шаг, Ctrl+Z отменяет её', (
      tester,
    ) async {
      await pumpCanvas(tester);
      await selectAll(tester);

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(offsetsOf(saved.last), [18, 18]);
      expect(undoButton(tester)?.onPressed, isNotNull);

      await undo(tester);
      expect(offsetsOf(saved.last), [16, 16]);
      expect(redoButton(tester)?.onPressed, isNotNull);

      await press(
        tester,
        LogicalKeyboardKey.keyY,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(offsetsOf(saved.last), [18, 18]);
    });

    testWidgets('Shift+стрелка шагает вдесятеро', (tester) async {
      await pumpCanvas(tester);
      await selectAll(tester);
      await press(
        tester,
        LogicalKeyboardKey.arrowRight,
        modifier: LogicalKeyboardKey.shiftLeft,
      );
      expect(offsetsOf(saved.last), [26, 26]);
    });

    testWidgets('Alt+стрелка ресайзит вместо сдвига', (tester) async {
      await pumpCanvas(tester);
      await selectAll(tester);

      await press(
        tester,
        LogicalKeyboardKey.arrowRight,
        modifier: LogicalKeyboardKey.altLeft,
      );
      await press(
        tester,
        LogicalKeyboardKey.arrowDown,
        modifier: LogicalKeyboardKey.altLeft,
      );

      final child = saved.last.children!.first;
      expect(child.offsetLeft, 16, reason: 'левый верхний якорь стоит');
      expect(child.offsetRight, 117);
      expect(child.offsetBottom, 49);
      expect(undoButton(tester)?.tooltip, contains('размер'));

      await undo(tester);
      final back = saved.last.children!.first;
      expect(back.offsetRight, 116);
      expect(back.offsetBottom, 48);
    });

    testWidgets('Delete снимает выделенных, Ctrl+D дублирует копии', (
      tester,
    ) async {
      await pumpCanvas(tester);
      await selectAll(tester);
      await press(tester, LogicalKeyboardKey.delete);
      expect(saved.last.children, isEmpty);

      await undo(tester);
      expect(saved.last.children!.length, 2);

      await selectAll(tester);
      await press(
        tester,
        LogicalKeyboardKey.keyD,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      // Копии вставляются рядом с оригиналом и сдвигаются на 16 px.
      expect(offsetsOf(saved.last), [16, 32, 16, 32]);

      await press(
        tester,
        LogicalKeyboardKey.keyD,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(offsetsOf(saved.last), [
        16,
        32,
        48,
        16,
        32,
        48,
      ], reason: 'выделились копии — второй дубликат идёт от них');
    });

    testWidgets('Escape сбрасывает выделение', (tester) async {
      await pumpCanvas(tester);
      await selectAll(tester);
      expect(find.textContaining('ещё 1'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.textContaining('ещё 1'), findsNothing);
      expect(find.textContaining('2 элементов'), findsOneWidget);
    });

    testWidgets(
      'Ctrl+C/V: копирование не правит документ, вставки расходятся',
      (tester) async {
        await pumpCanvas(tester, stack: _stackSingle());
        await selectAll(tester);
        await press(
          tester,
          LogicalKeyboardKey.keyC,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        expect(saved, isEmpty, reason: 'копирование — не правка документа');

        await press(
          tester,
          LogicalKeyboardKey.keyV,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        expect(offsetsOf(saved.last), [16, 32]);
        expect(
          ribbonField(tester, 'x'),
          '32',
          reason: 'вставка забирает выделение, как дубликат',
        );
        expect(ribbonField(tester, 'y'), '24');

        await press(
          tester,
          LogicalKeyboardKey.keyV,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        expect(
          offsetsOf(saved.last),
          [16, 32, 48],
          reason: 'повторная вставка уходит веером от оригинала, а не от копии',
        );

        await undo(tester);
        expect(offsetsOf(saved.last), [16, 32]);
        await undo(tester);
        expect(offsetsOf(saved.last), [
          16,
        ], reason: 'каждая вставка — свой шаг');
      },
    );

    testWidgets('Ctrl+X убирает объект, Ctrl+V возвращает его копией', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);
      await press(
        tester,
        LogicalKeyboardKey.keyX,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(saved.last.children, isEmpty);

      await press(
        tester,
        LogicalKeyboardKey.keyV,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(offsetsOf(saved.last), [
        32,
        216,
        356,
      ], reason: 'те же объекты, но смещённые на шаг вставки');
      expect(
        idsOf(saved.last),
        isNot(contains('a')),
        reason: 'вставка всегда даёт новые id',
      );
      expect(find.textContaining('ещё 2'), findsOneWidget);
    });

    testWidgets('Ctrl+Alt+C/V: стиль переезжает, геометрия остаётся', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackStyled());

      // Центр 'a' — экранная (73, 226).
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));
      await press(
        tester,
        LogicalKeyboardKey.keyC,
        modifier: LogicalKeyboardKey.controlLeft,
        modifier2: LogicalKeyboardKey.altLeft,
      );
      expect(saved, isEmpty, reason: 'копирование стиля — не правка документа');

      // Центр 'b' — экранная (278, 283).
      await tester.tapAt(const Offset(278, 283));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        ribbonField(tester, 'x'),
        '200',
        reason: 'иначе перенос уйдёт не в тот слой',
      );
      expect(ribbonField(tester, 'y'), '60');
      expect(ribbonField(tester, 'w'), '100');
      await press(
        tester,
        LogicalKeyboardKey.keyV,
        modifier: LogicalKeyboardKey.controlLeft,
        modifier2: LogicalKeyboardKey.altLeft,
      );

      final b = saved.last.children!.firstWhere((c) => c.id == 'b');
      expect(b.backgroundColor, const Color(0xFF123456));
      expect(b.borderRadius, 12);
      expect(b.opacity, 0.5);
      expect(b.text, 'b', reason: 'содержимое слоя не трогаем');
      expect(b.offsetTop, 60, reason: 'перенос стиля не двигает слой');
      final a = saved.last.children!.firstWhere((c) => c.id == 'a');
      expect(a.offsetTop, 8);

      await undo(tester);
      expect(
        saved.last.children!.firstWhere((c) => c.id == 'b').backgroundColor,
        isNull,
        reason: 'перенос — один шаг истории',
      );
    });
  });

  group('выделение, выравнивание и распределение', () {
    testWidgets('панель появляется только на выделении', (tester) async {
      await pumpCanvas(tester);
      expect(find.byIcon(Icons.align_horizontal_left), findsNothing);

      await selectAll(tester);
      expect(find.byIcon(Icons.align_horizontal_left), findsOneWidget);
      expect(find.byIcon(Icons.vertical_align_bottom), findsOneWidget);
    });

    testWidgets('по левому краю — все в x первого, Ctrl+Z всё возвращает', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);
      expect(saved, isEmpty, reason: 'выравнивание ещё не трогали');

      await tester.tap(find.byIcon(Icons.align_horizontal_left));
      await tester.pump();
      expect(offsetsOf(saved.last), [16, 16, 16]);

      await undo(tester);
      expect(offsetsOf(saved.last), [16, 200, 340]);
    });

    testWidgets('равные промежутки: двоим недоступно', (tester) async {
      await pumpCanvas(tester);
      await selectAll(tester);
      expect(
        buttonOf(tester, Icons.horizontal_distribute)?.onPressed,
        isNull,
        reason: 'двум объектам распределять нечего',
      );
    });

    testWidgets('распределение по обеим осям раскладывает детей с зазором', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);

      await tester.tap(find.byIcon(Icons.horizontal_distribute));
      await tester.pump();
      expect(offsetsOf(saved.last), [16, 178, 340]);

      await tester.tap(find.byIcon(Icons.vertical_distribute));
      await tester.pump();
      expect(topsOf(saved.last), [8, 64, 120]);
    });

    testWidgets('тап по пустому месту снимает выделение', (tester) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);
      expect(find.textContaining('ещё 2'), findsOneWidget);

      // Точка ниже детей: стек в тесте масштабируется в 1.111 раза и смещён
      // по y, так что stack (5, 175) — это экранные (6, 388).
      await tester.tapAt(const Offset(6, 388));
      // Тап живёт под допустимым временем даблтапа — одиночный onTapUp
      // прилетает только после него.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('ещё 2'), findsNothing);
    });

    testWidgets('M включает рамку: обведённые дети попадают в выделение', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await press(tester, LogicalKeyboardKey.keyM);
      expect(
        find.byTooltip('Рамка выделения включена: тащите по фону (M — выкл)'),
        findsOneWidget,
      );

      // stack (5, 200) → stack (460, 5): рамка снизу-справа накрывает всех
      // трёх детей. Идём ступеньками — жест начинается по прошествии slop,
      // и один прыжок на весь путь попал бы не в фон, а в объект.
      const from = Offset(6, 417);
      const to = Offset(511, 200);
      final gesture = await tester.startGesture(from);
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await gesture.moveTo(Offset.lerp(from, to, t)!);
      }
      await gesture.up();
      // Даю истечь таймеру даблтапа — иначе binding ругается на висящий Timer.
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('ещё 2'), findsOneWidget);
      expect(saved, isEmpty, reason: 'выделение рамкой — не правка документа');
    });

    testWidgets('Alt+рамка вычитает из выделения, а не заменяет его', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await press(tester, LogicalKeyboardKey.keyM);
      await selectAll(tester);
      expect(find.textContaining('ещё 2'), findsOneWidget);

      // Та же рамка, что в тесте выше, но с Alt: под неё попадают все трое,
      // и выделение должно опустеть, а не «замениться» ничем.
      const from = Offset(6, 417);
      const to = Offset(511, 200);
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.altLeft,
        physicalKey: PhysicalKeyboardKey.altLeft,
      );
      final gesture = await tester.startGesture(from);
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await gesture.moveTo(Offset.lerp(from, to, t)!);
      }
      await gesture.up();
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.altLeft,
        physicalKey: PhysicalKeyboardKey.altLeft,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('ещё'), findsNothing);
      expect(find.textContaining('3 элементов'), findsOneWidget);
    });
  });

  group('прозрачность и поворот', () {
    testWidgets('панель открывается на одном выделенном и правит ребёнка', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      expect(find.byIcon(Icons.tune_rounded), findsNothing);

      await selectAll(tester);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      // opacity, поворот, масштаб и — только для текстового слоя — размер шрифта.
      expect(find.byType(Slider), findsNWidgets(4));
      expect(
        find.textContaining('ось-выровненным'),
        findsOneWidget,
        reason: 'подсказка про поворот только на отрисовку',
      );

      // Тап в середину дорожки первого ползунка — opacity ≈ 0.5. Допуск по
      // толщине самого ползунка: внутренний трек Slider короче его rect.
      // Шит свойств прокручиваем: под сеткой якорей ползунок не гарантированно
      // попадает в вьюпорт теста.
      await tester.ensureVisible(find.byType(Slider).first);
      await tester.pumpAndSettle();
      final track = tester.getRect(find.byType(Slider).first);
      await tester.tapAt(track.center);
      await tester.pump();
      expect(saved.last.children!.single.opacity, closeTo(0.5, 0.05));

      await closeSheet(tester);
      await undo(tester);
      expect(saved.last.children!.single.opacity, 1.0);
    });

    testWidgets('серия движений ползунка — один шаг истории', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      // Второй ползунок — поворот (первый opacity, третий размер шрифта).
      final rotation = find.byType(Slider).at(1);
      await tester.ensureVisible(rotation);
      await tester.pumpAndSettle();
      final track = tester.getRect(rotation);
      final gesture = await tester.startGesture(
        Offset(track.left + 2, track.center.dy),
      );
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await gesture.moveTo(
          Offset(track.left + track.width * t, track.center.dy),
        );
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(saved.last.children!.single.rotation, closeTo(180, 20));
      await closeSheet(tester);
      await undo(tester);
      expect(
        saved.last.children!.single.rotation,
        0.0,
        reason: 'вся серия — одна отмена',
      );
    });

    testWidgets('ползунок размера шрифта правит текстовый слой', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      // Третий ползунок появляется только у текста: у него есть что менять.
      final sizeSlider = find.byType(Slider).last;
      await tester.ensureVisible(sizeSlider);
      await tester.pumpAndSettle();
      final track = tester.getRect(sizeSlider);
      await tester.tapAt(Offset(track.center.dx, track.center.dy));
      await tester.pump(const Duration(milliseconds: 400));
      expect(saved.last.children!.single.textSize, closeTo(36, 3));

      // Превью на канвасе рисуется тем же размером — иначе редактор врёт.
      final previewSizes = tester
          .widgetList<Text>(find.byType(Text))
          .where((w) => w.data == 'a')
          .map((w) => w.style?.fontSize);
      expect(previewSizes, contains(36.0));

      await closeSheet(tester);
      await undo(tester);
      expect(
        saved.last.children!.single.textSize,
        isNull,
        reason: 'без правки — движковый дефолт 16',
      );
    });
  });

  group('обводка текста', () {
    /// Одиночный текстовый слой → шит свойств.
    Future<void> openProps(WidgetTester tester) async {
      await selectAll(tester);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
    }

    /// Тап по плашке открывает палитру нодовых цветов; выбор по имени Tooltip'а
    /// — тот же путь, что у «фона стека».
    Future<void> pickOutlineColor(WidgetTester tester, String name) async {
      final swatch = find.byKey(const ValueKey('stack_outline_swatch'));
      await tester.ensureVisible(swatch);
      await tester.pumpAndSettle();
      await tester.tap(swatch);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(name));
      await tester.pumpAndSettle();
    }

    testWidgets('у текста строка есть, а без цвета ни толщины, ни «убрать»', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await openProps(tester);
      expect(find.text('Обводка'), findsOneWidget);
      expect(find.byKey(const ValueKey('stack_outline_clear')), findsNothing);
      expect(find.text('Толщина, px'), findsNothing);
      expect(
        find.byType(Slider),
        findsNWidgets(4),
        reason: 'opacity, поворот, масштаб и размер шрифта — пятого пока нет',
      );
      await closeSheet(tester);
    });

    testWidgets('у картинки строки нет: обводка — свойство текста', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackImage());
      await openProps(tester);
      expect(find.text('Размер, px'), findsNothing);
      expect(find.text('Обводка'), findsNothing);
      await closeSheet(tester);
    });

    testWidgets('выбор цвета пишет слой, включает ползунок и ложится в превью', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await openProps(tester);
      await pickOutlineColor(tester, 'Оранжевый');

      final child = saved.last.children!.single;
      expect(child.textOutlineColor, const Color(0xFFF57C00));
      expect(child.textOutlineWidth, isNull, reason: 'цвет толщину не задаёт');
      expect(
        child.textOutlinePaint?.strokeWidth,
        kTextOutlineWidthDefault,
        reason: 'без толщины кисть берёт дефолт',
      );

      expect(find.text('Толщина, px'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(5));

      // Превью на канвасе обязано рисовать тот же контур, что и плеер:
      // нижним слоем идёт штриховая копия того же текста.
      final strokeLayers = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (w) =>
                w.data == 'a' &&
                w.style?.foreground?.style == PaintingStyle.stroke,
          );
      expect(strokeLayers, hasLength(1));

      await closeSheet(tester);
      await undo(tester);
      expect(saved.last.children!.single.textOutlineColor, isNull);
    });

    testWidgets('серия движений ползунка толщины — один шаг истории', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await openProps(tester);
      await pickOutlineColor(tester, 'Синий');

      final widthSlider = find.byType(Slider).last;
      await tester.ensureVisible(widthSlider);
      await tester.pumpAndSettle();
      final track = tester.getRect(widthSlider);
      final gesture = await tester.startGesture(
        Offset(track.left + 2, track.center.dy),
      );
      for (double t = 0.1; t <= 0.601; t += 0.1) {
        await gesture.moveTo(
          Offset(track.left + track.width * t, track.center.dy),
        );
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      // Ползунок делённый (1…12 px), поэтому значение целое и оно изменилось.
      final width = saved.last.children!.single.textOutlineWidth!;
      expect(width % 1, 0.0);
      expect(width, greaterThan(kTextOutlineWidthDefault));
      expect(width, lessThanOrEqualTo(kTextOutlineWidthMax));

      await closeSheet(tester);
      await undo(tester);
      final restored = saved.last.children!.single;
      expect(restored.textOutlineColor, const Color(0xFF1976D2));
      expect(
        restored.textOutlineWidth,
        isNull,
        reason: 'вся серия — одна отмена, а цвет переживал её до драга',
      );
    });

    testWidgets('поле толщины и «убрать»: снимает оба поля одним шагом', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await openProps(tester);
      await pickOutlineColor(tester, 'Красный');

      await tester.enterText(
        find.widgetWithText(TextField, 'Толщина, px'),
        '7',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saved.last.children!.single.textOutlineWidth, 7.0);

      await tester.ensureVisible(
        find.byKey(const ValueKey('stack_outline_clear')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stack_outline_clear')));
      await tester.pump();

      final cleared = saved.last.children!.single;
      expect(cleared.textOutlineColor, isNull);
      expect(
        cleared.textOutlineWidth,
        isNull,
        reason: 'без цвета толщина бессмысленна — снимаем пару целиком',
      );
      expect(cleared.textOutlinePaint, isNull);
      expect(find.text('Толщина, px'), findsNothing);

      await closeSheet(tester);
      await undo(tester);
      final back = saved.last.children!.single;
      expect(back.textOutlineColor, const Color(0xFFD32F2F));
      expect(back.textOutlineWidth, 7.0, reason: 'отмена возвращает пару');
    });
  });

  group('панель слоёв', () {
    Future<void> openPanel(WidgetTester tester) async {
      await tester.tap(
        find.byTooltip(
          'Панель слоёв: z-порядок (долгое нажатие на строку), '
          'видимость, замок, выбор',
        ),
      );
      await tester.pump();
    }

    testWidgets('порядок сверху — передний план, тап по строке выделяет', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      expect(find.textContaining('Слои ·'), findsNothing);

      await openPanel(tester);
      expect(find.text('Слои · 3'), findsOneWidget);
      // z-порядок развёрнут: c (передний) выше списка, чем a (задний).
      final rows = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect(
        tester.getTopLeft(find.widgetWithText(ListTile, 'c')).dy,
        lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'a')).dy),
      );
      expect(rows, hasLength(3));

      // Тап по имени, а не по середине строки: справа от имени — кнопки слоя.
      await tester.tap(
        find.descendant(of: layerTile('b'), matching: find.text('b')),
      );
      await tester.pump();
      expect(find.textContaining('Текст · 200, 60'), findsOneWidget);
    });

    testWidgets('стрелки меняют z-порядок и отменяются', (tester) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await openPanel(tester);

      await tapLayer(tester, 'a', 'На слой выше');
      await tester.pump();
      expect(idsOf(saved.last), ['b', 'a', 'c']);

      await undo(tester);
      expect(idsOf(saved.last), ['a', 'b', 'c']);
    });

    testWidgets('долгое нажатие и драг строки меняют z-порядок', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await openPanel(tester);

      // c — верх списка (передний план). Целимся в дно строки a: ниже центра
      // — иначе прокси встаёт в середину, а не в последний слот. X — левый
      // край: справа в строке четыре кнопки слоя, жест ушёл бы в них.
      Rect row(String id) => tester.getRect(layerTile(id));
      final from = Offset(row('c').left + 12, row('c').center.dy);
      final to = Offset(row('a').left + 12, row('a').bottom - 4);
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      // Шагами, а не одним прыжком: список переставляет слой на каждом
      // пересечении границы строки, и следующий индекс приходит только после
      // предыдущего коммита.
      for (double t = 0.05; t <= 1.001; t += 0.05) {
        await gesture.moveTo(Offset.lerp(from, to, t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(idsOf(saved.last), ['c', 'a', 'b']);
      expect(undoButton(tester)?.tooltip, contains('порядок слоёв'));

      await undo(tester);
      expect(idsOf(saved.last), ['a', 'b', 'c']);
    });

    testWidgets('у переднего слоя нет «выше», у заднего — нет «ниже»', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await openPanel(tester);

      // Инвалидные стрелки остаются в дереве, но с погашенным onTap.
      InkWell arrow(String label, String tooltip) => tester.widget<InkWell>(
        find.descendant(
          of: find.descendant(
            of: layerTile(label),
            matching: find.byTooltip(tooltip),
          ),
          matching: find.byType(InkWell),
        ),
      );
      expect(arrow('c', 'На слой выше').onTap, isNull);
      expect(arrow('a', 'На слой ниже').onTap, isNull);
      expect(arrow('b', 'На слой выше').onTap, isNotNull);
    });

    testWidgets('скрытый слой: призрак на канвасе, вне тапа и вне Ctrl+A', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await openPanel(tester);
      await tapLayer(tester, 'a', 'Скрыть слой');
      await tester.pump();

      final hidden = saved.last.children!.firstWhere((c) => c.id == 'a');
      expect(hidden.isHidden, isTrue);
      expect(
        find.descendant(
          of: layerTile('a'),
          matching: find.byTooltip('Показать слой'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Закрыть панель слоёв'));
      await tester.pump();

      await selectAll(tester);
      expect(
        find.textContaining('ещё 1'),
        findsOneWidget,
        reason: 'скрытый слой в «выделить всё» не попадает',
      );

      // Центр 'a' — stack (66, 28) → экранная (73, 226): тап мимо, выделение
      // снимается, хотя объект на канвасе по-прежнему виден призраком.
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('ещё 1'), findsNothing);
      expect(find.textContaining('3 элементов'), findsOneWidget);
    });

    testWidgets('замок: слой вне Ctrl+A и тапом не берётся', (tester) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await openPanel(tester);
      await tapLayer(
        tester,
        'a',
        'Заблокировать слой: не выделяется тапом, рамкой и Ctrl+A',
      );
      await tester.pump();

      final locked = saved.last.children!.firstWhere((c) => c.id == 'a');
      expect(locked.locked, isTrue);
      expect(
        find.descendant(
          of: layerTile('a'),
          matching: find.byTooltip(
            'Разблокировать слой: его снова можно выделить',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Закрыть панель слоёв'));
      await tester.pump();

      await selectAll(tester);
      expect(
        find.textContaining('ещё 1'),
        findsOneWidget,
        reason: 'запертый слой в «выделить всё» не попадает',
      );

      // Центр 'a' — экранная (73, 226): тап по запертому снимает выделение,
      // а не выделяет его.
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('ещё 1'), findsNothing);
      expect(find.textContaining('3 элементов'), findsOneWidget);
    });

    testWidgets('замок на выделенном слое снимает выделение, undo возвращает', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);
      expect(find.textContaining('ещё 2'), findsOneWidget);

      await openPanel(tester);
      await tapLayer(
        tester,
        'a',
        'Заблокировать слой: не выделяется тапом, рамкой и Ctrl+A',
      );
      await tester.pump();
      expect(
        find.textContaining('ещё 1'),
        findsOneWidget,
        reason: 'a выпал из выделения сам, иначе Delete обошёл бы замок',
      );

      await undo(tester);
      expect(
        saved.last.children!.firstWhere((c) => c.id == 'a').locked,
        isFalse,
      );
    });

    testWidgets('заблокированный слой всё ещё двигается в панели слоёв', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await openPanel(tester);
      await tapLayer(
        tester,
        'b',
        'Заблокировать слой: не выделяется тапом, рамкой и Ctrl+A',
      );
      await tester.pump();
      await tapLayer(tester, 'b', 'На слой выше');
      await tester.pump();

      expect(idsOf(saved.last), ['a', 'c', 'b']);
    });

    testWidgets('выделенный слой получает имя и новую подпись в списке', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await openPanel(tester);
      await tester.tap(
        find.descendant(of: layerTile('b'), matching: find.text('b')),
      );
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byTooltip('Переименовать слой'));
      await tester.pumpAndSettle();
      expect(find.text('Имя слоя'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Подпись');
      await tester.tap(find.text('Переименовать'));
      await tester.pumpAndSettle();

      final named = saved.last.children!.firstWhere((c) => c.id == 'b');
      expect(named.layerName, 'Подпись');
      expect(named.text, 'b', reason: 'текст объекта имя слоя не трогает');
      // Строка списка подписана именем, а канвас по-прежнему рисует текст.
      expect(find.widgetWithText(ListTile, 'Подпись'), findsOneWidget);
      expect(undoButton(tester)?.tooltip, contains('имя слоя'));
    });
  });

  group('ручка поворота на канвасе', () {
    Finder rotateHandle() => find.byKey(const ValueKey('rotate_handle_a'));

    /// Любая ручка поворота — ключ содержит id объекта.
    Finder anyRotateHandle() => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('rotate_handle_'),
    );

    /// Центр бокса — середина между диагональными угловыми ручками: тест не
    /// зависит от того, как именно стек вписался в тестовые 800×600.
    Offset boxCenter(WidgetTester tester) {
      final tl = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeTL')))
          .center;
      final br = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeBR')))
          .center;
      return Offset((tl.dx + br.dx) / 2, (tl.dy + br.dy) / 2);
    }

    testWidgets('на группе из двух объектов ручки нет', (tester) async {
      await pumpCanvas(tester);
      expect(anyRotateHandle(), findsNothing);

      await selectAll(tester);
      expect(
        anyRotateHandle(),
        findsNothing,
        reason: 'группу не крутят за ручку',
      );
    });

    testWidgets(
      'драг на четверть оборота поворачивает и отменяется одним шагом',
      (tester) async {
        await pumpCanvas(tester, stack: _stackSingle());
        await selectAll(tester);

        final center = boxCenter(tester);
        final start = tester.getRect(rotateHandle()).center;
        final radius = center.dy - start.dy;
        final gesture = await tester.startGesture(start);
        for (double t = 0.2; t <= 1.001; t += 0.2) {
          // По хорде: угол от центра меняется монотонно от −90° до 0°.
          await gesture.moveTo(
            Offset.lerp(start, Offset(center.dx + radius, center.dy), t)!,
          );
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          saved.last.children!.single.rotation,
          closeTo(90, 3),
          reason: 'вектор «центр → палец» повернулся на 90°',
        );

        await undo(tester);
        expect(
          saved.last.children!.single.rotation,
          0.0,
          reason: 'вся дуга — одна запись истории',
        );
      },
    );

    testWidgets('Shift держит угол на сетке 15°', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      final center = boxCenter(tester);
      final start = tester.getRect(rotateHandle()).center;
      final radius = center.dy - start.dy;
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
      );
      final gesture = await tester.startGesture(start);
      // Экранная цель «на 30.7° от верхнего положения»: без Shift дала бы
      // дробный угол, с Shift ждём ровно 30°.
      final target = Offset(
        center.dx + radius * 0.51,
        center.dy - radius * 0.86,
      );
      for (double t = 0.2; t <= 1.001; t += 0.2) {
        await gesture.moveTo(Offset.lerp(start, target, t)!);
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
      );

      final rotation = saved.last.children!.single.rotation;
      expect(rotation % 15, 0, reason: 'сетка 15°, а не 30.7°');
      expect(rotation, 30);
    });
  });

  group('зум с клавиатуры', () {
    // Для знаков физическую клавишу передаём явно: на региональных раскладках
    // «=» и «-» лежат на других кодах, и дефолтный подбор может не сработать.
    Future<void> pressKey(
      WidgetTester tester,
      LogicalKeyboardKey logical,
      PhysicalKeyboardKey physical,
    ) async {
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.sendKeyEvent(logical, physicalKey: physical);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.pump();
    }

    testWidgets('Ctrl+= приближает, Ctrl+- откатывает назад', (tester) async {
      await pumpCanvas(tester);
      expect(find.text('100%'), findsOneWidget);

      await pressKey(
        tester,
        LogicalKeyboardKey.equal,
        PhysicalKeyboardKey.equal,
      );
      expect(find.text('125%'), findsOneWidget);

      await pressKey(
        tester,
        LogicalKeyboardKey.equal,
        PhysicalKeyboardKey.equal,
      );
      expect(find.text('156%'), findsOneWidget, reason: '1.25² = 1.5625');

      await pressKey(
        tester,
        LogicalKeyboardKey.minus,
        PhysicalKeyboardKey.minus,
      );
      expect(find.text('125%'), findsOneWidget);
    });

    testWidgets('Ctrl+1 даёт 100 %, Ctrl+0 сбрасывает вид', (tester) async {
      await pumpCanvas(tester);
      await pressKey(
        tester,
        LogicalKeyboardKey.equal,
        PhysicalKeyboardKey.equal,
      );
      expect(find.text('125%'), findsOneWidget);

      await pressKey(
        tester,
        LogicalKeyboardKey.digit1,
        PhysicalKeyboardKey.digit1,
      );
      expect(find.text('100%'), findsOneWidget, reason: 'реальный масштаб');

      await pressKey(
        tester,
        LogicalKeyboardKey.equal,
        PhysicalKeyboardKey.equal,
      );
      await pressKey(
        tester,
        LogicalKeyboardKey.digit0,
        PhysicalKeyboardKey.digit0,
      );
      expect(find.text('100%'), findsOneWidget, reason: 'вписать = камера 1.0');
    });

    testWidgets('Ctrl+2 вписывает в вид выделение', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      saved.clear();
      expect(find.text('100%'), findsOneWidget);

      await pressKey(
        tester,
        LogicalKeyboardKey.digit2,
        PhysicalKeyboardKey.digit2,
      );

      final shown = tester.widget<Text>(find.textContaining('%')).data!;
      expect(
        int.parse(shown.replaceAll('%', '')),
        greaterThan(100),
        reason: 'крошечный объект должен приблизиться до потолка зума',
      );
      expect(saved, isEmpty, reason: 'камера — не правка стека');
    });

    testWidgets('Ctrl+2 без выделения вид не трогает', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await pressKey(
        tester,
        LogicalKeyboardKey.digit2,
        PhysicalKeyboardKey.digit2,
      );
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('зум не правит документ', (tester) async {
      await pumpCanvas(tester);
      await selectAll(tester);
      saved.clear();

      await pressKey(
        tester,
        LogicalKeyboardKey.equal,
        PhysicalKeyboardKey.equal,
      );
      await pressKey(
        tester,
        LogicalKeyboardKey.digit0,
        PhysicalKeyboardKey.digit0,
      );
      expect(saved, isEmpty, reason: 'камера — не правка стека');

      // Без Ctrl тот же знак ничего не должен менять.
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);
    });
  });

  group('сохранение пропорций при ресайзе', () {
    /// Драг правого нижнего угла вправо на 40 px экрана. Возвращает rect
    /// ребёнка после коммита: якоря у него нулевые, поэтому offset'ы — и есть
    /// координаты внутри холста.
    Future<ContentItem> dragBrCorner(
      WidgetTester tester, {
      bool shift = false,
    }) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      if (shift) {
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
        );
      }
      final br = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeBR')))
          .center;
      final gesture = await tester.startGesture(br);
      for (double t = 0.25; t <= 1.001; t += 0.25) {
        await gesture.moveTo(Offset.lerp(br, br + const Offset(40, 0), t)!);
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      if (shift) {
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
        );
      }
      return saved.last.children!.single;
    }

    double widthOf(ContentItem child) => child.offsetRight - child.offsetLeft;
    double heightOf(ContentItem child) => child.offsetBottom - child.offsetTop;

    testWidgets('обычный драг угла меняет только одну ось', (tester) async {
      final child = await dragBrCorner(tester);

      expect(child.offsetLeft, 16, reason: 'верх-лево закреплены');
      expect(child.offsetTop, 8);
      expect(widthOf(child), greaterThan(100));
      expect(heightOf(child), 40);
    });

    testWidgets('Shift-драг угла тянет пропорционально', (tester) async {
      final child = await dragBrCorner(tester, shift: true);

      expect(child.offsetLeft, 16);
      expect(child.offsetTop, 8);
      expect(
        widthOf(child) / heightOf(child),
        closeTo(100 / 40, 0.01),
        reason: 'соотношение 2.5 удержано',
      );
      expect(heightOf(child), greaterThan(40), reason: 'высота додана сама');
    });

    // #185: ручка за границей холста возвращала объект назад — превью рисовало
    // большой бокс, а коммит ограничивал его размером канваса.
    testWidgets('правый край можно увести за границу холста', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      final br = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeBR')))
          .center;
      final gesture = await tester.startGesture(br);
      for (double t = 0.25; t <= 1.001; t += 0.25) {
        await gesture.moveTo(Offset.lerp(br, br + const Offset(1200, 0), t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      final child = saved.last.children!.single;
      // Под прежним лимитом коммит возвращал ровно ширину холста — 720 px,
      // поэтому проверяем запас, а не просто «больше края».
      expect(
        widthOf(child),
        greaterThan(kStackCanvasWidth + 200),
        reason: 'правый край ушёл дальше 720 px холста',
      );
      expect(child.offsetLeft, 16);
    });
  });

  group('прилипление при ресайзе', () {
    /// Экранное отображение канваса: масштаб и начало координат считаются по
    /// двум угловым ручкам одного rect'а, поэтому тест не зависит ни от того,
    /// как стек вписался в 800×600, ни от зума.
    ({double scale, Offset origin}) mapping(
      WidgetTester tester, {
      required String tlKey,
      required String brKey,
      required Rect stackRect,
    }) {
      final tl = tester.getRect(find.byKey(ValueKey(tlKey))).center;
      final br = tester.getRect(find.byKey(ValueKey(brKey))).center;
      final scale = (br.dx - tl.dx) / stackRect.width;
      return (
        scale: scale,
        origin: tl - Offset(stackRect.left, stackRect.top) * scale,
      );
    }

    Future<void> dragHandle(WidgetTester tester, String key, Offset to) async {
      final from = tester.getRect(find.byKey(ValueKey(key))).center;
      final gesture = await tester.startGesture(from);
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await gesture.moveTo(Offset.lerp(from, to, t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    ContentItem childOf(String id) =>
        saved.last.children!.firstWhere((c) => c.id == id);

    testWidgets('угол объекта доводится до края соседа', (tester) async {
      await pumpCanvas(tester, stack: _stackSpread());
      // Центр 'a' — stack (66, 28).
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));
      final map = mapping(
        tester,
        tlKey: 'handle_a-resizeTL',
        brKey: 'handle_a-resizeBR',
        stackRect: const Rect.fromLTWH(16, 8, 100, 40),
      );
      // На 4 px правее левого края 'b' (200) — в пороге прилипания; без него
      // край встал бы ровно сюда.
      final to = map.origin + Offset(204 * map.scale, 0);
      await dragHandle(
        tester,
        'handle_a-resizeBR',
        Offset(
          to.dx,
          tester
              .getRect(find.byKey(const ValueKey('handle_a-resizeBR')))
              .center
              .dy,
        ),
      );

      expect(childOf('a').offsetRight, closeTo(200, 0.01));
      expect(childOf('a').offsetLeft, 16, reason: 'левый край закреплён');
      expect(childOf('a').offsetTop, 8);
    });

    testWidgets('ограничивающий rect группы доводится до края канваса', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);
      final map = mapping(
        tester,
        tlKey: 'group_handle_resizeTL',
        brKey: 'group_handle_resizeBR',
        stackRect: const Rect.fromLTWH(16, 8, 424, 152),
      );
      final br = tester
          .getRect(find.byKey(const ValueKey('group_handle_resizeBR')))
          .center;
      await dragHandle(
        tester,
        'group_handle_resizeBR',
        Offset(map.origin.dx + 717 * map.scale, br.dy),
      );

      expect(
        childOf('c').offsetRight,
        closeTo(720, 0.01),
        reason: 'правый край группы доведён до рамки канваса',
      );
      expect(childOf('c').offsetLeft, greaterThan(340));
      expect(childOf('a').offsetLeft, closeTo(16, 0.01));
    });
  });

  group('Alt+драг дублирует', () {
    /// Центр выбранного объекта 'a' по его же resize-ручкам: пересчитывать
    /// экран из координат стека руками — удвоить математику камеры в тесте.
    Offset boxCenter(WidgetTester tester) {
      final tl = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeTL')))
          .center;
      final br = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeBR')))
          .center;
      return Offset((tl.dx + br.dx) / 2, (tl.dy + br.dy) / 2);
    }

    Future<void> dragWithAlt(WidgetTester tester, Offset delta) async {
      final from = boxCenter(tester);
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.altLeft,
        physicalKey: PhysicalKeyboardKey.altLeft,
      );
      final gesture = await tester.startGesture(from);
      for (double t = 0.25; t <= 1.001; t += 0.25) {
        await gesture.moveTo(Offset.lerp(from, from + delta, t)!);
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.altLeft,
        physicalKey: PhysicalKeyboardKey.altLeft,
      );
    }

    testWidgets('тащится копия, оригинал стоит на месте', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      await dragWithAlt(tester, const Offset(60, 0));

      final children = saved.last.children!;
      expect(children, hasLength(2));
      expect(children.first.id, 'a');
      expect(
        children.first.offsetLeft,
        16,
        reason: 'оригинал не сдвинулся ни на пиксель',
      );
      // Смещение экранных 60 px в координаты стека — величина масштабная
      // (здесь ~27), проверяем факт: копия уехала, оригинал нет.
      expect(
        children.last.offsetLeft,
        greaterThan(children.first.offsetLeft + 20),
      );
    });

    testWidgets('дубликат и перемещение — одна отмена', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      await dragWithAlt(tester, const Offset(60, 0));

      expect(undoButton(tester)?.tooltip, contains('дубликат'));

      await undo(tester);
      expect(saved.last.children!.map((c) => c.id), [
        'a',
      ], reason: 'один шаг убирает копию целиком, а не возвращает её на место');
      expect(saved.last.children!.single.offsetLeft, 16);
    });

    testWidgets('Alt+клик без движения всё равно создаёт копию', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      await dragWithAlt(tester, Offset.zero);

      final children = saved.last.children!;
      expect(children, hasLength(2));
      expect(children.first.offsetLeft, 16);
      expect(children.last.offsetLeft, 16);
      expect(undoButton(tester)?.tooltip, contains('дубликат'));
    });
  });

  group('ресайз группы', () {
    Rect rectOf(ContentItem c) => Rect.fromLTWH(
      c.offsetLeft,
      c.offsetTop,
      c.offsetRight - c.offsetLeft,
      c.offsetBottom - c.offsetTop,
    );

    /// Растягивает правый нижний угол ограничивающего rect'а на дельту
    /// экрана и возвращает детей после коммита.
    Future<List<ContentItem>> resizeGroup(
      WidgetTester tester,
      Offset delta, {
      bool shift = false,
    }) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);
      final br = tester
          .getRect(find.byKey(const ValueKey('group_handle_resizeBR')))
          .center;
      if (shift) {
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
        );
      }
      final gesture = await tester.startGesture(br);
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await gesture.moveTo(Offset.lerp(br, br + delta, t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      if (shift) {
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
        );
      }
      return saved.last.children!;
    }

    testWidgets('группа берётся за ручки общего bounding box', (tester) async {
      await pumpCanvas(tester, stack: _stackSpread());
      expect(find.byKey(const ValueKey('group_handle_resizeBR')), findsNothing);

      await selectAll(tester);
      // Одиночные ручки и ручка поворота — только у одного объекта.
      expect(find.byKey(const ValueKey('handle_a-resizeBR')), findsNothing);
      expect(
        find.byKey(const ValueKey('group_handle_resizeBR')),
        findsOneWidget,
        reason: 'на мультивыделении — 4 ручки вокруг группы',
      );
      expect(find.byKey(const ValueKey('rotate_handle_a')), findsNothing);
    });

    testWidgets('тянет всех детей одним множителем, отменяется одним шагом', (
      tester,
    ) async {
      final after = await resizeGroup(tester, const Offset(60, 40));
      final a = after.firstWhere((c) => c.id == 'a');
      final b = after.firstWhere((c) => c.id == 'b');
      final c = after.firstWhere((c) => c.id == 'c');

      // Якорь группы — её левый верхний угол: a там и был, он не уехал.
      expect(rectOf(a).left, 16);
      expect(rectOf(a).top, 8);
      // Все трое выросли в одно и то же число раз — группа вела себя как
      // одна картинка, а не как три независимых ресайза.
      final sx = rectOf(a).width / 100;
      expect(sx, greaterThan(1));
      expect(rectOf(b).width / 100, closeTo(sx, 0.02));
      expect(rectOf(c).width / 100, closeTo(sx, 0.02));
      // И разъехались пропорционально расстоянию до якоря.
      expect(rectOf(b).left, greaterThan(200));
      expect(rectOf(c).left, greaterThan(rectOf(b).right));
      expect(
        rectOf(c).right,
        lessThanOrEqualTo(kStackCanvasWidth),
        reason: 'группа не вылезла за холст',
      );

      await undo(tester);
      expect(offsetsOf(saved.last), [16, 200, 340]);
      expect(topsOf(saved.last), [8, 60, 120]);
    });

    testWidgets('Shift держит пропорции ограничивающего rect’а', (
      tester,
    ) async {
      final spread = _stackSpread().children!;
      final union = unionOfChildren(children: spread, height: 240)!;
      final after = await resizeGroup(tester, const Offset(60, 0), shift: true);
      final grown = unionOfChildren(children: after, height: 240)!;

      expect(
        grown.width / grown.height,
        closeTo(union.width / union.height, 0.02),
        reason: 'драг был по горизонтали, но высота додана сама',
      );
      expect(grown.height, greaterThan(union.height));
    });
  });

  group('ручки середин сторон', () {
    Rect rectOf(ContentItem c) => Rect.fromLTWH(
      c.offsetLeft,
      c.offsetTop,
      c.offsetRight - c.offsetLeft,
      c.offsetBottom - c.offsetTop,
    );

    /// Драг ручки [key] на [delta] пикселей экрана; возвращает детей после
    /// коммита.
    Future<List<ContentItem>> dragBy(
      WidgetTester tester,
      String key,
      Offset delta,
    ) async {
      final from = tester.getRect(find.byKey(ValueKey(key))).center;
      final gesture = await tester.startGesture(from);
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await gesture.moveTo(Offset.lerp(from, from + delta, t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      return saved.last.children!;
    }

    testWidgets('правая ручка объекта тянет только ширину', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      final child = (await dragBy(
        tester,
        'handle_a-resizeRight',
        const Offset(40, 30),
      )).single;

      expect(child.offsetLeft, 16);
      expect(child.offsetTop, 8);
      expect(
        child.offsetBottom,
        48,
        reason: 'низ закреплён: ручка середины стороны не трогает его',
      );
      expect(child.offsetRight, greaterThan(116));
    });

    testWidgets('правая ручка группы множит только x', (tester) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);

      final after = await dragBy(
        tester,
        'group_handle_resizeRight',
        const Offset(60, 40),
      );
      final a = after.firstWhere((c) => c.id == 'a');
      final b = after.firstWhere((c) => c.id == 'b');

      final sx = rectOf(a).width / 100;
      expect(sx, greaterThan(1));
      expect(rectOf(b).width / 100, closeTo(sx, 0.02));
      expect(
        rectOf(b).left,
        closeTo(16 + (200 - 16) * sx, 0.5),
        reason: 'смещение масштабируется тем же множителем',
      );
      expect(rectOf(a).top, 8, reason: 'по вертикали группа не двинулась');
      expect(rectOf(a).height, 40);
      expect(rectOf(b).top, 60);
    });
  });

  group('сетка канваса', () {
    /// Экранное отображение канваса по двум угловым ручкам объекта 'a': тест
    /// не зависит ни от того, как стек вписался в окно, ни от зума.
    ({double scale, Offset origin}) mapping(WidgetTester tester) {
      final tl = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeTL')))
          .center;
      final br = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeBR')))
          .center;
      const rect = Rect.fromLTWH(16, 8, 100, 40);
      final scale = (br.dx - tl.dx) / rect.width;
      return (scale: scale, origin: tl - Offset(rect.left, rect.top) * scale);
    }

    Future<void> toggleGrid(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('sheet_grid_switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('sheet_grid_switch')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await closeSheet(tester);
    }

    /// Драг тела объекта 'a' вправо на [stackDx] стековых пикселей.
    Future<ContentItem> dragBody(WidgetTester tester, double stackDx) async {
      final map = mapping(tester);
      final from = map.origin + const Offset(66, 28) * map.scale;
      final to = from + Offset(stackDx * map.scale, 0);
      final gesture = await tester.startGesture(from);
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await gesture.moveTo(Offset.lerp(from, to, t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      return saved.last.children!.single;
    }

    testWidgets('сетка включается и выключается в свойствах канваса', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      expect(find.byKey(const ValueKey('stack_grid')), findsNothing);

      await toggleGrid(tester);
      expect(find.byKey(const ValueKey('stack_grid')), findsOneWidget);
      expect(find.text('20 px'), findsNothing, reason: 'шит закрыт');

      saved.clear();
      await toggleGrid(tester);
      expect(find.byKey(const ValueKey('stack_grid')), findsNothing);
      expect(saved, isEmpty, reason: 'сетка — вид, а не правка документа');
    });

    testWidgets('выбор шага сетки живёт в свойствах канваса', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pumpAndSettle();

      expect(find.text('40 px'), findsNothing, reason: 'сетка ещё выключена');
      await tester.ensureVisible(
        find.byKey(const ValueKey('sheet_grid_switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('sheet_grid_switch')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('40 px'), findsOneWidget);

      // Шит скроллируется, и чипы сетки после добавления ещё одной настройки
      // уезжают за нижний край — тап по невидимому целился бы мимо.
      await tester.ensureVisible(find.text('40 px'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('40 px'));
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '40 px'),
      );
      expect(chip.selected, isTrue);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '20 px'))
            .selected,
        isFalse,
      );
    });

    testWidgets('край объекта прилипает к линии сетки', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      // У жеста перемещения есть мёртвая зона распознавания, поэтому цель
      // считаем по первому проходу без сетки: край встаёт между линиями.
      final plain = await dragBody(tester, 47);
      final line = (plain.offsetLeft / 20).roundToDouble() * 20;
      expect(
        (plain.offsetLeft - line).abs(),
        greaterThan(1),
        reason: 'без сетки край остаётся там, где его отпустили',
      );

      await undo(tester);
      await toggleGrid(tester);
      await selectAll(tester);
      final snapped = await dragBody(tester, 47 + (line - plain.offsetLeft));
      expect(snapped.offsetLeft, closeTo(line, 0.01));
      expect(snapped.offsetTop, 8, reason: 'горизонтальный драг не трогает y');
    });

    testWidgets('ручка ресайза цепляется за сетку', (tester) async {
      /// Правая ручка объекта в stack-координате [toStackX]; возвращает
      /// правый край после коммита.
      Future<double> dragRightEdge(double toStackX) async {
        final map = mapping(tester);
        final from = tester
            .getRect(find.byKey(const ValueKey('handle_a-resizeRight')))
            .center;
        final to = map.origin + Offset(toStackX, 28) * map.scale;
        final gesture = await tester.startGesture(from);
        for (double t = 0.1; t <= 1.001; t += 0.1) {
          await gesture.moveTo(Offset.lerp(from, to, t)!);
          await tester.pump();
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 400));
        return saved.last.children!.single.offsetRight;
      }

      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      expect(await dragRightEdge(123), closeTo(123, 0.01));

      await undo(tester);
      await toggleGrid(tester);
      await selectAll(tester);
      expect(await dragRightEdge(123), closeTo(120, 0.01));
    });
  });

  group('слои за краем холста', () {
    Clip canvasClip(WidgetTester tester) =>
        tester
            .widget<Stack>(find.byKey(const ValueKey('stack_children_layer')))
            .clipBehavior;

    Future<void> toggleOutside(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('sheet_outside_switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('sheet_outside_switch')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await closeSheet(tester);
    }

    testWidgets('по умолчанию холст режет так же, как плеер', (tester) async {
      await pumpCanvas(tester, stack: _stackOutside());
      expect(canvasClip(tester), Clip.hardEdge);
    });

    testWidgets('переключатель рисует слой за краем и не правит документ', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackOutside());
      await toggleOutside(tester);

      expect(canvasClip(tester), Clip.none);
      expect(saved, isEmpty, reason: 'это настройка вида, не правка стека');
    });
  });

  group('линейка не прячет слои', () {
    // Окна в подложке полосы живущие в приватном painter'е: читаем через
    // dynamic. На коде без правки поля нет, и тест падает на чтении.
    List<Rect> rulerWindows(WidgetTester tester, {required bool vertical}) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(
            ValueKey(vertical ? 'ruler_vertical' : 'ruler_horizontal'),
          ),
          matching: find.byType(CustomPaint),
        ),
      ).painter! as dynamic;
      return paint.contentGaps as List<Rect>;
    }

    double canvasScale(WidgetTester tester) =>
        tester.getRect(
          find.byKey(const ValueKey('canvas_edge_handle')),
        ).width /
        kStackCanvasWidth;

    testWidgets('слой у края получает окно в полосе линейки', (tester) async {
      await pumpCanvas(tester, stack: _stackAtEdge());
      final scale = canvasScale(tester);

      final windows = rulerWindows(tester, vertical: true);
      // По x полоса занята целиком (слой 100 px шире полосы), по y остаётся
      // за вычетом уголка горизонтальной линейки.
      expect(windows, hasLength(1));
      expect(windows.single.left, closeTo(0, .01));
      expect(windows.single.width, closeTo(kStackRulerThickness, .01));
      expect(
        windows.single.height,
        closeTo(40 * scale - kStackRulerThickness, .5),
      );

      // Горизонтальная линейка получает то же самое по своей оси.
      final wide = rulerWindows(tester, vertical: false);
      expect(wide, hasLength(1));
      expect(wide.single.top, closeTo(0, .01));
      expect(wide.single.height, closeTo(kStackRulerThickness, .01));
    });

    testWidgets('пустой край линейка держит плотной подложкой', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackAtEdge(left: 300, top: 100));

      expect(rulerWindows(tester, vertical: true), isEmpty);
      expect(rulerWindows(tester, vertical: false), isEmpty);
    });
  });

  group('инспектор точных значений', () {
    Finder field(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(TextField));

    String fieldText(WidgetTester tester, String label) =>
        tester.widget<TextField>(field(label)).controller!.text;

    Future<void> openProps(WidgetTester tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester, String label, String value) async {
      await tester.enterText(field(label), value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    testWidgets('поля взяты из реального rect объекта', (tester) async {
      await openProps(tester);

      expect(fieldText(tester, 'X'), '16');
      expect(fieldText(tester, 'Y'), '8');
      expect(fieldText(tester, 'Ширина'), '100');
      expect(fieldText(tester, 'Высота'), '40');
    });

    testWidgets(
      'X и Y — отдельные шаги истории, уход из поля шага не добавляет',
      (tester) async {
        await openProps(tester);

        await submit(tester, 'X', '200');
        expect(saved.length, 1);
        expect(saved.last.children!.single.offsetLeft, 200);

        // Тап по полю Y снимает фокус с X — вторая «правка» тем же значением
        // не должна ложиться в историю.
        await submit(tester, 'Y', '30');
        expect(saved.length, 2, reason: 'одна правка поля — одна запись');
        expect(saved.last.children!.single.offsetRight, 200 + 100);

        await closeSheet(tester);
        await undo(tester);
        final child = saved.last.children!.single;
        expect(child.offsetTop, 8, reason: 'отменился только шаг по Y');
        expect(child.offsetLeft, 200, reason: 'X остаётся как был');
      },
    );

    testWidgets('размер не сжимается в нуль, мусор откатывается', (
      tester,
    ) async {
      await openProps(tester);

      await submit(tester, 'Ширина', '2');
      expect(
        fieldText(tester, 'Ширина'),
        '8',
        reason: 'в поле показываем то, что реально записалось',
      );
      expect(saved.last.children!.single.offsetRight, 16 + 8);

      saved.clear();
      await submit(tester, 'X', '-');
      expect(saved, isEmpty, reason: 'непарсящееся значение — не правка');
      expect(fieldText(tester, 'X'), '16');
    });
  });

  group('холст и фон стека', () {
    Finder field(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(TextField));

    String fieldText(WidgetTester tester, String label) =>
        tester.widget<TextField>(field(label)).controller!.text;

    Future<void> submit(WidgetTester tester, String label, String value) async {
      await tester.enterText(field(label), value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    Future<void> openCanvasProps(WidgetTester tester) async {
      await pumpCanvas(tester);
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('поле высоты берётся из реального холста', (tester) async {
      await openCanvasProps(tester);

      expect(fieldText(tester, 'Высота холста'), '240');
      expect(fieldText(tester, 'Скругление'), '', reason: 'скругления нет');
      // Без выделения детей инспектор объекта не открывается — здесь только
      // документные свойства.
      expect(find.text('Ширина'), findsNothing);
    });

    testWidgets('высота пишется в документ, уход из поля шага не добавляет', (
      tester,
    ) async {
      await openCanvasProps(tester);

      await submit(tester, 'Высота холста', '400');
      expect(saved.length, 1);
      expect(saved.last.stackHeight, 400);
      // Дети привязаны к верхнему левому якорю — при смене высоты они
      // остаются там же, где лежали.
      expect(saved.last.children!.first.offsetTop, 8);

      await closeSheet(tester);
      expect(saved.length, 1, reason: 'потеря фокуса после Enter — не правка');

      await undo(tester);
      expect(saved.last.stackHeight, 240);
    });

    testWidgets('холст не сжимается в нить и не растягивается в простыню', (
      tester,
    ) async {
      await openCanvasProps(tester);

      await submit(tester, 'Высота холста', '20');
      expect(
        fieldText(tester, 'Высота холста'),
        '60',
        reason: 'в поле показываем то, что записалось',
      );
      expect(saved.last.stackHeight, 60);

      await submit(tester, 'Высота холста', '99999');
      // Потолок — тот же, что у модели/плеера: редактор не имеет права
      // обещать одно поле, а писать другое.
      expect(fieldText(tester, 'Высота холста'), '4000');
      expect(saved.last.stackHeight, kStackCanvasHeightMax);

      saved.clear();
      await submit(tester, 'Высота холста', '-');
      expect(saved, isEmpty);
      expect(fieldText(tester, 'Высота холста'), '4000');
    });

    testWidgets('холст тянется за нижний край и край идёт под пальцем', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final handle = find.byKey(const ValueKey('canvas_edge_handle'));

      final g = await tester.startGesture(tester.getCenter(handle));
      // Первый ход уходит на порог жеста — дальше сравниваем уже приращения.
      await g.moveBy(const Offset(0, 30));
      await tester.pump();
      final mid = tester.getCenter(handle);
      await g.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(
        tester.getCenter(handle).dy - mid.dy,
        closeTo(40, 0.6),
        reason:
            'FittedBox вписывает холст по ширине — тяга компенсирует это 2×',
      );
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(saved.length, 1, reason: 'жест — одна правка');
      expect(saved.last.stackHeight, greaterThan(240));
      expect(
        saved.last.children!.first.offsetTop,
        8,
        reason: 'верхний якорь: объект при своём',
      );

      await undo(tester);
      expect(saved.last.stackHeight, 240);
    });

    testWidgets('холст тянется за правый край: ширина в документе и плашка', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final handle = find.byKey(const ValueKey('canvas_right_handle'));

      final g = await tester.startGesture(tester.getCenter(handle));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      // Холст вписан по ширине, поэтому край прижат к вьюпорту и не едет:
      // обратную связь даёт плашка с размерами.
      expect(find.byKey(const ValueKey('canvas_size_badge')), findsOneWidget);
      expect(
        find.widgetWithText(Text, '720 × 240 px'),
        findsNothing,
        reason: 'на раста — не исходный размер',
      );
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('canvas_size_badge')), findsNothing);
      expect(saved.length, 1, reason: 'жест — одна правка');
      expect(saved.last.stackWidth, greaterThan(kStackCanvasWidth));

      await undo(tester);
      expect(
        saved.last.stackWidth ?? kStackCanvasWidth,
        kStackCanvasWidth,
        reason: 'отмена возвращает проектную ширину: null — она и есть 720',
      );
    });

    testWidgets('когда холст вписан по высоте, правый край идёт под пальцем', (
      tester,
    ) async {
      // Высокий стек: FittedBox выбирает масштаб по высоте, по бокам остаются
      // поля, и край может двигаться.
      await pumpCanvas(
        tester,
        stack: _stack(stackHeight: 1200),
      );
      final handle = find.byKey(const ValueKey('canvas_right_handle'));

      final g = await tester.startGesture(tester.getCenter(handle));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      final mid = tester.getCenter(handle);
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(
        tester.getCenter(handle).dx - mid.dx,
        closeTo(40, 0.8),
        reason: 'край догоняет палец 1:1',
      );
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(saved.last.stackWidth, greaterThan(kStackCanvasWidth));
    });

    testWidgets('зона отсечки помечена, но указатель через неё проходит', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      expect(find.byKey(const ValueKey('canvas_cut_overlay')), findsOneWidget);

      await selectAll(tester);
      expect(find.textContaining('ещё 2'), findsOneWidget);

      // Полоса над холстом — как раз та, что рисует «здесь обрежется». Тап
      // по ней должен работать как тап по пустому месту, а не упираться в
      // оверлей.
      final canvasTop = tester
          .getTopLeft(find.byKey(const ValueKey('canvas_right_handle')))
          .dy;
      await tester.tapAt(Offset(400, canvasTop - 30));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.textContaining('ещё 2'),
        findsNothing,
        reason: 'выделение снялось: оверлей не съел тап',
      );
    });

    testWidgets('escape бросает тягу холста без правки', (tester) async {
      await pumpCanvas(tester);
      final handle = find.byKey(const ValueKey('canvas_edge_handle'));
      final start = tester.getCenter(handle);

      final g = await tester.startGesture(start);
      await g.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(tester.getCenter(handle).dy, greaterThan(start.dy));

      await press(tester, LogicalKeyboardKey.escape);
      expect(tester.getCenter(handle).dy, closeTo(start.dy, 0.5));
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(saved, isEmpty, reason: 'брошенный жест в историю не попадает');
    });

    testWidgets('скругление ставится и снимается пустым полем', (tester) async {
      await openCanvasProps(tester);

      await submit(tester, 'Скругление', '12');
      expect(saved.last.borderRadius, 12);

      await submit(tester, 'Скругление', '');
      expect(saved.last.borderRadius, null);
      expect(fieldText(tester, 'Скругление'), '');

      // Повторный уход из пустого поля — новая правки нет.
      final depth = saved.length;
      await submit(tester, 'Скругление', '');
      expect(saved.length, depth);
    });

    testWidgets('фон стека: кнопка «убрать» появляется только у цвета', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        stack: _stack().copyWith(backgroundColor: const Color(0x14000000)),
      );
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pumpAndSettle();

      // Шит длинный: после ряда чипов масштаба кнопка уезжает за нижний край
      // тестового окна, а тап мимо цели правку не делает.
      await tester.ensureVisible(find.text('убрать'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('убрать'));
      await tester.pump();
      expect(saved.last.backgroundColor, null);
      expect(find.text('убрать'), findsNothing, reason: 'цвета больше нет');

      await closeSheet(tester);
      await undo(tester);
      expect(saved.last.backgroundColor, const Color(0x14000000));
    });
  });

  group('масштаб содержимого из шита', () {
    // Выбор режима живёт в сессии редактора, в документ не пишется: шит
    // открывается с «только рамка», а слои едут за холстом, если автор сам
    // попросил пропорции.
    Finder widthField() => find.ancestor(
      of: find.text('Ширина холста'),
      matching: find.byType(TextField),
    );

    Future<void> openProps(WidgetTester tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pumpAndSettle();
    }

    Future<void> pickMode(WidgetTester tester, String mode) async {
      final chip = find.byKey(ValueKey('sheet_content_scale_$mode'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    Future<void> setWidth(WidgetTester tester, String value) async {
      await tester.enterText(widthField(), value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    testWidgets('по умолчанию меняется рамка, слой остаётся', (tester) async {
      await openProps(tester);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('sheet_content_scale_keep')),
            )
            .selected,
        isTrue,
      );

      await setWidth(tester, '360');
      expect(saved.last.stackWidth, 360);
      expect(saved.last.children!.single.offsetLeft, 16);
    });

    testWidgets('пропорционально уводит слой вместе с рамкой', (tester) async {
      await openProps(tester);
      await pickMode(tester, 'uniform');
      await setWidth(tester, '360');

      final a = saved.last.children!.single;
      expect(
        a.stackChildRect(360, 240),
        const Rect.fromLTWH(8, 4, 50, 20),
        reason: 'слой 16,8..116,48 в холсте 360 — вдвое',
      );
      expect(saved.last.stackWidth, 360);

      await closeSheet(tester);
      await undo(tester);
      expect(
        saved.last.children!.single.stackChildRect(720, 240).left,
        16,
        reason: 'отмена возвращает и холст, и слой',
      );
    });
  });

  group('курсоры и наведение', () {
    // Центр объекта 'a' и пустое место канваса в экранных координатах:
    // масштаб 1.111 и сдвиг по y — следствие того, как стек вписался в окно.
    const overObject = Offset(73, 226);
    const overBackground = Offset(445, 417);

    /// Мышь в тесте — отдельный указатель, который ведём по канвасу: hover
    /// приходит только от мышиного устройства, палец его не генерирует.
    Future<TestGesture> mouse(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(400, 560));
      addTearDown(gesture.removePointer);
      await tester.pump();
      return gesture;
    }

    MouseCursor canvasCursor(WidgetTester tester) => tester
        .widget<MouseRegion>(find.byKey(const ValueKey('stack_canvas_input')))
        .cursor;

    // У каждой ручки свой MouseRegion: по ключу «cursor_…» его найти проще,
    // чем разбираться, кто из них родитель, а кто ребёнок.
    MouseCursor handleCursor(WidgetTester tester, String key) =>
        tester.widget<MouseRegion>(find.byKey(ValueKey('cursor_$key'))).cursor;

    testWidgets('объект под курсором обводится и просит курсор перемещения', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      expect(find.byKey(const ValueKey('stack_overlay')), findsNothing);
      expect(canvasCursor(tester), SystemMouseCursors.basic);

      final pointer = await mouse(tester);
      await pointer.moveTo(overObject);
      await tester.pump();
      expect(find.byKey(const ValueKey('stack_overlay')), findsOneWidget);
      expect(canvasCursor(tester), SystemMouseCursors.move);

      await pointer.moveTo(overBackground);
      await tester.pump();
      expect(find.byKey(const ValueKey('stack_overlay')), findsNothing);
      expect(canvasCursor(tester), SystemMouseCursors.basic);
    });

    testWidgets('в режиме рамки курсор — прицел', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await press(tester, LogicalKeyboardKey.keyM);
      final pointer = await mouse(tester);
      await pointer.moveTo(overBackground);
      await tester.pump();
      expect(canvasCursor(tester), SystemMouseCursors.precise);
    });

    testWidgets('ручка ресайза показывает направление тяги', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      expect(
        handleCursor(tester, 'handle_a-resizeLeft'),
        SystemMouseCursors.resizeLeftRight,
      );
      expect(
        handleCursor(tester, 'handle_a-resizeRight'),
        SystemMouseCursors.resizeLeftRight,
      );
      expect(
        handleCursor(tester, 'handle_a-resizeTop'),
        SystemMouseCursors.resizeUpDown,
      );
      expect(
        handleCursor(tester, 'handle_a-resizeBottom'),
        SystemMouseCursors.resizeUpDown,
      );
      expect(
        handleCursor(tester, 'handle_a-resizeTL'),
        SystemMouseCursors.resizeUpLeftDownRight,
      );
      expect(
        handleCursor(tester, 'handle_a-resizeBR'),
        SystemMouseCursors.resizeUpLeftDownRight,
      );
      expect(
        handleCursor(tester, 'handle_a-resizeTR'),
        SystemMouseCursors.resizeUpRightDownLeft,
      );
      expect(
        handleCursor(tester, 'handle_a-resizeBL'),
        SystemMouseCursors.resizeUpRightDownLeft,
      );
      expect(handleCursor(tester, 'rotate_handle_a'), SystemMouseCursors.grab);
    });

    testWidgets('у ручек группы те же курсоры', (tester) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);
      expect(
        handleCursor(tester, 'group_handle_resizeBR'),
        SystemMouseCursors.resizeUpLeftDownRight,
      );
    });
  });

  group('группы объектов', () {
    Future<void> pressCombo(
      WidgetTester tester,
      LogicalKeyboardKey key,
      List<LogicalKeyboardKey> modifiers,
    ) async {
      for (final m in modifiers) {
        await tester.sendKeyDownEvent(m, physicalKey: physOf(m));
      }
      await tester.sendKeyEvent(key);
      for (final m in modifiers.reversed) {
        await tester.sendKeyUpEvent(m, physicalKey: physOf(m));
      }
      await tester.pump();
    }

    ContentItem child(List<ContentItem> children, String id) =>
        children.firstWhere((c) => c.id == id);

    Future<void> openPanel(WidgetTester tester) async {
      await tester.tap(
        find.byTooltip(
          'Панель слоёв: z-порядок (долгое нажатие на строку), '
          'видимость, замок, выбор',
        ),
      );
      await tester.pump();
    }

    Future<void> groupAll(WidgetTester tester) => pressCombo(
      tester,
      LogicalKeyboardKey.keyG,
      [LogicalKeyboardKey.controlLeft],
    );

    testWidgets('Ctrl+G пишет имя группы, Ctrl+Shift+G стирает', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);

      await groupAll(tester);
      var savedChildren = saved.last.children!;
      expect(child(savedChildren, 'a').groupName, 'Группа 1');
      expect(child(savedChildren, 'b').groupName, 'Группа 1');
      expect(child(savedChildren, 'c').groupName, 'Группа 1');
      expect(undoButton(tester)?.tooltip, contains('группировка'));

      await pressCombo(tester, LogicalKeyboardKey.keyG, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ]);
      savedChildren = saved.last.children!;
      expect(child(savedChildren, 'a').groupName, isNull);
      expect(undoButton(tester)?.tooltip, contains('разгруппировка'));

      await undo(tester);
      expect(child(saved.last.children!, 'c').groupName, 'Группа 1');
    });

    testWidgets('выделение из одного слоя группу не делает', (tester) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));
      final before = saved.length;

      await groupAll(tester);
      expect(
        saved.length,
        before,
        reason: 'одна кнопка Ctrl+G не должна даже дёргать автосейв',
      );
    });

    testWidgets('тап по слою берёт всю группу, стрелка ведёт её целиком', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackGrouped());
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('ещё 1'),
        findsOneWidget,
        reason: 'клик по a тянет b — группа выделяется целиком',
      );
      expect(
        find.textContaining('Группа 1 ·'),
        findsOneWidget,
        reason: 'в статусе видно, какой группой он правит',
      );

      await press(tester, LogicalKeyboardKey.arrowRight);
      final moved = saved.last.children!;
      expect(child(moved, 'a').offsetLeft, 17);
      expect(child(moved, 'b').offsetLeft, 201);
      expect(
        child(moved, 'c').offsetLeft,
        340,
        reason: 'c вне группы — остался на месте',
      );
    });

    testWidgets('кнопки группы на панели выравнивания', (tester) async {
      await pumpCanvas(tester, stack: _stackGrouped());
      // Тап по a берёт всю группу: и сгруппировать ещё раз есть что, и
      // разгруппировать есть что.
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        buttonOf(tester, Icons.group_rounded)?.onPressed,
        isNotNull,
        reason: 'в выделении два слоя — группировать можно',
      );
      expect(buttonOf(tester, Icons.group_off_rounded)?.onPressed, isNotNull);

      await tester.tap(find.byIcon(Icons.group_rounded));
      await tester.pump(const Duration(milliseconds: 400));
      final grouped = saved.last.children!;
      expect(child(grouped, 'a').groupName, 'Группа 2');
      expect(child(grouped, 'b').groupName, 'Группа 2');
      expect(child(grouped, 'c').groupName, isNull);

      // Группа теперь одна на весь стек — кнопка разгруппировки активна.
      await tester.tap(find.byIcon(Icons.group_off_rounded));
      await tester.pump(const Duration(milliseconds: 400));
      expect(child(saved.last.children!, 'a').groupName, isNull);
    });

    testWidgets('панель слоёв подписывает группы', (tester) async {
      await pumpCanvas(tester, stack: _stackGrouped());
      await openPanel(tester);
      expect(find.text('Группа 1'), findsNWidgets(2));
    });

    testWidgets('имя группы правится из панели выравнивания', (tester) async {
      await pumpCanvas(tester, stack: _stackGrouped());
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byTooltip('Переименовать группу'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Шапка');
      await tester.tap(find.text('Переименовать'));
      await tester.pumpAndSettle();

      final renamed = saved.last.children!;
      expect(child(renamed, 'a').groupName, 'Шапка');
      expect(child(renamed, 'b').groupName, 'Шапка');
      expect(child(renamed, 'c').groupName, isNull);
      expect(undoButton(tester)?.tooltip, contains('имя группы'));

      await openPanel(tester);
      expect(
        find.text('Шапка'),
        findsNWidgets(2),
        reason: 'подписи слоёв следуют за новым именем',
      );
    });

    testWidgets('долгое нажатие на слой даёт меню правок', (tester) async {
      await pumpCanvas(tester, stack: _stackGrouped());
      await tester.longPressAt(const Offset(73, 226));
      await tester.pumpAndSettle();

      expect(find.text('Переименовать слой'), findsOneWidget);
      expect(find.text('Скрыть слой'), findsOneWidget);
      expect(find.text('Заблокировать'), findsOneWidget);
      expect(
        find.text('Разгруппировать'),
        findsOneWidget,
        reason: 'слой в группе — в меню есть что разгруппировать',
      );

      await tester.tap(find.text('Скрыть слой'));
      await tester.pumpAndSettle();
      expect(child(saved.last.children!, 'a').isHidden, isTrue);
      expect(undoButton(tester)?.tooltip, contains('видимость'));
    });

    testWidgets('из меню слой переименовывают и разгруппируют', (tester) async {
      await pumpCanvas(tester, stack: _stackGrouped());
      await tester.longPressAt(const Offset(73, 226));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переименовать слой'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Шапка');
      await tester.tap(find.text('Переименовать'));
      await tester.pumpAndSettle();
      expect(child(saved.last.children!, 'a').layerName, 'Шапка');

      await tester.longPressAt(const Offset(73, 226));
      await tester.pumpAndSettle();
      // Меню скроллится, а не разваливается на две страницы — до нижних
      // пунктов надо дотянуться.
      await tester.ensureVisible(find.text('Разгруппировать'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Разгруппировать'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(undoButton(tester)?.tooltip, contains('разгруппировка'));
      expect(child(saved.last.children!, 'a').groupName, isNull);
      expect(
        child(saved.last.children!, 'b').groupName,
        isNull,
        reason: 'разгруппировка снимает имя со всей группы',
      );
      // Имя слоя — редакторское, группировка его не трогает.
      expect(child(saved.last.children!, 'a').layerName, 'Шапка');
    });
  });

  group('шпаргалка горячих клавиш', () {
    testWidgets('открывается из AppBar, до нижних строк есть скролл', (
      tester,
    ) async {
      await pumpCanvas(tester);
      await tester.tap(find.byTooltip('Горячие клавиши'));
      await tester.pumpAndSettle();

      expect(find.text('Горячие клавиши канваса'), findsOneWidget);
      expect(find.text('Ctrl+G'), findsOneWidget);
      expect(find.text('Alt+рамка'), findsOneWidget);
      expect(
        find.text('ручка низа холста'),
        findsOneWidget,
        reason: 'новое движение обязано быть в списке, а не только в коде',
      );

      // Список длиннее шита: последняя строка должна доставаться скроллом.
      await tester.ensureVisible(find.text('Ctrl+2'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Ctrl+2')).top, lessThan(600));
    });
  });

  group('направляющие и линейки', () {
    Finder verticalGuides() => find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('guide_x'),
    );

    Future<void> drag(WidgetTester tester, Offset from, Offset total) async {
      final g = await tester.startGesture(from);
      // Первый ход уходит на порог жеста, поэтому движение делим надвое.
      await g.moveBy(total / 2);
      await tester.pump();
      await g.moveBy(total / 2);
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('направляющую вытягивают из линейки — это одна правка', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final ruler = find.byKey(const ValueKey('ruler_vertical'));
      expect(ruler, findsOneWidget);
      expect(find.byKey(const ValueKey('ruler_horizontal')), findsOneWidget);

      final band = tester.getRect(ruler);
      await drag(
        tester,
        Offset(band.left + 9, band.top + 40),
        const Offset(140, 0),
      );

      expect(saved.length, 1, reason: 'жест — одна запись истории');
      final placed = saved.last.guidesX;
      expect(placed, hasLength(1));
      expect(placed!.single, greaterThan(60));
      expect(placed.single, lessThan(kStackCanvasWidth));

      await undo(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(saved.last.guidesX, anyOf(isNull, isEmpty));
    });

    testWidgets('направляную тащат за линию и удаляют возвратом в линейку', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stack().copyWith(guidesX: const [300]));
      expect(verticalGuides(), findsOneWidget);

      await drag(
        tester,
        tester.getCenter(verticalGuides()),
        const Offset(150, 0),
      );
      final moved = saved.last.guidesX!.single;
      expect(moved, greaterThan(300), reason: 'линия уехала вправо');

      final depth = saved.length;
      await drag(
        tester,
        tester.getCenter(verticalGuides()),
        // До левого края окна с запасом: порог жеста съедает часть пути.
        Offset(-(tester.getCenter(verticalGuides()).dx + 60), 0),
      );
      expect(saved.length, greaterThan(depth));
      expect(saved.last.guidesX, anyOf(isNull, isEmpty));
    });

    testWidgets('escape бросает направляную без правки', (tester) async {
      await pumpCanvas(tester);
      final band = tester.getRect(find.byKey(const ValueKey('ruler_vertical')));

      final g = await tester.startGesture(Offset(band.left + 9, band.top + 40));
      await g.moveBy(const Offset(70, 0));
      await tester.pump();
      await g.moveBy(const Offset(70, 0));
      await tester.pump();
      expect(
        verticalGuides(),
        findsOneWidget,
        reason: 'линию видно под курсором',
      );

      await press(tester, LogicalKeyboardKey.escape);
      expect(verticalGuides(), findsNothing);
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(saved, isEmpty, reason: 'брошенный жест в историю не попадает');
    });

    testWidgets('Ctrl+; прячет линейки и не правит документ', (tester) async {
      await pumpCanvas(tester, stack: _stack().copyWith(guidesX: const [300]));
      expect(verticalGuides(), findsOneWidget);

      await press(
        tester,
        LogicalKeyboardKey.semicolon,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(find.byKey(const ValueKey('ruler_vertical')), findsNothing);
      expect(verticalGuides(), findsNothing, reason: 'скрытые линии не мешают');
      expect(saved, isEmpty);

      await press(
        tester,
        LogicalKeyboardKey.semicolon,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(verticalGuides(), findsOneWidget);
    });

    testWidgets('объект под полосой линейки всё равно тянется', (tester) async {
      await pumpCanvas(
        tester,
        stack: _stack().copyWith(children: [_child('a', left: 0, top: 0)]),
      );
      final band = tester.getRect(find.byKey(const ValueKey('ruler_vertical')));
      // Точка внутри полосы линейки и одновременно внутри объекта: линейка —
      // декорация, жест выбирает детектор холста, и объект важнее направляющей.
      final grab = Offset(band.left + 9, band.top + 6);

      final g = await tester.startGesture(grab);
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(saved.length, 1);
      expect(saved.last.children!.single.offsetLeft, greaterThan(0));
    });
  });

  group('замеры при драге', () {
    testWidgets('зазоры рисуются, пока объект на ходу', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      final tl = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeTL')))
          .center;
      final br = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeBR')))
          .center;
      final scale = (br.dx - tl.dx) / 100;
      final from = tl + Offset(50 * scale, 20 * scale);

      final g = await tester.startGesture(from);
      for (var t = 0.1; t <= 1.001; t += 0.1) {
        await g.moveTo(from + Offset(60 * scale * t, 0));
        await tester.pump();
      }
      expect(
        find.byKey(const ValueKey('stack_overlay')),
        findsOneWidget,
        reason: 'слой с замерами живёт всё время драга',
      );
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        saved,
        hasLength(1),
        reason: 'замеры — картинка, а не правка документа',
      );
    });
  });

  group('модификаторы перетаскивания', () {
    /// Протащить единственный объект из центра на [dx]×[dy] пикселей стека.
    /// Модификатор держат весь жест — экран читает его на каждом кадре.
    ///
    /// Распознаватель пускает драг только после 18 px хода, поэтому до цели
    /// доля пути не доезжает: при десяти шагах тяги объект проходит 0.9·dx.
    Future<ContentItem> drag(
      WidgetTester tester, {
      double dx = 0,
      double dy = 0,
      LogicalKeyboardKey? modifier,
    }) async {
      final tl = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeTL')))
          .center;
      final br = tester
          .getRect(find.byKey(const ValueKey('handle_a-resizeBR')))
          .center;
      final scale = (br.dx - tl.dx) / 100;
      final from = tl + Offset(50 * scale, 20 * scale);
      if (modifier != null) {
        await tester.sendKeyDownEvent(modifier, physicalKey: physOf(modifier));
      }
      final g = await tester.startGesture(from);
      for (var t = 0.1; t <= 1.001; t += 0.1) {
        await g.moveTo(from + Offset(dx * scale * t, dy * scale * t));
        await tester.pump();
      }
      await g.up();
      if (modifier != null) {
        await tester.sendKeyUpEvent(modifier, physicalKey: physOf(modifier));
      }
      await tester.pump(const Duration(milliseconds: 400));
      return saved.last.children!.single;
    }

    testWidgets('Shift оставляет движение на длинной оси', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      final right = await drag(
        tester,
        dx: 60,
        dy: 40,
        modifier: LogicalKeyboardKey.shiftLeft,
      );
      expect(right.offsetLeft, closeTo(58, 1), reason: 'горизонталь идёт');
      expect(right.offsetTop, 8, reason: 'палец ушёл и вниз — объект нет');
    });

    testWidgets('Shift: короткая ось не двигается вообще', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      final down = await drag(
        tester,
        dx: 20,
        dy: 60,
        modifier: LogicalKeyboardKey.shiftLeft,
      );
      expect(down.offsetLeft, 16);
      expect(down.offsetTop, closeTo(50, 1));
    });

    testWidgets('Ctrl на ходу отключает прилипание', (tester) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      // 323 px по X ставят центр объекта в 356.7 — три пикселя до середины
      // холста, то есть ровно в пороге прилипания.
      final free = await drag(
        tester,
        dx: 323,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(free.offsetLeft, closeTo(306.7, 1));
    });

    testWidgets('тот же ход без Ctrl дотягивается до середины холста', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      final snapped = await drag(tester, dx: 323);
      expect(snapped.offsetLeft, closeTo(310, 0.01), reason: 'центр на 360');
    });
  });

  group('значок действия у слоя', () {
    // a — скрипт в старом формате, b — в новом, c — переход, d — кнопка
    // перехода (переход в ней не «висит», а является её типом), e — статичный.
    ContentItem stackWired() => ContentItem(
      id: 'stack-1',
      type: 'stack',
      stackHeight: 240,
      children: [
        _child(
          'a',
        ).copyWith(scriptTriggers: const {'onPress': 'scripts/a.json'}),
        _child('b', left: 200, top: 60).copyWith(
          behaviours: const [
            ContentTrigger(event: 'onAppear', script: 'scripts/b.json'),
          ],
        ),
        _child('c', left: 340, top: 120).copyWith(targetNodeId: 'n-2'),
        _child('e', left: 340, top: 180),
      ],
    );

    Future<void> openPanel(WidgetTester tester) async {
      await tester.tap(
        find.byTooltip(
          'Панель слоёв: z-порядок (долгое нажатие на строку), '
          'видимость, замок, выбор',
        ),
      );
      await tester.pump();
    }

    testWidgets('оживлённые слои помечены, статичный — нет', (tester) async {
      await pumpCanvas(tester, stack: stackWired());

      expect(find.byKey(const ValueKey('wiring_a')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('wiring_b')),
        findsOneWidget,
        reason: 'behaviours — тот же смысл, что scriptTriggers',
      );
      expect(
        find.byKey(const ValueKey('wiring_c')),
        findsOneWidget,
        reason: 'переход по тапу тоже действие',
      );
      expect(find.byKey(const ValueKey('wiring_e')), findsNothing);
    });

    // Проверка на жалобу «иконка триггера не едет за кнопкой в стеке».
    // Значок лежит в том же Positioned, что и сам слой, так что он обязан
    // смещаться пиксель в пиксель с уголком слоя — сравниваем именно эти два
    // смещения, чтобы масштаб превью не врал.
    testWidgets('значок уезжает вместе со слоем', (tester) async {
      await pumpCanvas(
        tester,
        stack: ContentItem(
          id: 'stack-1',
          type: 'stack',
          stackHeight: 240,
          children: [
            _child(
              'a',
            ).copyWith(scriptTriggers: const {'onPress': 'scripts/a.json'}),
          ],
        ),
      );
      await selectAll(tester);

      Offset badge() =>
          tester.getCenter(find.byKey(const ValueKey('wiring_a')));
      Offset corner() =>
          tester.getCenter(find.byKey(const ValueKey('handle_a-resizeBR')));

      final badge0 = badge();
      final corner0 = corner();

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump();

      final dBadge = badge() - badge0;
      final dCorner = corner() - corner0;
      expect(dBadge.dx, greaterThan(0));
      expect(dBadge.dx, closeTo(dCorner.dx, 0.01));
      expect(dBadge.dy, closeTo(dCorner.dy, 0.01));
    });

    // Его жалоба была про перетаскивание: тащим кнопку, а молния осталась на
    // старом месте. Тут жест не пишет в модель, так что единственный источник
    // геометрии — превью жеста; сверяем значок с тем же уголком слоя.
    testWidgets('значок не отстаёт от пальца при перетаскивании', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        stack: ContentItem(
          id: 'stack-1',
          type: 'stack',
          stackHeight: 240,
          children: [
            _child(
              'a',
            ).copyWith(scriptTriggers: const {'onPress': 'scripts/a.json'}),
          ],
        ),
      );
      await selectAll(tester);

      Offset corner() =>
          tester.getCenter(find.byKey(const ValueKey('handle_a-resizeBR')));
      Offset badge() =>
          tester.getCenter(find.byKey(const ValueKey('wiring_a')));
      final tl = tester.getCenter(
        find.byKey(const ValueKey('handle_a-resizeTL')),
      );
      final at = Offset(
        (tl.dx + corner().dx) / 2,
        (tl.dy + corner().dy) / 2,
      );
      final badge0 = badge();
      final corner0 = corner();

      final g = await tester.startGesture(at);
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await g.moveTo(at + const Offset(90, 40) * t);
        await tester.pump();
      }

      final dBadge = badge() - badge0;
      final dCorner = corner() - corner0;
      expect(dCorner.dx, greaterThan(0), reason: 'жест вообще поехал');
      expect(dBadge.dx, closeTo(dCorner.dx, 0.01));
      expect(dBadge.dy, closeTo(dCorner.dy, 0.01));
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('button_jump не маркируется: это и есть переход', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        stack: ContentItem(
          id: 'stack-1',
          type: 'stack',
          stackHeight: 240,
          children: [
            _child('d').copyWith(
              type: 'button_jump',
              targetNodeId: 'n-2',
              buttonText: 'вперёд',
            ),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('wiring_d')), findsNothing);
    });

    testWidgets('пустой слот скрипта значка не даёт', (tester) async {
      await pumpCanvas(
        tester,
        stack: ContentItem(
          id: 'stack-1',
          type: 'stack',
          stackHeight: 240,
          children: [
            _child('a').copyWith(scriptTriggers: const {'onPress': '  '}),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('wiring_a')), findsNothing);
    });

    testWidgets('в панели слоёв подсказка перечисляет действия', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: stackWired());
      await openPanel(tester);

      final tooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('layer_wiring_a')),
      );
      expect(tooltip.message, 'На слое действие: onPress');
      expect(
        find.byKey(const ValueKey('layer_wiring_e')),
        findsNothing,
        reason: 'статичный слой без наложения',
      );
    });
  });

  group('узкое окно телефона', () {
    // 390×720 — типичный телефон. В стандартных 800×600 и панель слоёв, и
    // лента кнопок помещаются, поэтому борьба за пиксели видна только здесь.
    Future<void> pumpPhone(WidgetTester tester, {double width = 390}) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpCanvas(tester, stack: _stackSpread());
    }

    Future<void> openPanel(WidgetTester tester) async {
      await tester.tap(
        find.byTooltip(
          'Панель слоёв: z-порядок (долгое нажатие на строку), '
          'видимость, замок, выбор',
        ),
      );
      await tester.pump();
    }

    testWidgets('строка статуса ужимается в многоточие, а не в столбик', (
      tester,
    ) async {
      await pumpPhone(tester);
      await selectAll(tester);
      await openPanel(tester);
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Row не должен переполняться',
      );
      final status = tester.widget<Text>(find.textContaining('ещё 2').first);
      expect(status.maxLines, 1);
      expect(status.overflow, TextOverflow.ellipsis);
    });

    testWidgets('лента выравнивания скроллится по горизонтали', (tester) async {
      await pumpPhone(tester);
      await selectAll(tester);
      await tester.pump();

      expect(tester.takeException(), isNull);
      final scroller = tester.widget<SingleChildScrollView>(
        find.ancestor(
          of: find.byTooltip('По левому краю'),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(scroller.scrollDirection, Axis.horizontal);
    });

    testWidgets('на 320 px панель берёт не больше 70 %', (tester) async {
      await pumpPhone(tester, width: 320);
      await openPanel(tester);
      await tester.pump();

      // Раньше тут было clamp(180, 160): нижняя граница выше верхней, и
      // ListTile ещё и падал на «хвост съел всю ширину».
      expect(tester.takeException(), isNull);
      final row = tester.getRect(layerTile('a'));
      expect(row.width, lessThanOrEqualTo(320 * 0.7));
      // Подпись слоя должна читаться, а не схлопываться в один знак.
      expect(find.text('a'), findsWidgets);
      expect(row.width, greaterThan(180));
    });
  });

  group('замеры при ресайзе', () {
    testWidgets('свободный край показывает зазоры, даже когда ловить нечего', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      final from = tester.getCenter(
        find.byKey(const ValueKey('handle_a-resizeRight')),
      );

      final g = await tester.startGesture(from);
      for (var t = 0.1; t <= 1.001; t += 0.1) {
        await g.moveTo(from + Offset(120 * t, 0));
        await tester.pump();
      }
      // Единственное, что тут рисуется, — зазоры: сетка выключена,
      // направляющих нет, до соседей и рамки холста далеко.
      expect(
        find.byKey(const ValueKey('stack_overlay')),
        findsOneWidget,
        reason: 'при ресайзе тоже подписываем расстояния',
      );
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(saved.last.children!.single.offsetRight, greaterThan(116));
    });
  });

  group('escape бросает жест', () {
    /// Центр выделенного объекта — из его же ручек, без экранных констант.
    Offset centerOf(WidgetTester tester, String id) {
      final tl = tester
          .getRect(find.byKey(ValueKey('handle_$id-resizeTL')))
          .center;
      final br = tester
          .getRect(find.byKey(ValueKey('handle_$id-resizeBR')))
          .center;
      return Offset((tl.dx + br.dx) / 2, (tl.dy + br.dy) / 2);
    }

    Future<void> hold(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      required bool down,
    }) => down
        ? tester.sendKeyDownEvent(key, physicalKey: physOf(key))
        : tester.sendKeyUpEvent(key, physicalKey: physOf(key));

    testWidgets('драг объекта: объект и холст остаются на месте', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);
      final from = centerOf(tester, 'a');

      final g = await tester.startGesture(from);
      for (var t = 0.1; t <= 1.001; t += 0.1) {
        await g.moveTo(from + Offset(200 * t, 0));
        await tester.pump();
      }
      await press(tester, LogicalKeyboardKey.escape);
      final placed = tester.getRect(
        find.byKey(const ValueKey('handle_a-resizeTL')),
      );

      // Палец ещё двигается: эти кадры не должны уехать ни в объект, ни в
      // панораму холста.
      await g.moveTo(from + const Offset(260, 60));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(saved, isEmpty, reason: 'брошенный драг — не правка документа');
      expect(
        tester.getRect(find.byKey(const ValueKey('handle_a-resizeTL'))),
        placed,
        reason: 'остаток жеста ничего не сдвинул',
      );
      expect(
        ribbonField(tester, 'x'),
        '16',
        reason: 'выделение живёт и после отмены',
      );
      expect(ribbonField(tester, 'y'), '8');
    });

    testWidgets('alt-драг: брошенная копия исчезает, оригинал выделяется', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      // Центр 'a' — экранная (73, 226).
      await tester.tapAt(const Offset(73, 226));
      await tester.pump(const Duration(milliseconds: 400));
      final from = centerOf(tester, 'a');

      await hold(tester, LogicalKeyboardKey.altLeft, down: true);
      final g = await tester.startGesture(from);
      for (var t = 0.1; t <= 1.001; t += 0.1) {
        await g.moveTo(from + Offset(150 * t, 0));
        await tester.pump();
      }
      await press(tester, LogicalKeyboardKey.escape);
      await g.moveTo(from + const Offset(220, 0));
      await tester.pump();
      await g.up();
      await hold(tester, LogicalKeyboardKey.altLeft, down: false);
      await tester.pump(const Duration(milliseconds: 400));

      expect(saved.last.children!.map((c) => c.id), [
        'a',
        'b',
        'c',
      ], reason: 'копии были превью жеста и ушли вместе с ним');
      await selectAll(tester);
      expect(
        find.textContaining('ещё 2'),
        findsOneWidget,
        reason: 'на канвасе снова три слоя, не четыре',
      );
    });

    testWidgets('рамка выделения: она исчезает, выделение остаётся', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackSpread());
      await selectAll(tester);
      await press(tester, LogicalKeyboardKey.keyM);

      // Свободное место канваса — stack (400, 200).
      final g = await tester.startGesture(const Offset(445, 417));
      await g.moveTo(const Offset(500, 430));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('stack_overlay')),
        findsOneWidget,
        reason: 'рамка рисуется',
      );

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('stack_overlay')), findsNothing);

      await g.moveTo(const Offset(560, 470));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(saved, isEmpty, reason: 'брошенная рамка — не правка');
      expect(find.textContaining('ещё 2'), findsOneWidget);
    });
  });

  group('эргономика вёрстки', () {
    testWidgets('двойной тап по пустому месту добавляет слой туда', (
      tester,
    ) async {
      await pumpCanvas(tester);
      // Полоса ручки лежит на нижнем крае холста и равна ему по ширине — из
      // неё и достаём масштаб с началом координат, чтобы не зашивать экранные
      // пиксели под конкретное окно теста.
      final band = tester.getRect(
        find.byKey(const ValueKey('canvas_edge_handle')),
      );
      final scale = band.width / kStackCanvasWidth;
      final origin = Offset(band.left, band.center.dy - 240 * scale);
      Offset atStack(double x, double y) =>
          origin + Offset(x * scale, y * scale);

      final at = atStack(400, 150);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      final row = find.text('Строка (Сетка)');
      expect(
        row,
        findsWidgets,
        reason: 'второе нажатие открывает меню добавления',
      );
      await tester.tap(row.first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));

      expect(saved.last.children!.length, 3);
      final rect = saved.last.children!.last.stackChildRect(
        kStackCanvasWidth,
        240,
      );
      expect(rect.center.dx, closeTo(400, 1), reason: 'слой лёг под тап');
      expect(rect.center.dy, closeTo(150, 1));
    });

    testWidgets('двойной тап вне холста слой не добавляет', (tester) async {
      // Янтарная зона за границей — не холст: точка в документ влезть не
      // может, и меню добавления там открывать нечего.
      await pumpCanvas(tester);
      final band = tester.getRect(
        find.byKey(const ValueKey('canvas_edge_handle')),
      );
      final scale = band.width / kStackCanvasWidth;
      final canvasTop = band.center.dy - 240 * scale;
      final at = Offset(band.center.dx, canvasTop - 40);

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(find.text('Строка (Сетка)'), findsNothing);
      expect(saved, isEmpty);
    });

    testWidgets('выравнивание знает фактическую ширину холста', (
      tester,
    ) async {
      // Кастомный холст 400 px: без явной ширины лента выравнивания считала
      // рамку проектной (720) и «по правому краю» уводила слой за отсечку.
      await pumpCanvas(
        tester,
        stack: ContentItem(
          id: 'stack-1',
          type: 'stack',
          stackWidth: 400,
          stackHeight: 240,
          children: [_child('a')],
        ),
      );
      final band = tester.getRect(
        find.byKey(const ValueKey('canvas_edge_handle')),
      );
      final scale = band.width / 400;
      final origin = Offset(band.left, band.center.dy - 240 * scale);
      // Слой 'a' занимает stack (16, 8)…(116, 48).
      await tester.tapAt(origin + const Offset(66, 28) * scale);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byIcon(Icons.align_horizontal_right));
      await tester.pump(const Duration(milliseconds: 400));

      final a = saved.last.children!.single;
      expect(a.stackChildRect(400, 240).right, closeTo(400, 0.5));
    });

    testWidgets('поля геометрии в шапке идут за жестом', (tester) async {
      // Раньше в шапке лежала геометрия из модели: во время тяги цифры стояли
      // на месте, и выставить слой «на 120 px правее» по глазам было нельзя —
      // только тащить и смотреть, что записалось.
      await pumpCanvas(tester, stack: _stackSingle());
      final band = tester.getRect(
        find.byKey(const ValueKey('canvas_edge_handle')),
      );
      final scale = band.width / kStackCanvasWidth;
      final origin = Offset(band.left, band.center.dy - 240 * scale);
      final at = origin + const Offset(66, 28) * scale;

      double liveLeft() => double.parse(ribbonField(tester, 'x'));

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
      expect(ribbonField(tester, 'x'), '16');
      expect(ribbonField(tester, 'w'), '100');

      final g = await tester.startGesture(at);
      for (double t = 0.1; t <= 1.001; t += 0.1) {
        await g.moveTo(at + const Offset(120, 0) * scale * t);
        await tester.pump();
      }

      final moved = liveLeft();
      expect(moved, greaterThan(16), reason: 'x поехал за жестом');
      expect(
        ribbonField(tester, 'y'),
        '8',
        reason: 'тяга была по горизонтали — y не меняется',
      );

      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      final committed = saved.last.children!.single.stackChildRect(
        kStackCanvasWidth,
        240,
      ).left;
      expect(
        moved,
        closeTo(committed, 1),
        reason: 'цифры в превью равны тому, что легло в документ',
      );
      expect(liveLeft(), closeTo(committed, 1));
    });

    testWidgets('ввод координаты в поле шапки двигает слой без шита', (
      tester,
    ) async {
      // Слой один — холст под ногами, и лезть в модалку свойств, чтобы
      // поставить x=300, незачем.
      await pumpCanvas(tester, stack: _stackSingle());
      await selectAll(tester);

      await tester.enterText(
        find.byKey(const ValueKey('rect_field_x')),
        '300',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 400));

      final child = saved.last.children!.single;
      expect(child.offsetLeft, 300);
      expect(ribbonField(tester, 'x'), '300');
      expect(
        find.byIcon(Icons.tune_rounded),
        findsOneWidget,
        reason: 'кнопка свойств осталась — стили правятся там',
      );
    });
  });

  group('повёрнутый объект на канвасе', () {
    // Слой 100×40 под 90° стоит на боку: картинка занимает stack
    // x∈[46,86], y∈[−22,78], а её модельный rect остался
    // x∈[16,116], y∈[8,48]. До правки ручки, обводка и тап жили в модельном
    // rect'е — то есть мимо того, что автор видит на канвасе.
    Map<String, Offset> cornerCenters(WidgetTester tester) => {
      for (final m in const ['TL', 'TR', 'BR', 'BL'])
        m: tester.getRect(find.byKey(ValueKey('handle_a-resize$m'))).center,
    };

    /// Калибровка stack → экран по полоске края холста: она лежит ровно на
    /// нижней границе и равна холсту по ширине, поэтому экранные пиксели под
    /// конкретное окно теста зашивать не нужно.
    Offset Function(double x, double y) atStack(WidgetTester tester) {
      final band = tester.getRect(
        find.byKey(const ValueKey('canvas_edge_handle')),
      );
      final scale = band.width / kStackCanvasWidth;
      final origin = Offset(band.left, band.center.dy - 240 * scale);
      return (x, y) => origin + Offset(x * scale, y * scale);
    }

    testWidgets('ручки стоят на углах картинки, а не модельного rect’а', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackRotated());
      await selectAll(tester);
      final at = atStack(tester);
      final got = cornerCenters(tester);

      // Угол TL уходит туда, куда его поворачивает (x, y) → (−y, x) вокруг
      // центра (66, 28) — это верхний правый угол картинного бокса.
      expect(got['TL'], nearOffset(at(86, -22)), reason: 'TL ↔ (86, −22)');
      expect(got['TR'], nearOffset(at(86, 78)), reason: 'TR ↔ (86, 78)');
      expect(got['BR'], nearOffset(at(46, 78)), reason: 'BR ↔ (46, 78)');
      expect(got['BL'], nearOffset(at(46, -22)), reason: 'BL ↔ (46, −22)');

      // Тот же тест как отрицательный контроль: до правки ручки сидели на
      // углах модельного rect'а, а они от поворота не двигаются.
      expect(got['TL'], isNot(nearOffset(at(16, 8))));
    });

    testWidgets('тап по видимой картинке вне модельного rect’а выделяет слой', (
      tester,
    ) async {
      await pumpCanvas(tester, stack: _stackRotated());
      final at = atStack(tester);
      expect(
        find.byKey(const ValueKey('rotate_handle_a')),
        findsNothing,
        reason: 'сначала ничего не выделено',
      );

      // Stack (66, 60): низ картинки, но ниже модельного rect'а — он
      // кончается на y = 48. Старый hit-test бил именно по нему.
      await tester.tapAt(at(66, 60));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byKey(const ValueKey('rotate_handle_a')),
        findsOneWidget,
        reason: 'выделен слой a по тапу в картинку',
      );
    });

    testWidgets('тяга за угол растит собственную ось объекта, а не ось экрана', (
      tester,
    ) async {
      // Отрицательный контроль: до правки экранная тяга «вниз» добавляла
      // высоту, потому что resize не знал про поворот.
      await pumpCanvas(tester, stack: _stackRotated());
      await selectAll(tester);

      final br = cornerCenters(tester)['BR']!;
      final gesture = await tester.startGesture(br);
      for (double t = 0.25; t <= 1.001; t += 0.25) {
        await gesture.moveTo(br + const Offset(0, 55));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      final child = saved.last.children!.single;
      final rect = child.stackChildRect(kStackCanvasWidth, 240);
      expect(
        rect.height,
        closeTo(40, 1),
        reason: 'объект лежит на боку: вертикаль экрана — не его ось',
      );
      expect(rect.width, greaterThan(120), reason: 'высота ушла в ширину');
      expect(child.rotation, 90, reason: 'поворот не сбросился');
    });
  });
}
