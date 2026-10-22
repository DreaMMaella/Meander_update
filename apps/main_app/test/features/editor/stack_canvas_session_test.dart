// Сессия редактирования стека: снимки, отмена/повтор, склейка мелких шагов,
// групповые правки и выделение по id. Экран канваса — только гесты поверх
// этого, поэтому вся логика правок проверяется без виджетов.

import 'dart:ui' show Rect;

import 'package:canvas_app/features/editor/logic/stack_canvas_ops.dart';
import 'package:canvas_app/features/editor/logic/stack_canvas_session.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem _child(String id, {double left = 0}) => ContentItem(
  id: id,
  type: 'text',
  text: id,
  anchorLeft: 0,
  anchorTop: 0,
  anchorRight: 0,
  anchorBottom: 0,
  offsetLeft: left,
  offsetTop: 0,
  offsetRight: left + 100,
  offsetBottom: 40,
);

ContentItem _stack(List<ContentItem> children) => ContentItem(
  id: 'stack-1',
  type: 'stack',
  children: children,
  stackHeight: 240,
);

class _Clock {
  DateTime now = DateTime(2026, 9, 20, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('история', () {
    test('commit → undo → redo возвращает оба состояния', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      final v0 = session.stack;
      final v1 = v0.copyWith(stackHeight: 300);
      session.commit(v1, kind: StackEditKind.style, label: 'высота');

      expect(session.stack.stackHeight, 300);
      expect(session.canUndo, isTrue);
      expect(session.undoLabel, 'высота');

      expect(session.undo(), isTrue);
      expect(session.stack.stackHeight, 240);
      expect(session.stack, same(v0));
      expect(session.canRedo, isTrue);

      expect(session.redo(), isTrue);
      expect(session.stack, same(v1));
    });

    test('новая правка после undo сбрасывает ветку повтора', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      session.commit(
        session.stack.copyWith(stackHeight: 300),
        kind: StackEditKind.style,
      );
      session.undo();
      expect(session.canRedo, isTrue);

      session.commit(
        session.stack.copyWith(stackHeight: 400),
        kind: StackEditKind.style,
      );
      expect(session.canRedo, isFalse);
      expect(session.stack.stackHeight, 400);
    });

    test('undo/redo на пустой истории — no-op', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      expect(session.undo(), isFalse);
      expect(session.redo(), isFalse);
    });

    test('одинаковый снимок не создаёт запись', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      session.commit(session.stack, kind: StackEditKind.move);
      expect(session.undoDepth, 0);
    });

    test('серия стрелок склеивается в один шаг, другой тип — нет', () {
      final clock = _Clock();
      final session = StackCanvasSession(
        stack: _stack([_child('a')]),
        clock: clock.call,
      );
      for (var i = 1; i <= 5; i++) {
        clock.advance(const Duration(milliseconds: 60));
        session.commit(
          session.stack.copyWith(stackHeight: 220 + i * 10),
          kind: StackEditKind.nudge,
          coalesce: true,
        );
      }
      expect(session.undoDepth, 1, reason: '5 шагов стрелкой = одна отмена');
      expect(session.undoLabel, 'сдвиг');

      clock.advance(const Duration(milliseconds: 60));
      session.commit(
        session.stack.copyWith(stackHeight: 500),
        kind: StackEditKind.style,
      );
      expect(session.undoDepth, 2, reason: 'смена типа правки — новый шаг');

      // Длинная пауза — серия стрелок снова отдельный шаг.
      session.commit(
        session.stack.copyWith(stackHeight: 240),
        kind: StackEditKind.style,
      );
      clock.advance(kStackEditCoalesceWindow + const Duration(seconds: 1));
      session.commit(
        session.stack.copyWith(stackHeight: 250),
        kind: StackEditKind.nudge,
        coalesce: true,
      );
      session.commit(
        session.stack.copyWith(stackHeight: 260),
        kind: StackEditKind.nudge,
        coalesce: true,
      );
      expect(session.undoDepth, 4);
    });

    test('два разных ползунка подряд — два шага, а не один', () {
      // kind у обоих style, и без проверки цели отмена одного движения
      // убивала бы и второе: «прозрачность → поворот» сливались в запись.
      final clock = _Clock();
      final session = StackCanvasSession(
        stack: _stack([_child('a')]),
        clock: clock.call,
      );
      session.commit(
        session.stack.copyWith(stackHeight: 300),
        kind: StackEditKind.style,
        label: 'прозрачность',
        coalesce: true,
      );
      clock.advance(const Duration(milliseconds: 60));
      session.commit(
        session.stack.copyWith(stackHeight: 320),
        kind: StackEditKind.style,
        label: 'поворот',
        coalesce: true,
      );
      expect(session.undoDepth, 2);

      clock.advance(const Duration(milliseconds: 60));
      session.commit(
        session.stack.copyWith(stackHeight: 340),
        kind: StackEditKind.style,
        label: 'поворот',
        coalesce: true,
      );
      expect(session.undoDepth, 2, reason: 'то же поле в пределах окна — тот же шаг');
      expect(session.undoLabel, 'поворот');
    });

    test('история ограничена по глубине', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      for (var i = 0; i < kStackEditHistoryLimit + 20; i++) {
        session.commit(
          session.stack.copyWith(stackHeight: 220 + (i % 50)),
          kind: StackEditKind.style,
        );
      }
      expect(session.undoDepth, kStackEditHistoryLimit);
    });
  });

  group('правки детей', () {
    test('commitChild меняет только целевой ребёнок', () {
      final a = _child('a');
      final b = _child('b');
      final session = StackCanvasSession(stack: _stack([a, b]));

      session.commitChild(
        'b',
        (c) => c.copyWith(offsetLeft: 50),
        kind: StackEditKind.move,
      );

      expect(session.children[0], same(a));
      expect(session.children[1].offsetLeft, 50);
    });

    test('несуществующий id — правка не записывается', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      session.commitChild(
        'нет-такого',
        (c) => c.copyWith(offsetLeft: 50),
        kind: StackEditKind.move,
      );
      expect(session.undoDepth, 0);
      expect(session.children.single.offsetLeft, 0);
    });

    test('undo удалённого ребёнка возвращает и его, и выделение чистит', () {
      final a = _child('a');
      final b = _child('b');
      final session = StackCanvasSession(stack: _stack([a, b]));
      session.select('b');

      session.commit(
        session.stack.copyWith(children: [a]),
        kind: StackEditKind.remove,
      );
      expect(session.selection, isEmpty);

      session.undo();
      expect(session.children.length, 2);
      expect(
        session.selection,
        isEmpty,
        reason: 'id жив, но выделять само не надо',
      );
    });
  });

  group('высота холста', () {
    test('setStackHeight пишет clamp и одним шагом отменяется', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));

      expect(session.setStackHeight(300), isTrue);
      expect(session.stack.stackHeight, 300);
      expect(session.undoLabel, 'высота стека');

      expect(session.setStackHeight(9999), isTrue);
      expect(session.stackHeight, kStackHeightMax, reason: 'потолок холста');

      session.undo();
      session.undo();
      expect(session.stack.stackHeight, 240);
    });

    test('то же значение в пределах пикселя — не шаг истории', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      expect(session.setStackHeight(240.3), isFalse);
      expect(session.undoDepth, 0);
    });
  });

  group('ширина холста', () {
    test('без stackWidth холст остаётся проектной ширины', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      expect(session.stackWidth, kStackCanvasWidth);
    });

    test('setStackWidth пишет clamp и одним шагом отменяется', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));

      expect(session.setStackWidth(400), isTrue);
      expect(session.stack.stackWidth, 400);
      expect(session.undoLabel, 'ширина стека');

      expect(session.setStackWidth(9999), isTrue);
      expect(session.stackWidth, kStackWidthMax, reason: 'потолок холста');

      session.undo();
      session.undo();
      expect(session.stackWidth, kStackCanvasWidth);
    });

    test('то же значение в пределах пикселя — не шаг истории', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      expect(session.setStackWidth(kStackCanvasWidth + 0.3), isFalse);
      expect(session.undoDepth, 0);
    });

    test('узкий холст остаётся введённым, а не разворачивается обратно', () {
      // Редактор не имеет права переписывать то, что рисует плеер: пол 240 px
      // при пределе модели 60 превращал «100» в «240».
      final session = StackCanvasSession(stack: _stack([_child('a')]));

      expect(session.setStackWidth(100), isTrue);
      expect(session.stackWidth, 100);
      expect(session.setStackHeight(100), isTrue);
      expect(session.stackHeight, 100);

      // Драг за край холста не должен оставлять в json 289.98624028596936,
      // когда поле показывает «290».
      expect(session.setStackWidth(289.98624028596936), isTrue);
      expect(session.stack.stackWidth, 290);
    });
  });

  group('масштаб содержимого при новом размере', () {
    /// Стек с направляющими и скруглением рамки: проверка задевает и детей, и
    /// редакторский слой, и сам холст.
    StackCanvasSession makeSession() => StackCanvasSession(
      stack: _stack([_child('a', left: 100)]).copyWith(
        guidesX: const <double>[360],
        guidesY: const <double>[120],
        borderRadius: 20,
      ),
    );

    test('без выбора режима правится только рамка', () {
      // Прежнее поведение и дефолт: подтянуть холст под фон — не значит
      // переписать каждый слой.
      final session = makeSession();
      expect(session.setStackWidth(360), isTrue);

      final a = session.stack.children!.single;
      expect(a.stackChildRect(360, 240).left, 100);
      expect(session.stack.guidesX, [360]);
      expect(session.undoLabel, 'ширина стека');
    });

    test('пропорционально едут слои и направляющие, рамка своя', () {
      final session = makeSession();
      expect(
        session.setStackWidth(360, scaleContent: StackContentScale.uniform),
        isTrue,
      );

      final stack = session.stack;
      expect(stack.stackWidth, 360);
      expect(
        stack.children!.single.stackChildRect(360, 240),
        const Rect.fromLTWH(50, 0, 50, 20),
      );
      expect(stack.guidesX, [180]);
      expect(stack.guidesY, [60]);
      expect(
        stack.borderRadius,
        20,
        reason: 'скругление холста — не размер слоя',
      );
      expect(session.undoLabel, 'размер стека');
    });

    test('один шаг отменяет и рамку, и геометрию сразу', () {
      // Два шага («сначала слой, потом рамка») вернули бы состояние, которого
      // в документе никогда не было: новые объекты в старом холсте.
      final session = makeSession();
      session.setStackWidth(360, scaleContent: StackContentScale.uniform);
      final depth = session.undoDepth;

      session.undo();
      expect(session.undoDepth, depth - 1);
      expect(session.stackWidth, kStackCanvasWidth);
      expect(session.stack.children!.single.stackChildRect(720, 240).left, 100);
      expect(session.stack.guidesX, [360]);

      session.redo();
      expect(session.stackWidth, 360);
      expect(session.stack.children!.single.stackChildRect(360, 240).left, 50);
    });

    test('высота в пропорциональном режиме ведёт обе оси своим множителем', () {
      final session = makeSession();
      expect(
        session.setStackHeight(480, scaleContent: StackContentScale.uniform),
        isTrue,
      );

      expect(session.stack.stackHeight, 480);
      expect(
        session.stack.children!.single.stackChildRect(720, 480),
        const Rect.fromLTWH(200, 0, 200, 80),
      );
      expect(session.stack.guidesY, [240]);
      expect(session.undoLabel, 'размер стека');
    });

    test('по осям: ширина делится, высота остаётся', () {
      final session = makeSession();
      expect(
        session.setStackWidth(360, scaleContent: StackContentScale.stretch),
        isTrue,
      );

      expect(
        session.stack.children!.single.stackChildRect(360, 240),
        const Rect.fromLTWH(50, 0, 50, 40),
      );
      expect(session.stack.guidesY, [120], reason: 'ось высоты не тронута');
    });
  });

  group('выделение', () {
    test('аддитивный клик добавляет и снимает', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b')]),
      );
      session.select('a');
      session.select('b', additive: true);
      expect(session.selection, {'a', 'b'});
      session.select('a', additive: true);
      expect(session.selection, {'b'});
    });

    test('замок: слой не выделяется ни одним способом', () {
      final session = StackCanvasSession(
        stack: _stack([
          _child('a'),
          _child('b'),
          _child('c').copyWith(locked: true),
        ]),
      );

      session.select('c');
      expect(session.selection, isEmpty, reason: 'клик по запертому — мимо');
      session.select('c', additive: true);
      expect(session.selection, isEmpty);
      session.selectMany(['a', 'c']);
      expect(session.selection, {'a'});
      session.selectAll();
      expect(session.selection, {'a', 'b'}, reason: 'Ctrl+A пропускает замок');
      session.select('a');
      session.selectRange('c');
      expect(session.selection, {'a', 'b'}, reason: 'диапазон тоже фильтрует');
    });

    test('замок на выделенном слое снимает выделение, undo возвращает', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b')]),
      );
      session.select('a');

      session.commitChild(
        'a',
        (c) => c.copyWith(locked: true),
        kind: StackEditKind.style,
        label: 'блокировка',
      );
      expect(session.children[0].locked, isTrue);
      expect(session.selection, isEmpty, reason: 'иначе Delete был бы обход');
      // Запертый id не мешает правке, если она идёт напрямую по id.
      expect(session.undoLabel, 'блокировка');

      session.undo();
      expect(session.children[0].locked, isFalse);
    });

    test('разблокировать можно и сняв выделение аддитивным кликом', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b', left: 120)]),
      );
      session.select('a');
      session.commitChild(
        'a',
        (c) => c.copyWith(locked: true),
        kind: StackEditKind.style,
      );
      expect(session.selection, isEmpty);
      // Запертый слой по-прежнему двигается в панели слоёв.
      session.moveChild('a', forward: true);
      expect(session.children.map((c) => c.id), ['b', 'a']);
    });

    test('диапазон по z-порядку, не по кликам', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b'), _child('c'), _child('d')]),
      );
      session.select('c');
      session.selectRange('b');
      expect(session.selection, {'b', 'c'});
      expect(session.selectedIdsInZOrder, [
        'b',
        'c',
      ], reason: 'порядок всегда z-порядок, куда бы ни кликнули');
    });

    test('обычный клик заменяет выделение', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b')]),
      );
      session.selectAll();
      expect(session.selection, {'a', 'b'});
      session.select('b');
      expect(session.selection, {'b'});
      session.clearSelection();
      expect(session.selection, isEmpty);
    });

    test('рамка выделения заменяет, а с Shift — дополняет', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b'), _child('c')]),
      );
      session.select('a');
      session.selectMany(['b', 'c']);
      expect(session.selection, {'b', 'c'});

      session.selectMany(['a'], additive: true);
      expect(session.selection, {'b', 'c', 'a'});
      expect(session.selectedIdsInZOrder, ['a', 'b', 'c']);
    });

    test('после смены документа мёртвые id забываются', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b')]),
      );
      session.select('a');
      session.commit(
        session.stack.copyWith(children: [_child('b')]),
        kind: StackEditKind.remove,
      );
      expect(session.selection, isEmpty);
      expect(session.primaryId, isNull);
      expect(session.primaryChild, isNull);
    });
  });

  group('групповые правки', () {
    StackCanvasSession sessionWith(List<String> ids) =>
        StackCanvasSession(stack: _stack([for (final id in ids) _child(id)]));

    test('removeSelected снимает всех выделенных одним шагом истории', () {
      final session = sessionWith(['a', 'b', 'c']);
      session.select('a');
      session.select('c', additive: true);

      session.removeSelected();

      expect(session.children.map((c) => c.id), ['b']);
      expect(session.selection, isEmpty);
      expect(session.undoDepth, 1);
      expect(session.undoLabel, 'удаление 2 объектов');

      session.undo();
      expect(session.children.map((c) => c.id), ['a', 'b', 'c']);
    });

    test('removeSelected без выделения — ничего не делает', () {
      final session = sessionWith(['a']);
      session.removeSelected();
      expect(session.undoDepth, 0);
      expect(session.children.length, 1);
    });

    test('duplicateSelected смещает копии и выделяет их', () {
      final session = sessionWith(['a', 'b']);
      session.select('a');

      var seq = 0;
      session.duplicateSelected(idFactory: () => 'copy-${++seq}');

      expect(session.children.map((c) => c.id), ['a', 'copy-1', 'b']);
      expect(session.selection, {'copy-1'});
      // Копия смещена, оригинал на месте.
      expect(session.children[0].offsetLeft, 0);
      expect(session.children[1].offsetLeft, 16);
      expect(session.children.first.text, 'a');

      session.undo();
      expect(session.children.map((c) => c.id), ['a', 'b']);
      // Мёртвый id копии выпал из выделения.
      expect(session.selection, isEmpty);
    });

    test('повторный Ctrl+D дублирует копию, а не исходник', () {
      final session = sessionWith(['a']);
      session.select('a');
      var seq = 0;
      session.duplicateSelected(idFactory: () => 'copy-${++seq}');
      session.duplicateSelected(idFactory: () => 'copy-${++seq}');

      expect(session.children.map((c) => c.id), ['a', 'copy-1', 'copy-2']);
      expect(session.children[1].offsetLeft, 16);
      expect(session.children[2].offsetLeft, 32);
    });

    test('alt-драг: копии берут выделение, оригиналы стоят', () {
      final session = sessionWith(['a', 'b']);
      session.select('a');

      var seq = 0;
      final copies = session.beginDuplicateDrag(
        idFactory: () => 'copy-${++seq}',
      );

      expect(copies, ['copy-1']);
      expect(session.children.map((c) => c.id), ['a', 'copy-1', 'b']);
      expect(session.selection, {'copy-1'});
      // Без смещения: копия легла ровно на оригинал, её поведёт жест.
      expect(session.children[1].offsetLeft, 0);
      expect(session.undoDepth, 0, reason: 'пока только превью правки');

      session.finishDuplicateDrag(const Offset(50, 0));
      expect(session.children[1].offsetLeft, 50);
      expect(session.children.first.offsetLeft, 0);
      expect(session.undoLabel, 'дубликат');
      expect(session.undoDepth, 1);
    });

    test('escape посреди alt-драга убирает копии и возвращает выделение', () {
      final session = sessionWith(['a', 'b']);
      session.select('a');
      session.beginDuplicateDrag(idFactory: () => 'copy-1');
      expect(session.children.map((c) => c.id), ['a', 'copy-1', 'b']);

      session.abortDuplicateDrag();

      expect(session.children.map((c) => c.id), ['a', 'b']);
      expect(session.selection, {
        'a',
      }, reason: 'выделение возвращается на оригиналы');
      expect(session.undoDepth, 0, reason: 'брошенный жест — не правка');
      expect(session.canUndo, isFalse);
    });

    test('abort без начатого жеста — пустой', () {
      final session = sessionWith(['a']);
      session.select('a');

      session.abortDuplicateDrag();

      expect(session.children.map((c) => c.id), ['a']);
      expect(session.selection, {'a'});
    });

    test('alt-драг без смещения — один шаг «дубликат»', () {
      final session = sessionWith(['a']);
      session.select('a');
      session.beginDuplicateDrag(idFactory: () => 'copy-1');
      session.finishDuplicateDrag(Offset.zero);

      expect(session.children.map((c) => c.id), ['a', 'copy-1']);
      expect(session.undoDepth, 1);

      // Одна отмена убирает копию целиком — до состояния без неё.
      session.undo();
      expect(session.children.map((c) => c.id), ['a']);
      expect(session.selection, isEmpty);
    });

    test('undo посреди alt-драга не подставляет старый снимок', () {
      final session = sessionWith(['a']);
      session.select('a');
      session.duplicateSelected(idFactory: () => 'x-1');
      expect(session.undoDepth, 1);

      session.beginDuplicateDrag(idFactory: () => 'copy-1');
      // Ctrl+Z вместо завершения жеста: снимок копий протух.
      expect(session.undo(), isTrue);
      session.finishDuplicateDrag(const Offset(50, 0));

      expect(session.undoDepth, 0, reason: 'жест закрылся без записи');
      expect(session.children.map((c) => c.id), ['a']);
    });

    test('insertCopies кладёт копии в конец с новыми id и смещением', () {
      final session = sessionWith(['a', 'b']);
      final source = [session.children.first];

      var seq = 0;
      session.insertCopies(
        source,
        idFactory: () => 'p-${++seq}',
        offset: const Offset(16, 16),
      );

      expect(session.children.map((c) => c.id), ['a', 'b', 'p-1']);
      expect(session.selection, {'p-1'});
      expect(session.children.last.offsetLeft, 16);
      expect(session.children.last.text, 'a');
      expect(session.undoLabel, 'вставка');

      session.undo();
      expect(session.children.map((c) => c.id), ['a', 'b']);
    });

    test('вставка группы — одна запись истории, пустая не пишет', () {
      final session = sessionWith(['a', 'b']);
      session.insertCopies(const [], idFactory: () => 'nope');
      expect(session.undoDepth, 0, reason: 'вставлять нечего — шага нет');

      var seq = 0;
      session.insertCopies([
        session.children[0],
        session.children[1],
      ], idFactory: () => 'x-${++seq}');
      expect(session.undoDepth, 1);
      expect(session.children.length, 4);
      expect(session.selection, {'x-1', 'x-2'});
      expect(session.undoLabel, 'вставка 2 объектов');
    });

    test('zOrder поднимает группу, сохраняя её взаимный порядок', () {
      final session = sessionWith(['a', 'b', 'c']);
      session.select('a');
      session.select('c', additive: true);

      session.zOrder(toFront: true);
      expect(session.children.map((c) => c.id), ['b', 'a', 'c']);

      session.zOrder(toFront: false);
      expect(session.children.map((c) => c.id), ['a', 'c', 'b']);
    });

    test('zOrder на всём стеке — no-op, дёргать историю незачем', () {
      final session = sessionWith(['a', 'b']);
      session.selectAll();
      final before = session.stack;

      session.zOrder(toFront: true);
      expect(session.stack, same(before));
      expect(session.undoDepth, 0);
    });

    test('moveChild меняет соседей местами и отменяется одним шагом', () {
      final session = sessionWith(['a', 'b', 'c']);

      expect(session.moveChild('b', forward: true), isTrue);
      expect(session.children.map((c) => c.id), ['a', 'c', 'b']);
      expect(session.undoLabel, 'порядок слоёв');

      expect(session.moveChild('b', forward: false), isTrue);
      expect(session.children.map((c) => c.id), ['a', 'b', 'c']);
      expect(session.undoDepth, 2);

      session.undo();
      session.undo();
      expect(session.children.map((c) => c.id), ['a', 'b', 'c']);
      expect(session.undoDepth, 0);
    });

    test('moveChild на краю и по несуществующему id — false без истории', () {
      final session = sessionWith(['a', 'b']);

      expect(session.moveChild('a', forward: false), isFalse);
      expect(session.moveChild('b', forward: true), isFalse);
      expect(session.moveChild('нет-такого', forward: true), isFalse);
      expect(session.undoDepth, 0);
      expect(session.children.map((c) => c.id), ['a', 'b']);
    });

    test('скрытые дети не участвуют в групповых правках выделения', () {
      final session = StackCanvasSession(
        stack: _stack([
          _child('a'),
          _child('b').copyWith(isHidden: true),
          _child('c'),
        ]),
      );
      session.selectAll();
      expect(session.selection, {
        'a',
        'c',
      }, reason: 'скрытый слой не выделяется');

      // Но если его всё-таки выделили из панели — удаляется он наравне с другими.
      session.select('b', additive: true);
      session.removeSelected();
      expect(session.children.map((c) => c.id), isEmpty);
    });
  });

  group('группы слоёв', () {
    String? groupOf(StackCanvasSession session, String id) =>
        session.children.firstWhere((c) => c.id == id).groupName;

    // a и b — «Группа 1», остальные слои списка идут без группы.
    StackCanvasSession sessionWithGroup(List<String> ids) => StackCanvasSession(
      stack: _stack([
        for (final (i, id) in ids.indexed)
          _child(id).copyWith(groupName: i < 2 ? 'Группа 1' : null),
      ]),
    );

    test('groupSelected даёт общее имя и считается историей одной правкой', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b'), _child('c')]),
      );
      session.select('a');
      session.select('b', additive: true);

      expect(session.canGroup, isTrue);
      expect(session.groupSelected(), 'Группа 1');
      expect(groupOf(session, 'a'), 'Группа 1');
      expect(groupOf(session, 'b'), 'Группа 1');
      expect(groupOf(session, 'c'), isNull, reason: 'не выделен — не в группе');
      expect(session.undoLabel, 'группировка');

      session.undo();
      expect(groupOf(session, 'a'), isNull);
    });

    test('номера групп не повторяются', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b'), _child('c'), _child('d')]),
      );
      session.selectMany(['a', 'b']);
      expect(session.groupSelected(), 'Группа 1');
      session.selectMany(['c', 'd']);
      expect(session.groupSelected(), 'Группа 2');
    });

    test('из одного слоя группу не делает', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b')]),
      );
      session.select('a');
      expect(session.canGroup, isFalse);
      expect(session.groupSelected(), isNull);
      expect(session.undoDepth, 0);
    });

    test('клик по слою берёт всю группу, повторный — сворачивает до слоя', () {
      final session = sessionWithGroup(['a', 'b', 'c']);

      session.select('a');
      expect(session.selection, {'a', 'b'}, reason: 'группа за один клик');
      session.select('a');
      expect(session.selection, {'a'}, reason: 'второй клик — один слой');
      // Слой без группы кликается как обычно.
      session.select('c');
      expect(session.selection, {'c'});
    });

    test('аддитивный клик работает группой в обе стороны', () {
      final session = sessionWithGroup(['a', 'b', 'c']);
      session.selectMany(['c']);
      expect(session.selection, {'c'});

      session.select('a', additive: true);
      expect(session.selection, {'c', 'a', 'b'});
      // Снятие — тоже вся группа: половина группы в выделении смысла нет.
      session.select('b', additive: true);
      expect(session.selection, {'c'});
    });

    test('рамка, зацепившая один слой, берёт группу целиком', () {
      final session = sessionWithGroup(['a', 'b', 'c']);
      session.selectMany(['a']);
      expect(session.selection, {'a', 'b'});
    });

    test('Alt+рамка вычитает группу целиком, а не один слой', () {
      final session = sessionWithGroup(['a', 'b', 'c']);
      session.selectMany(['a', 'c']);
      expect(session.selection, {'a', 'b', 'c'});

      session.selectMany(['b'], subtractive: true);
      expect(session.selection, {'c'});
    });

    test(
      'рамка по пустому месту очищает выделение, Alt+рамка — не трогает',
      () {
        final session = sessionWithGroup(['a', 'b', 'c']);
        session.selectMany(['a']);
        expect(session.selection, {'a', 'b'});

        session.selectMany([]);
        expect(session.selection, isEmpty);

        session.selectMany(['c']);
        session.selectMany([], subtractive: true);
        expect(session.selection, {'c'});
      },
    );

    test('заблокированный член группы не въезжает в выделение', () {
      final session = sessionWithGroup(['a', 'b']);
      session.commitChild(
        'b',
        (c) => c.copyWith(locked: true),
        kind: StackEditKind.style,
        label: 'блокировка',
      );

      session.select('a');
      expect(session.selection, {'a'});
    });

    test('разгруппировка снимает имена со всех выделенных', () {
      final session = sessionWithGroup(['a', 'b', 'c']);
      session.select('c');
      expect(session.canUngroup, isFalse);
      expect(session.ungroupSelected(), isFalse);

      session.select('a');
      expect(session.canUngroup, isTrue);
      expect(session.ungroupSelected(), isTrue);
      expect(groupOf(session, 'a'), isNull);
      expect(groupOf(session, 'b'), isNull);
      expect(session.undoLabel, 'разгруппировка');
    });

    test('разгруппировка слоя из меню не зависит от выделения', () {
      final session = sessionWithGroup(['a', 'b', 'c']);
      session.select('a');
      // Повторный клик схлопывает выделение до одного слоя — меню по такому
      // выделению разорвало бы группу на части.
      session.select('a');
      expect(session.selection, {'a'});

      expect(session.ungroupLayer('a'), isTrue);
      expect(groupOf(session, 'a'), isNull);
      expect(
        groupOf(session, 'b'),
        isNull,
        reason: 'вся группа, не только клик',
      );
      expect(session.undoLabel, 'разгруппировка');

      expect(session.ungroupLayer('c'), isFalse, reason: 'слой вне группы');
      // Холостой вызов не добавляет шага: отмена возвращает ровно группу.
      expect(session.undo(), isTrue);
      expect(groupOf(session, 'a'), 'Группа 1');
      expect(session.canUndo, isFalse, reason: 'разгруппировка — один шаг');
    });

    test('копия группы — своя группа, оригиналы к ней не причём', () {
      final session = sessionWithGroup(['a', 'b']);
      session.select('a');
      expect(session.selection, {'a', 'b'});

      var seq = 0;
      session.duplicateSelected(idFactory: () => 'copy-${++seq}');

      expect(groupOf(session, 'a'), 'Группа 1');
      expect(groupOf(session, 'copy-1'), 'Группа 2');
      expect(groupOf(session, 'copy-2'), 'Группа 2');
      // Клик по копии ведёт свою группу, а не оригиналы.
      expect(session.groupIdsOf('copy-1'), ['copy-1', 'copy-2']);
    });

    test('копия одного слоя из группы не примыкает к оригиналам', () {
      final session = sessionWithGroup(['a', 'b']);
      session.select('a');
      session.select('a');
      expect(session.selection, {'a'});

      session.duplicateSelected(idFactory: () => 'copy-1');
      // Копия получает собственную группу (пусть и из одного слоя): главное —
      // она не «Группа 1», иначе дубликат тянулся бы за оригиналами.
      expect(groupOf(session, 'copy-1'), 'Группа 2');
      session.select('copy-1');
      expect(session.groupIdsOf('copy-1'), ['copy-1']);
      expect(groupOf(session, 'a'), 'Группа 1');
    });

    test('вставка группы из буфера — новая группа', () {
      final session = sessionWithGroup(['a', 'b']);
      var seq = 0;
      session.insertCopies([
        session.children[0],
        session.children[1],
      ], idFactory: () => 'pasted-${++seq}');
      // Обе вставки одного исходного слоя попадают в одну новую группу, а не
      // в исходную: иначе вставка оказалась бы привязана к оригиналам.
      expect(groupOf(session, 'pasted-1'), 'Группа 2');
      expect(groupOf(session, 'pasted-2'), 'Группа 2');
      expect(groupOf(session, 'a'), 'Группа 1');
    });

    test('renameGroup переименовывает всю группу одним шагом', () {
      final session = sessionWithGroup(['a', 'b', 'c']);

      expect(session.renameGroup('Группа 1', 'Шапка'), isTrue);
      expect(groupOf(session, 'a'), 'Шапка');
      expect(groupOf(session, 'b'), 'Шапка');
      expect(groupOf(session, 'c'), isNull);
      expect(session.undoLabel, 'имя группы');

      session.undo();
      expect(groupOf(session, 'a'), 'Группа 1');
    });

    test('renameGroup: пусто, то же имя, чужая группа — без правки', () {
      final session = sessionWithGroup(['a', 'b']);

      expect(session.renameGroup('Группа 1', '  '), isFalse);
      expect(session.renameGroup('Группа 1', 'Группа 1'), isFalse);
      expect(session.renameGroup('Нет такой', 'Что-то'), isFalse);
      expect(session.undoDepth, 0);
    });

    test(
      'renameGroup на чужое имя сливает группы: имя и есть идентичность',
      () {
        final session = StackCanvasSession(
          stack: _stack([
            _child('a').copyWith(groupName: 'Слева'),
            _child('b').copyWith(groupName: 'Справа'),
          ]),
        );
        expect(session.renameGroup('Справа', 'Слева'), isTrue);
        expect(session.groupIdsOf('a'), ['a', 'b']);
      },
    );
  });

  group('имена слоёв', () {
    test('renameLayer пишет имя и отменяется одним шагом', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));

      expect(session.renameLayer('a', '  Шапка  '), isTrue);
      expect(session.childById('a')!.layerName, 'Шапка');
      expect(session.undoLabel, 'имя слоя');
      expect(session.undoDepth, 1);

      session.undo();
      expect(session.childById('a')!.layerName, isNull);
    });

    test('renameLayer: чужой id, то же имя и пустое в пустое — без правки', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      expect(session.renameLayer('нет-такого', 'Шапка'), isFalse);
      expect(session.renameLayer('a', '   '), isFalse);
      expect(session.undoDepth, 0);

      session.renameLayer('a', 'Шапка');
      expect(session.renameLayer('a', 'Шапка'), isFalse);
      expect(session.undoDepth, 1);

      // Пустое имя снимает подпись — иначе в списке висел бы пустой ярлык.
      expect(session.renameLayer('a', ''), isTrue);
      expect(session.childById('a')!.layerName, isNull);
    });

    test('копия слоя теряет имя: два «Шапка» в списке не различить', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a').copyWith(layerName: 'Шапка')]),
      );
      session.select('a');
      session.duplicateSelected(idFactory: () => 'copy-1');

      expect(session.childById('a')!.layerName, 'Шапка');
      expect(session.childById('copy-1')!.layerName, isNull);
    });
  });

  group('направляющие', () {
    test('добавление, повтор и удаление', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      expect(session.guidesX, isEmpty);

      expect(session.addGuide(vertical: true, position: 120.2), isTrue);
      expect(session.guidesX, [120.0], reason: 'позиция квантуется');
      expect(session.undoLabel, 'вертикальная направляющая');

      // Та же линия рядом — правки нет: иначе лишний шаг undo на пустяк.
      expect(session.addGuide(vertical: true, position: 120.1), isFalse);
      expect(session.undoDepth, 1);

      expect(session.addGuide(vertical: true, position: 80), isTrue);
      expect(session.guidesX, [
        80.0,
        120.0,
      ], reason: 'хранятся отсортированными');

      expect(session.removeGuide(vertical: true, position: 120), isTrue);
      expect(session.guidesX, [80.0]);
      expect(session.removeGuide(vertical: true, position: 120), isFalse);
    });

    test('перестановка ищет по значению, слияние оставляет одну линию', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      session.addGuide(vertical: false, position: 64);
      session.addGuide(vertical: false, position: 128);
      expect(session.guidesY, [64.0, 128.0]);

      // Пересортица посреди драга не должна уронить перетаскивание на чужую
      // линию: целимся значением, а не индексом.
      expect(session.moveGuide(vertical: false, from: 128, to: 32), isTrue);
      expect(session.guidesY, [32.0, 64.0]);

      expect(session.moveGuide(vertical: false, from: 32, to: 64), isTrue);
      expect(session.guidesY, [64.0]);

      expect(session.moveGuide(vertical: false, from: 64, to: 64), isFalse);
      expect(session.moveGuide(vertical: false, from: 200, to: 10), isFalse);
      expect(session.undoDepth, 4, reason: 'две поставили, две передвинули');
    });

    test('кламп по краям холста и undo одной правкой', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      expect(session.addGuide(vertical: true, position: 9000), isTrue);
      expect(session.addGuide(vertical: false, position: -40), isTrue);
      expect(session.guidesX, [kStackCanvasWidth]);
      expect(session.guidesY, [0]);

      session.undo();
      expect(session.guidesY, isEmpty);
      session.undo();
      expect(session.guidesX, isEmpty);
      expect(session.canUndo, isFalse);
    });

    test('правка детей и холста направляющие не трогает', () {
      final session = StackCanvasSession(
        stack: _stack([_child('a'), _child('b')]),
      );
      session.addGuide(vertical: false, position: 200);
      session.select('a');
      session.removeSelected();
      session.setStackHeight(300);

      expect(session.children.length, 1);
      expect(session.stack.stackHeight, 300);
      expect(session.guidesY, [200.0]);
    });

    test('направляющие доживают до json и обратно', () {
      final session = StackCanvasSession(stack: _stack([_child('a')]));
      session.addGuide(vertical: true, position: 120);
      session.addGuide(vertical: false, position: 64);

      final restored = ContentItem.fromJson(session.stack.toJson());
      expect(restored.guidesX, [120.0]);
      expect(restored.guidesY, [64.0]);
    });
  });
}
