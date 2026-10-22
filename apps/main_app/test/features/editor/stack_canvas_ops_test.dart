// Чистая геометрия канваса стека: групповой сдвиг, ограничивающий rect,
// чужие rect'ы для снаппинга, замеры, перенос стиля и пресеты якорей.
// Экран вызывает эти функции, не наоборот, — поэтому их можно проверять
// без виджетов.

import 'dart:ui';

import 'package:canvas_app/features/editor/logic/stack_canvas_ops.dart';
import 'package:canvas_app/features/editor/widgets/stack_anchor_presets.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ребёнок с якорями в 0 и смещениями = прямоугольник в пикселях стека.
ContentItem _box(String id, double left, double top, double w, double h) =>
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
      offsetRight: left + w,
      offsetBottom: top + h,
    );

const double _h = 400;

/// Точки после поворота — иррациональные, поэтому сравниваем с допуском.
Matcher nearOffset(Offset to, [double eps = 0.01]) => predicate<Offset>(
  (o) => (o.dx - to.dx).abs() <= eps && (o.dy - to.dy).abs() <= eps,
  'within $eps of Offset(${to.dx}, ${to.dy})',
);

Matcher nearRect(Rect to, [double eps = 0.01]) => predicate<Rect>(
  (r) =>
      (r.left - to.left).abs() <= eps &&
      (r.top - to.top).abs() <= eps &&
      (r.right - to.right).abs() <= eps &&
      (r.bottom - to.bottom).abs() <= eps,
  'within $eps of $to',
);

/// Середина стороны между двумя видимыми углами.
Offset _mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

void main() {
  group('translateChildren', () {
    test('сдвигает только выбранных', () {
      final a = _box('a', 0, 0, 100, 40);
      final b = _box('b', 200, 100, 80, 30);
      final moved = translateChildren(
        children: [a, b],
        ids: {'b'},
        delta: const Offset(10, -5),
        height: _h,
      );

      expect(moved[0], same(a), reason: 'нетронутые — те же экземпляры');
      expect(
        moved[1].stackChildRect(kStackCanvasWidth, _h),
        const Rect.fromLTWH(210, 95, 80, 30),
      );
    });

    test('нулевой сдвиг и пустое выделение возвращают тот же список', () {
      final children = [_box('a', 0, 0, 100, 40)];
      expect(
        translateChildren(
          children: children,
          ids: {'a'},
          delta: Offset.zero,
          height: _h,
        ),
        same(children),
      );
      expect(
        translateChildren(
          children: children,
          ids: <String>{},
          delta: const Offset(5, 5),
          height: _h,
        ),
        same(children),
      );
    });

    test('сдвиг сохраняется в якоре+offset, а не в сырых пикселях', () {
      // Якорь по центру: после переноса модель обязана остаться читаемой
      // GameStackWidget, который пересчитывает rect под другую ширину.
      final centered = ContentItem(
        id: 'c',
        type: 'text',
        anchorLeft: 0.5,
        anchorTop: 0.5,
        anchorRight: 0.5,
        anchorBottom: 0.5,
        offsetLeft: -50,
        offsetTop: -20,
        offsetRight: 50,
        offsetBottom: 20,
      );
      final moved = translateChildren(
        children: [centered],
        ids: {'c'},
        delta: const Offset(30, 0),
        height: _h,
      ).single;

      expect(moved.anchorLeft, 0.5);
      expect(moved.offsetLeft, closeTo(-20, 0.001));
      expect(moved.offsetRight, closeTo(80, 0.001));
    });
  });

  group('unionOfChildren', () {
    test('общий прямоугольник группы', () {
      final union = unionOfChildren(
        children: [_box('a', 0, 0, 100, 40), _box('b', 200, 100, 80, 30)],
        height: _h,
      );
      expect(union, const Rect.fromLTRB(0, 0, 280, 130));
    });

    test('нулевые по размеру дети не попадают в union', () {
      final union = unionOfChildren(
        children: [_box('a', 10, 10, 100, 40), _box('zero', 5, 5, 0, 20)],
        height: _h,
      );
      expect(union, const Rect.fromLTRB(10, 10, 110, 50));
    });

    test('пустой список — null', () {
      expect(unionOfChildren(children: const [], height: _h), isNull);
    });
  });

  group('scaleRectIntoGroup', () {
    test('то же место — тот же rect', () {
      const from = Rect.fromLTRB(10, 20, 210, 120);
      expect(
        scaleRectIntoGroup(const Rect.fromLTRB(50, 40, 90, 60), from, from),
        const Rect.fromLTRB(50, 40, 90, 60),
      );
    });

    test('двойное увеличение группы множит и размер, и смещение', () {
      final scaled = scaleRectIntoGroup(
        const Rect.fromLTRB(50, 50, 100, 100),
        const Rect.fromLTWH(0, 0, 100, 100),
        const Rect.fromLTWH(0, 0, 200, 300),
      );
      expect(scaled, const Rect.fromLTWH(100, 150, 100, 150));
    });

    test('перенос без изменения размера не трогает самого ребёнка', () {
      expect(
        scaleRectIntoGroup(
          const Rect.fromLTRB(0, 0, 10, 10),
          const Rect.fromLTWH(0, 0, 100, 100),
          const Rect.fromLTWH(20, 30, 100, 100),
        ),
        const Rect.fromLTWH(20, 30, 10, 10),
      );
    });

    test('вырожденный union не даёт Inf: только перенос', () {
      final point = const Rect.fromLTWH(50, 50, 0, 0);
      final scaled = scaleRectIntoGroup(
        point,
        point,
        const Rect.fromLTWH(70, 80, 0, 0),
      );
      expect(scaled, const Rect.fromLTWH(70, 80, 0, 0));
      expect(scaled.width.isFinite, isTrue);
      expect(scaled.height.isFinite, isTrue);
    });
  });

  test('otherRects оставляет только невыделенных', () {
    final rects = otherRects(
      children: [_box('a', 0, 0, 10, 10), _box('b', 20, 0, 10, 10)],
      excludeIds: {'a'},
      height: _h,
    );
    expect(rects, [const Rect.fromLTWH(20, 0, 10, 10)]);
  });

  group('nudgeResize', () {
    ContentItem byId(List<ContentItem> list, String id) =>
        list.firstWhere((c) => c.id == id);

    test('растёт правый край, левый якорь стоит', () {
      final a = _box('a', 10, 20, 100, 40);
      final b = _box('b', 300, 300, 60, 20);
      final next = nudgeResize(
        children: [a, b],
        ids: {'a'},
        delta: const Offset(5, 0),
        height: _h,
      );

      final grown = byId(next, 'a').stackChildRect(kStackCanvasWidth, _h);
      expect(grown, const Rect.fromLTWH(10, 20, 105, 40));
      expect(byId(next, 'b'), same(b), reason: 'чужие объекты не трогаем');
    });

    test('отрицательная дельта упирается в минимальный размер', () {
      final next = nudgeResize(
        children: [_box('a', 10, 20, 100, 40)],
        ids: {'a'},
        delta: const Offset(-500, -500),
        height: _h,
      );
      final rect = next.single.stackChildRect(kStackCanvasWidth, _h);
      expect(
        rect,
        const Rect.fromLTWH(10, 20, kStackChildMinWidth, kStackChildMinHeight),
      );
    });

    // Инвариант сменился по #185: раньше рост упирался в рамку канваса, и
    // автор не мог собрать фон из больших спрайтов — объект после каждой
    // правки возвращался к краю холста. Холст — окно, а не стена.
    test('рост не ограничен рамкой канваса', () {
      final next = nudgeResize(
        children: [_box('a', 10, 20, 100, 40)],
        ids: {'a'},
        delta: const Offset(900, 900),
        height: _h,
      );
      final rect = next.single.stackChildRect(kStackCanvasWidth, _h);
      expect(rect.right, 10 + 100 + 900);
      expect(rect.bottom, 20 + 40 + 900);
    });

    test('группа масштабируется аффинно, как за ручку', () {
      final children = [_box('a', 0, 0, 100, 40), _box('b', 200, 100, 80, 30)];
      final next = nudgeResize(
        children: children,
        ids: {'a', 'b'},
        delta: const Offset(140, 0),
        height: _h,
      );

      // union был 0..280, стал 0..420 — множитель 1.5 по x и 1 по y.
      final a = next.first.stackChildRect(kStackCanvasWidth, _h);
      final b = next.last.stackChildRect(kStackCanvasWidth, _h);
      expect(a, const Rect.fromLTWH(0, 0, 150, 40));
      expect(b, const Rect.fromLTWH(300, 100, 120, 30));
    });

    test('нулевая дельта и пустое выделение — список тот же', () {
      final children = [_box('a', 10, 20, 100, 40)];
      expect(
        nudgeResize(
          children: children,
          ids: {'a'},
          delta: Offset.zero,
          height: _h,
        ),
        same(children),
      );
      expect(
        nudgeResize(
          children: children,
          ids: const {},
          delta: const Offset(5, 5),
          height: _h,
        ),
        same(children),
      );
    });
  });

  group('idsInRect', () {
    final children = [
      _box('a', 0, 0, 100, 40),
      _box('b', 200, 100, 80, 30),
      _box('c', 300, 300, 40, 40),
    ];

    test('цепляет за частичное пересечение, в z-порядке', () {
      expect(
        idsInRect(
          children: children,
          rect: const Rect.fromLTWH(90, 30, 150, 100),
          height: _h,
        ),
        ['a', 'b'],
      );
    });

    test('partial: false требует полного попадания', () {
      expect(
        idsInRect(
          children: children,
          rect: const Rect.fromLTWH(90, 30, 150, 100),
          height: _h,
          partial: false,
        ),
        isEmpty,
      );
      expect(
        idsInRect(
          children: children,
          rect: const Rect.fromLTWH(-10, -10, 700, 400),
          height: _h,
          partial: false,
        ),
        ['a', 'b', 'c'],
      );
    });

    test('нулевая рамка (тап без движения) не выделяет ничего', () {
      expect(
        idsInRect(
          children: children,
          rect: const Rect.fromLTWH(50, 20, 0, 0),
          height: _h,
        ),
        isEmpty,
      );
    });

    test('рамка ловит повёрнутый слой по видимому габариту', () {
      // Под 90° слой a стоит вертикально: его картинка — x∈[30,70], y∈[−30,70].
      // Рамка начинается с x=90, то есть правее картинки, хотя модельный
      // rect' с right=100 в неё ещё попадал.
      final turned = [
        _box('a', 0, 0, 100, 40).copyWith(rotation: 90),
        children[1],
      ];
      expect(
        idsInRect(
          children: turned,
          rect: const Rect.fromLTWH(90, 30, 150, 100),
          height: _h,
        ),
        ['b'],
        reason: 'без поворота a попал бы в рамку, с поворотом — мимо',
      );
    });

    test('рамка ловит масштабированный слой по увеличенной картинке', () {
      // Масштаб 1.5 растёт от центра: правый край уезжает с 100 на 125 и
      // попадает в рамку, которая начинается с 120.
      final zoomed = [
        _box('a', 0, 0, 100, 40).copyWith(scale: 1.5),
        _box('b', 200, 100, 80, 30),
      ];
      expect(
        idsInRect(
          children: zoomed,
          rect: const Rect.fromLTWH(120, 0, 40, 40),
          height: _h,
        ),
        ['a'],
      );
    });
  });

  group('rulerContentGaps', () {
    // Полоса вертикальной линейки: 18 px у левого края холста.
    const band = Rect.fromLTWH(100, 50, 18, 300);

    test('слой у края отдаёт линейке пересечение в своих координатах', () {
      expect(
        rulerContentGaps(
          band: band,
          content: const [Rect.fromLTWH(90, 60, 200, 40)],
        ),
        const [Rect.fromLTWH(0, 10, 18, 40)],
      );
    });

    test('слой целиком в полосе — полоса уходит в дымку на весь его rect', () {
      expect(
        rulerContentGaps(
          band: band,
          content: const [Rect.fromLTWH(102, 100, 8, 30)],
        ),
        const [Rect.fromLTWH(2, 50, 8, 30)],
      );
    });

    test('дальний слой линейке не мешает', () {
      expect(
        rulerContentGaps(
          band: band,
          content: const [Rect.fromLTWH(300, 60, 100, 40)],
        ),
        isEmpty,
      );
    });

    test('пересечение по вертикали считаем только в пределах полосы', () {
      expect(
        rulerContentGaps(
          band: band,
          content: const [Rect.fromLTWH(90, 300, 200, 200)],
        ),
        const [Rect.fromLTWH(0, 250, 18, 50)],
      );
    });
  });

  group('snapDrag', () {
    final moving = const Rect.fromLTWH(0, 0, 100, 40);

    test('край прилипает к краю соседа и рисует линию', () {
      final snap = snapDrag(
        moving: moving,
        desired: const Offset(196, 130),
        others: const [Rect.fromLTWH(200, 100, 80, 30)],
        canvasHeight: _h,
      );
      // 196 → 200 по x; по y нижний край соседа (130) ровно под верхним краем.
      expect(snap.delta, const Offset(200, 130));
      expect(snap.verticalGuides, [200.0]);
      expect(snap.horizontalGuides, [130.0]);
    });

    test('центр группы липнет к центру канваса', () {
      final snap = snapDrag(
        moving: moving,
        desired: const Offset(350, 0),
        others: const [],
        canvasHeight: _h,
      );
      // Ни один край (350/400/450) не попал в 6 px от центра 360.
      expect(snap.delta, const Offset(350, 0));
      expect(snap.verticalGuides, isEmpty);

      final centered = snapDrag(
        moving: moving,
        desired: const Offset(307, 0),
        others: const [],
        canvasHeight: _h,
      );
      expect(centered.delta.dx, 310, reason: 'центр 357 → 360');
      expect(centered.verticalGuides, [360.0]);
    });

    test('за порогом прилипания нет', () {
      final snap = snapDrag(
        moving: moving,
        desired: const Offset(170, -30),
        others: const [Rect.fromLTWH(200, 100, 80, 30)],
        canvasHeight: _h,
      );
      expect(snap.delta, const Offset(170, -30));
      expect(snap.verticalGuides, isEmpty);
      expect(snap.horizontalGuides, isEmpty);
    });

    test('направляющая — цель прилипания и линия-подсказка', () {
      final snap = snapDrag(
        moving: moving,
        desired: const Offset(153, 76),
        others: const [],
        canvasHeight: _h,
        guidesX: const [150],
        guidesY: const [80],
      );
      // Левый край 153 → направляющая 150; верх 76 → направляющая 80.
      expect(snap.delta, const Offset(150, 80));
      expect(snap.verticalGuides, [150.0]);
      expect(snap.horizontalGuides, [80.0]);
    });

    test('ближайшая цель побеждает направляющую', () {
      final snap = snapDrag(
        moving: moving,
        desired: const Offset(197, 0),
        others: const [Rect.fromLTWH(200, 100, 80, 30)],
        canvasHeight: _h,
        guidesX: const [193],
      );
      expect(snap.delta.dx, 200, reason: 'сосед в 3 px, направляющая в 4');
      expect(snap.verticalGuides, [200.0]);
    });

    test('ось без цели сохраняет честный сдвиг', () {
      final snap = snapDrag(
        moving: moving,
        desired: const Offset(201, 45),
        others: const [Rect.fromLTWH(200, 100, 80, 30)],
        canvasHeight: _h,
      );
      expect(snap.delta, const Offset(200, 45));
      expect(snap.verticalGuides, [200.0]);
      expect(snap.horizontalGuides, isEmpty);
    });

    test('из группы липнет весь bounding rect, а не каждый ребёнок', () {
      // Группу 120×40 ведёт её центр (358 → 360), а не чей-то отдельный край.
      final snap = snapDrag(
        moving: const Rect.fromLTWH(0, 0, 120, 40),
        desired: const Offset(298, 0),
        others: const [Rect.fromLTWH(320, 0, 80, 30)],
        canvasHeight: _h,
      );
      expect(snap.delta.dx, 300);
      expect(snap.verticalGuides, [360.0]);
    });
  });

  group('snapResize', () {
    test('правый нижний угол липнет к левому краю соседа', () {
      final snap = snapResize(
        rect: const Rect.fromLTWH(0, 0, 196, 40),
        mode: StackChildDragMode.resizeBR,
        others: const [Rect.fromLTWH(200, 100, 80, 30)],
        canvasHeight: _h,
      );
      // По x правый край 196 → 200; по y нижний 40 далёк от всех целей.
      expect(snap.delta, const Offset(4, 0));
      expect(snap.verticalGuides, [200.0]);
      expect(snap.horizontalGuides, isEmpty);
    });

    test('верхний левый угол цепляет и рамку канваса', () {
      final snap = snapResize(
        rect: const Rect.fromLTWH(3, 4, 100, 40),
        mode: StackChildDragMode.resizeTL,
        others: const [],
        canvasHeight: _h,
      );
      expect(snap.delta, const Offset(-3, -4));
      expect(snap.verticalGuides, [0.0]);
      expect(snap.horizontalGuides, [0.0]);
    });

    test('липнут только свободные края: правый верх не трогает низ', () {
      // Нижний край (196) стоит в 4 px от центра канваса по вертикали, но у
      // resizeTR он закреплён — прилипать нечему, верх (96) далёк от целей.
      final snap = snapResize(
        rect: const Rect.fromLTWH(100, 96, 100, 100),
        mode: StackChildDragMode.resizeTR,
        others: const [Rect.fromLTWH(0, 300, 50, 40)],
        canvasHeight: _h,
      );
      expect(snap.delta, Offset.zero);
      expect(snap.horizontalGuides, isEmpty);
    });

    test('за порогом поправки нет', () {
      final snap = snapResize(
        rect: const Rect.fromLTWH(0, 0, 180, 40),
        mode: StackChildDragMode.resizeBR,
        others: const [Rect.fromLTWH(200, 100, 80, 30)],
        canvasHeight: _h,
      );
      expect(snap.delta, Offset.zero);
      expect(snap.verticalGuides, isEmpty);
    });

    test('середина стороны липнет только по своей оси', () {
      final snap = snapResize(
        rect: const Rect.fromLTWH(0, 0, 196, 100),
        mode: StackChildDragMode.resizeRight,
        others: const [Rect.fromLTWH(200, 100, 80, 30)],
        canvasHeight: _h,
      );
      // По x правый край 196 → 200; по y ручка вообще не двигает край.
      expect(snap.delta, const Offset(4, 0));
      expect(snap.verticalGuides, [200.0]);
      expect(snap.horizontalGuides, isEmpty);
    });

    test('режим перемещения поправки не даёт', () {
      final snap = snapResize(
        rect: const Rect.fromLTWH(0, 0, 197, 40),
        mode: StackChildDragMode.move,
        others: const [Rect.fromLTWH(200, 100, 80, 30)],
        canvasHeight: _h,
      );
      expect(snap.delta, Offset.zero);
    });

    test('с сеткой липнет и край, оказавшийся между соседями', () {
      final snap = snapResize(
        rect: const Rect.fromLTWH(0, 0, 196, 40),
        mode: StackChildDragMode.resizeBR,
        others: const [Rect.fromLTWH(300, 100, 80, 30)],
        canvasHeight: _h,
        gridStep: 20,
      );
      // До соседа далеко, сетка (200) рядом.
      expect(snap.delta, const Offset(4, 0));
      expect(snap.verticalGuides, [200.0]);
    });

    test('ресайз цепляется за направляющую только свободным краем', () {
      final snap = snapResize(
        rect: const Rect.fromLTWH(0, 0, 196, 40),
        mode: StackChildDragMode.resizeBR,
        others: const [],
        canvasHeight: _h,
        guidesX: const [200],
        guidesY: const [300],
      );
      // Правый край 196 → направляющая 200; нижний 40 до 300 не дотягивается,
      // и левый/верхний — закреплённые, их не двигаем.
      expect(snap.delta, const Offset(4, 0));
      expect(snap.verticalGuides, [200.0]);
      expect(snap.horizontalGuides, isEmpty);
    });
  });

  group('constrainToAxis', () {
    test('без Shift смещение проходит как есть', () {
      expect(
        constrainToAxis(const Offset(30, -12), locked: false),
        const Offset(30, -12),
      );
    });

    test('остаётся ось, куда палец ушёл дальше', () {
      expect(
        constrainToAxis(const Offset(30, -12), locked: true),
        const Offset(30, 0),
      );
      expect(
        constrainToAxis(const Offset(4, 90), locked: true),
        const Offset(0, 90),
      );
    });

    test('нулевой ход и равные проекции не дают диагонали', () {
      expect(
        constrainToAxis(Offset.zero, locked: true),
        Offset.zero,
        reason: 'на нуле любая ось честная',
      );
      expect(
        constrainToAxis(const Offset(-20, 20), locked: true),
        const Offset(-20, 0),
        reason: 'при ничьей выигрывает горизонталь — предсказуемо, не в рандом',
      );
    });
  });

  group('measureDrag', () {
    // 100×40 в (200,100) на холсте 720×400.
    const moving = Rect.fromLTWH(200, 100, 100, 40);

    List<StackMeasure> alongX(List<StackMeasure> measures) =>
        measures.where((m) => m.horizontal).toList();

    test('зазор до соседей с обеих сторон, линия по центру', () {
      final measures = alongX(
        measureDrag(
          moving: moving,
          others: const [
            Rect.fromLTWH(80, 110, 100, 20),
            Rect.fromLTWH(340, 100, 60, 40),
          ],
          canvasHeight: _h,
        ),
      );
      expect(measures.map((m) => m.gap).toList(), [20, 40]);
      expect(measures.first.from, 180);
      expect(measures.first.to, 200);
      expect(measures.map((m) => m.line).toSet(), {
        120.0,
      }, reason: 'линия идёт по центру тащимого rect\'а');
    });

    test('без соседа мерит до края холста', () {
      final measures = measureDrag(
        moving: moving,
        others: const [],
        canvasHeight: _h,
      );
      expect(measures, hasLength(4));
      // По x — до левого 0 и правого 720; по y — до 0 и 400.
      expect(measures.map((m) => m.gap).toList(), [200, 420, 100, 260]);
    });

    test('сосед по диагонали — не сосед', () {
      final measures = alongX(
        measureDrag(
          moving: moving,
          // 200..240 по y не пересекает 100..140: дырки по x между ними нет.
          others: const [Rect.fromLTWH(150, 200, 40, 40)],
          canvasHeight: _h,
        ),
      );
      expect(measures.map((m) => m.gap).toList(), [200, 420]);
    });

    test('из двух соседей с одной стороны берётся ближайший', () {
      final measures = alongX(
        measureDrag(
          moving: moving,
          others: const [
            Rect.fromLTWH(0, 100, 150, 40),
            Rect.fromLTWH(100, 100, 95, 40),
          ],
          canvasHeight: _h,
        ),
      );
      expect(measures.first.gap, 5, reason: 'правый край 195 ближе, чем 150');
      expect(measures.first.from, 195);
    });

    test('впритык — нулевой зазор, наложение — без замера', () {
      final touching = alongX(
        measureDrag(
          moving: moving,
          others: const [Rect.fromLTWH(160, 100, 40, 40)],
          canvasHeight: _h,
        ),
      );
      expect(touching.first.gap, 0, reason: 'края сошлись — это видно');

      final overlapping = alongX(
        measureDrag(
          moving: moving,
          others: const [Rect.fromLTWH(250, 100, 60, 40)],
          canvasHeight: _h,
        ),
      );
      expect(overlapping.map((m) => m.gap).toList(), [
        200,
        420,
      ], reason: 'отрицательного зазора не бывает: объект лег на соседа');
    });
  });

  group('pasteStyle', () {
    final source = _box('s', 0, 0, 100, 40).copyWith(
      backgroundColor: const Color(0xFF112233),
      borderRadius: 12,
      padding: 8,
      fontFamily: 'res/fonts/mono.ttf',
      opacity: 0.5,
    );

    test('переносит вид и не трогает геометрию, текст и имена', () {
      final target = _box('t', 200, 100, 80, 30).copyWith(
        backgroundColor: const Color(0xFFFF0000),
        layerName: 'Заголовок',
        groupName: 'Группа 1',
      );
      final next = pasteStyle(
        children: [source, target],
        ids: {'t'},
        source: source,
      );
      final pasted = next.last;
      expect(pasted.backgroundColor, const Color(0xFF112233));
      expect(pasted.borderRadius, 12);
      expect(pasted.padding, 8);
      expect(pasted.fontFamily, 'res/fonts/mono.ttf');
      expect(pasted.opacity, 0.5);
      expect(pasted.offsetTop, 100, reason: 'геометрия своя');
      expect(pasted.text, 't', reason: 'содержимое своё');
      expect(pasted.layerName, 'Заголовок');
      expect(pasted.groupName, 'Группа 1');
    });

    test('формулы переезжают вместе с числом', () {
      // Копирование вида пополам: число приехало, а привязка к переменной
      // осталась у цели — в игре слой выглядел бы не тем, что на канвасе.
      final styled = _box('s', 0, 0, 10, 10)
          .copyWith(borderRadius: 12, padding: 8)
          .withNumericExpr('borderRadius', 'hp / 4')
          .withNumericExpr('padding', 'gap');
      final target = _box('t', 0, 0, 10, 10).withNumericExpr('duration', '2.5');
      final next = pasteStyle(
        children: [styled, target],
        ids: {'t'},
        source: styled,
      );

      final pasted = next.last;
      expect(pasted.borderRadius, 12);
      expect(pasted.padding, 8);
      expect(pasted.numericExpr('borderRadius'), 'hp / 4');
      expect(pasted.numericExpr('padding'), 'gap');
      expect(
        pasted.numericExpr('duration'),
        '2.5',
        reason: 'поле, которое вставка не копирует, остаётся целевым',
      );
    });

    test('у источника формулы нет — снимаем её и у цели', () {
      final plain = _box('s', 0, 0, 10, 10).copyWith(borderRadius: 4);
      final target = _box('t', 0, 0, 10, 10)
          .copyWith(borderRadius: 30)
          .withNumericExpr('borderRadius', 'hp / 4')
          .withNumericExpr('duration', '5');
      final next = pasteStyle(
        children: [target, plain],
        ids: {'t'},
        source: plain,
      );

      final pasted = next.first;
      expect(pasted.borderRadius, 4);
      expect(pasted.numericExpr('borderRadius'), isNull);
      // Поле, которое числом не переносится, не задеваем.
      expect(pasted.numericExpr('duration'), '5');
    });

    test('чужие слои не меняются', () {
      final a = _box('a', 0, 0, 10, 10);
      final untouched = pasteStyle(
        children: [source, a],
        ids: {'s'},
        source: source,
      );
      expect(untouched.last, same(a));
    });

    test('пустой стиль источника очищает цель, а не оставляет её вид', () {
      final target = _box('t', 0, 0, 10, 10).copyWith(
        backgroundColor: const Color(0xFFFF0000),
        borderRadius: 4,
        padding: 2,
        fontFamily: 'res/fonts/old.ttf',
      );
      final plain = _box('p', 0, 0, 10, 10);
      final next = pasteStyle(
        children: [plain, target],
        ids: {'t'},
        source: plain,
      );
      final pasted = next.last;
      expect(pasted.backgroundColor, isNull);
      expect(pasted.borderRadius, isNull);
      expect(pasted.padding, isNull);
      expect(pasted.fontFamily, isNull);
      expect(pasted.opacity, 1.0, reason: 'источник без прозрачности');
    });

    test('стиль кнопки переезжает целиком', () {
      final button = _box(
        'b',
        0,
        0,
        10,
        10,
      ).copyWith(buttonStyle: ButtonStyleConfig(textSize: 22));
      final next = pasteStyle(
        children: [button, _box('t', 0, 0, 10, 10)],
        ids: {'t'},
        source: button,
      );
      expect(next.last.buttonStyle?.effectiveTextSize, 22);
    });
  });

  group('gridLines', () {
    test('шаг 0 — пустой список', () {
      expect(gridLines(0, 0, 100), isEmpty);
      expect(gridLines(-10, 0, 100), isEmpty);
    });

    test('линии только внутри интервала', () {
      expect(gridLines(20, 15, 62), [20.0, 40.0, 60.0]);
    });

    test('вырожденный интервал даёт одну линию на границе', () {
      expect(gridLines(20, 40, 40), [40.0]);
      expect(gridLines(20, 41, 41), isEmpty);
    });
  });

  group('визуальные габариты повёрнутого объекта', () {
    // Бокс 100×40 с центром в (50, 20).
    final box = const Rect.fromLTWH(0, 0, 100, 40);
    final center = box.center;

    test('углы следуют за картинкой, а не за модельным rect’ом', () {
      final corners = stackChildVisualCorners(box, rotation: 90);

      // 90° вокруг центра (50, 20): локальный вектор (x, y) становится
      // (-y, x) — картинка ложится на бок.
      expect(corners[0], nearOffset(const Offset(70, -30)));
      expect(corners[1], nearOffset(const Offset(70, 70)));
      expect(corners[2], nearOffset(const Offset(30, 70)));
      expect(corners[3], nearOffset(const Offset(30, -30)));
    });

    test('нулевой поворот и масштаб 1 ничего не двигают', () {
      expect(stackChildVisualCorners(box), [
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
      ]);
      expect(stackChildVisualRect(box), box);
    });

    test('масштаб растёт от центра, как Transform.scale', () {
      final rect = stackChildVisualRect(box, scale: 2);
      expect(rect, nearRect(const Rect.fromLTWH(-50, -20, 200, 80)));
      expect(rect.center, center);
    });

    test('габарит повёрнутого объекта — описанный вокруг картинки rect', () {
      final rect = stackChildVisualRect(box, rotation: 45);
      // |w·cos| + |h·sin| = (100 + 40)·√2/2 по обеим осям.
      expect(rect.width, closeTo(98.995, 0.01));
      expect(rect.height, closeTo(98.995, 0.01));
      expect(rect.center, nearOffset(center));
    });

    test('тап бьёт по картинке, а не по описанному rect’у', () {
      // Под 45° левый верхний угол модельного rect’а — пустота вне бокса.
      expect(
        stackChildContains(box.topLeft, box, rotation: 45),
        isFalse,
        reason: 'без поворота эта точка внутри, с поворотом — мимо',
      );
      expect(stackChildContains(box.topLeft, box), isTrue);
      // Точка напротив видимого угла — попадание.
      final corner = stackChildVisualCorners(box, rotation: 45)[3];
      expect(
        stackChildContains(
          Offset.lerp(corner, center, 0.2)!,
          box,
          rotation: 45,
        ),
        isTrue,
      );
      // Масштаб 0.5 уменьшает картинку вдвое: угол модельного rect’а больше не
      // под ней.
      expect(stackChildContains(box.topLeft, box, scale: 0.5), isFalse);
    });
  });

  group('ресайз повёрнутого объекта', () {
    final box = const Rect.fromLTWH(100, 100, 100, 40);

    test('тяга вниз при 90° растит собственную ширину объекта', () {
      final next = resizeStackChildRect(
        start: box,
        mode: StackChildDragMode.resizeBR,
        delta: const Offset(0, 50),
        rotation: 90,
      );

      // Объект стоит на боку: его ось X смотрит вниз по канвасу, поэтому
      // «протащить ручку на 50 вниз» для него — это плюс 50 к ширине.
      expect(next.width, closeTo(150, 0.01));
      expect(next.height, closeTo(40, 0.01));
    });

    test('противоположный визуальный угол не уезжает', () {
      for (final rotation in [0.0, 30.0, 45.0, 90.0, 137.0]) {
        final startPin = stackChildVisualCorners(box, rotation: rotation)[0];
        final next = resizeStackChildRect(
          start: box,
          mode: StackChildDragMode.resizeBR,
          delta: const Offset(37, -21),
          rotation: rotation,
        );
        expect(
          stackChildVisualCorners(next, rotation: rotation)[0],
          nearOffset(startPin),
          reason: 'закреплённый TL должен стоять на месте при $rotation°',
        );
      }
    });

    test('сторона крепится за противоположную сторону', () {
      final next = resizeStackChildRect(
        start: box,
        mode: StackChildDragMode.resizeLeft,
        delta: const Offset(10, 0),
        rotation: 45,
      );
      // Закреплена правая сторона — середина между TR и BR.
      Offset pinOf(Rect r) => _mid(
        stackChildVisualCorners(r, rotation: 45)[1],
        stackChildVisualCorners(r, rotation: 45)[2],
      );

      expect(next.width, lessThan(box.width));
      expect(next.height, closeTo(box.height, 0.01));
      expect(pinOf(next), nearOffset(pinOf(box)));
    });

    test('нулевой поворот — ровно то же, что applyStackChildDrag', () {
      for (final mode in StackChildDragMode.values) {
        final delta = const Offset(13, -7);
        expect(
          resizeStackChildRect(
            start: box,
            mode: mode,
            delta: delta,
            keepAspect: mode.isCorner,
          ),
          applyStackChildDrag(box, mode, delta, keepAspect: mode.isCorner),
          reason: '${mode.name} без поворота не имеет права сдвинуться',
        );
      }
    });

    test('Shift держит пропорции в собственных осях объекта', () {
      final next = resizeStackChildRect(
        start: box,
        mode: StackChildDragMode.resizeBR,
        delta: const Offset(0, 50),
        rotation: 90,
        keepAspect: true,
      );

      expect(
        next.width / next.height,
        closeTo(box.width / box.height, 0.01),
        reason: 'соотношение 2.5 удержано, хотя тянули по экрану вниз',
      );
      expect(next.height, greaterThan(box.height));
    });
  });

  group('snapDrag с сеткой', () {
    test('сетка ловит объект там, где соседей нет', () {
      final snap = snapDrag(
        moving: const Rect.fromLTWH(0, 0, 100, 40),
        desired: const Offset(197, 0),
        others: const [],
        canvasHeight: _h,
        gridStep: 20,
      );
      // Левый край 197 → 200 по линии сетки; центр (247) от линий далеко.
      expect(snap.delta.dx, 200);
      expect(snap.verticalGuides, [200.0]);
    });

    test('ближайшая цель побеждает: сосед ближе линии сетки', () {
      final snap = snapDrag(
        moving: const Rect.fromLTWH(0, 0, 100, 40),
        desired: const Offset(196, 0),
        others: const [Rect.fromLTWH(197, 200, 80, 30)],
        canvasHeight: _h,
        gridStep: 20,
      );
      // 196: до сетки 4 px, до края соседа 1 px.
      expect(snap.delta.dx, 197);
      expect(snap.verticalGuides, [197.0]);
    });

    test('выключенная сетка ничего не добавляет', () {
      final snap = snapDrag(
        moving: const Rect.fromLTWH(0, 0, 100, 40),
        desired: const Offset(194, 0),
        others: const [],
        canvasHeight: _h,
      );
      expect(snap.delta.dx, 194);
      expect(snap.verticalGuides, isEmpty);
    });
  });

  group('alignChildren', () {
    List<double?> lefts(List<ContentItem> list) =>
        list.map((c) => c.offsetLeft).toList();

    test('по левому краю группы', () {
      final children = [_box('a', 10, 0, 100, 40), _box('b', 50, 60, 80, 30)];
      final aligned = alignChildren(
        children: children,
        ids: {'a', 'b'},
        align: StackAlign.left,
        height: _h,
      );
      expect(lefts(aligned), [10, 10]);
      expect(
        aligned[1].offsetTop,
        60,
        reason: 'горизонталь не трогает вертикаль',
      );
    });

    test('по центру группы', () {
      final children = [_box('a', 0, 0, 100, 40), _box('b', 200, 0, 80, 40)];
      final aligned = alignChildren(
        children: children,
        ids: {'a', 'b'},
        align: StackAlign.centerX,
        height: _h,
      );
      // union 0..280 → центр 140.
      expect(aligned[0].offsetLeft, 90);
      expect(aligned[1].offsetLeft, 100);
    });

    test('по нижней общей границе', () {
      final children = [_box('a', 0, 0, 100, 40), _box('b', 0, 60, 80, 30)];
      final aligned = alignChildren(
        children: children,
        ids: {'a', 'b'},
        align: StackAlign.bottom,
        height: _h,
      );
      expect(aligned[0].offsetBottom, 90);
      expect(aligned[1].offsetBottom, 90);
      expect(aligned.map((c) => c.offsetLeft).toList(), [0, 0]);
    });

    test('один выделенный центрируется по канвасу', () {
      final children = [_box('a', 10, 0, 100, 40), _box('b', 20, 20, 10, 10)];
      final aligned = alignChildren(
        children: children,
        ids: {'a'},
        align: StackAlign.centerX,
        height: _h,
      );
      expect(aligned[0].offsetLeft, (kStackCanvasWidth - 100) / 2);
      expect(aligned[1], same(children[1]));
    });

    test('пустое выделение возвращает список тем же объектом', () {
      final children = [_box('a', 10, 0, 100, 40)];
      expect(
        alignChildren(
          children: children,
          ids: <String>{},
          align: StackAlign.left,
          height: _h,
        ),
        same(children),
      );
    });

    test('рамка канваса берётся фактическая ширина, а не проектная', () {
      // Стек 400 px: «по правому краю» обязан прижать к 400. С проектной
      // шириной слой уезжал за отсечку — ровно в ту янтарную зону.
      final children = [_box('a', 10, 0, 100, 40)];
      final aligned = alignChildren(
        children: children,
        ids: {'a'},
        align: StackAlign.right,
        height: _h,
        width: 400,
      );
      expect(aligned[0].offsetRight, 400);
      expect(aligned[0].offsetLeft, 300);
    });
  });

  group('distributeChildren', () {
    test('равные промежутки, крайние не двигаются', () {
      final children = [
        _box('a', 0, 0, 100, 40),
        _box('b', 110, 0, 100, 40),
        _box('c', 300, 0, 100, 40),
      ];
      final result = distributeChildren(
        children: children,
        ids: {'a', 'b', 'c'},
        horizontal: true,
        height: _h,
      );
      // span 0..400, размеры 300 → зазор 50 между соседями.
      expect(result.map((c) => c.offsetLeft).toList(), [0, 150, 300]);
      expect(result.map((c) => c.offsetTop).toList(), [
        0,
        0,
        0,
      ], reason: 'горизонтальное распределение не трогает вертикаль');
    });

    test('z-порядок остаётся исходным', () {
      final children = [
        _box('c', 300, 0, 100, 40),
        _box('a', 0, 0, 100, 40),
        _box('b', 110, 0, 100, 40),
      ];
      final result = distributeChildren(
        children: children,
        ids: {'a', 'b', 'c'},
        horizontal: true,
        height: _h,
      );
      expect(result.map((c) => c.id).toList(), ['c', 'a', 'b']);
      expect(result.map((c) => c.offsetLeft).toList(), [300, 0, 150]);
    });

    test('по вертикали', () {
      final children = [
        _box('a', 0, 0, 100, 40),
        _box('b', 0, 60, 100, 40),
        _box('c', 0, 200, 100, 40),
      ];
      final result = distributeChildren(
        children: children,
        ids: {'a', 'b', 'c'},
        horizontal: false,
        height: _h,
      );
      // span 0..240, размеры 120 → зазор 60.
      expect(result.map((c) => c.offsetTop).toList(), [0, 100, 200]);
      expect(result.map((c) => c.offsetLeft).toList(), [0, 0, 0]);
    });

    test('двоих распределять нечем — список не меняется', () {
      final children = [_box('a', 0, 0, 10, 10), _box('b', 50, 0, 10, 10)];
      expect(
        distributeChildren(
          children: children,
          ids: {'a', 'b'},
          horizontal: true,
          height: _h,
        ),
        same(children),
      );
    });
  });

  group('applyStackAnchorPreset', () {
    const double w = 720;

    test('точечный пресет меняет якоря, но не трогает rect слоя', () {
      final child = _box('a', 300, 180, 100, 40);
      final next = applyStackAnchorPreset(
        child,
        anchors: const [0.5, 0.5, 0.5, 0.5],
        width: w,
        height: _h,
      );

      expect(next.anchorLeft, 0.5);
      expect(next.anchorTop, 0.5);
      // Смещения пересчитаны от центра, а картинка осталась на месте.
      expect(next.offsetLeft, closeTo(-60, 1e-9));
      expect(next.offsetTop, closeTo(-20, 1e-9));
      expect(
        next.stackChildRect(w, _h),
        child.stackChildRect(w, _h),
        reason: 'тап по пресету не должен двигать слой',
      );
    });

    test('после пресета якоря распознаются как этот же пресет', () {
      final next = applyStackAnchorPreset(
        _box('a', 620, 360, 100, 40),
        anchors: kStackAnchorPresets['bottomRight']!,
        width: w,
        height: _h,
      );
      expect(stackAnchorPresetOf(next), 'bottomRight');
      // Ниж-правый угол прижат к холсту: слой уедет туда, где его нет.
      expect(next.stackChildRect(w, _h).right, closeTo(w - 0, 1));
    });

    test('«растянуть по ширине» цепляет края холста, высоту не трогает', () {
      final child = _box('a', 300, 180, 100, 40);
      final next = applyStackAnchorPreset(
        child,
        anchors: kStackAnchorPresets['stretchH']!,
        width: w,
        height: _h,
      );

      final rect = next.stackChildRect(w, _h);
      expect(rect.left, closeTo(0, 1e-9));
      expect(rect.right, closeTo(w, 1e-9));
      expect(rect.top, closeTo(180, 1e-9));
      expect(rect.height, closeTo(40, 1e-9));
      // Обрезанные по краям смещения — 0, иначе ресайз холста даст щель.
      expect(next.offsetLeft, 0);
      expect(next.offsetRight, 0);
    });

    test('«растянуть целиком» = слой на весь холст', () {
      final next = applyStackAnchorPreset(
        _box('a', 10, 10, 20, 20),
        anchors: kStackAnchorPresets['stretch']!,
        width: w,
        height: _h,
      );
      expect(next.stackChildRect(w, _h), Rect.fromLTRB(0, 0, w, _h));
    });

    test('ресайз холста после пресета держит прижатый слой у края', () {
      // Ради этого пресеты и нужны: «прижать к правому нижнему углу»
      // переживает изменение размера стека.
      final pinned = applyStackAnchorPreset(
        _box('a', 620, 360, 100, 40),
        anchors: kStackAnchorPresets['bottomRight']!,
        width: w,
        height: _h,
      );
      final before = pinned.stackChildRect(w, _h);
      final after = pinned.stackChildRect(w + 200, _h + 200);

      expect(before.right, closeTo(w, 1));
      expect(before.bottom, closeTo(_h, 1));
      expect(after.right, closeTo(w + 200, 1));
      expect(after.bottom, closeTo(_h + 200, 1));
      expect(after.width, closeTo(before.width, 1), reason: 'размер не ползёт');
    });
  });

  group('масштаб содержимого при новом размере холста', () {
    test('uniform ведёт обе оси множителем правленной стороны', () {
      // Высота не трогалась — значит и слои не должны «подрасти по вертикали»,
      // как если бы брали среднее из 0.5 и 1.
      final f = stackContentFactors(
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 240,
        mode: StackContentScale.uniform,
      );
      expect(f.x, 0.5);
      expect(f.y, 0.5);
    });

    test('stretch правит каждую ось своим множителем, keep — ничего', () {
      final stretch = stackContentFactors(
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 480,
        mode: StackContentScale.stretch,
      );
      expect(stretch.x, 0.5);
      expect(stretch.y, 2);
      final keep = stackContentFactors(
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 480,
        mode: StackContentScale.keep,
      );
      expect((keep.x, keep.y), (1.0, 1.0));
    });

    test('несуществующий холст даёт единичные множители', () {
      for (final bad in [0.0, -1.0, double.infinity, double.nan]) {
        final f = stackContentFactors(
          fromWidth: bad,
          fromHeight: 240,
          toWidth: 360,
          toHeight: 240,
          mode: StackContentScale.uniform,
        );
        expect((f.x, f.y), (1.0, 1.0), reason: '$bad как ширина');
      }
    });

    test('боксы пересчитываются, якоря остаются своими', () {
      final out = scaleStackContent(
        children: [_box('a', 100, 40, 200, 80)],
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 240,
      );
      expect(
        out.single.stackChildRect(360, 240),
        const Rect.fromLTWH(50, 20, 100, 40),
      );
      expect(out.single.anchorLeft, 0);
      expect(out.single.anchorTop, 0);
    });

    test('слой, прижатый к правому краю, остаётся прижатым', () {
      // 20 px от правого края в холсте 720 → 10 px в холсте 360: прижатие
      // переживает масштаб, иначе «уменьшить макет» разъезжается с рамкой.
      final pinned = ContentItem(
        id: 'p',
        type: 'text',
        text: 'p',
        anchorLeft: 1,
        anchorRight: 1,
        anchorTop: 0,
        anchorBottom: 0,
        offsetLeft: -100,
        offsetRight: -20,
        offsetTop: 40,
        offsetBottom: 80,
      );
      expect(
        pinned.stackChildRect(720, 240),
        const Rect.fromLTWH(620, 40, 80, 40),
      );

      final out = scaleStackContent(
        children: [pinned],
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 240,
      ).single;
      expect(out.anchorRight, 1, reason: 'якорь не переставляем');
      expect(out.offsetRight, -10);
      expect(
        out.stackChildRect(360, 240),
        const Rect.fromLTWH(310, 20, 40, 20),
      );
    });

    test('размеры стиля едут множителем, отсутствие стиля — остаётся', () {
      final styled = _box(
        'a',
        0,
        0,
        200,
        80,
      ).copyWith(textSize: 16, padding: 8, borderRadius: 4);
      final out = scaleStackContent(
        children: [styled, _box('b', 0, 0, 200, 80)],
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 240,
      );
      expect(out.first.textSize, 8);
      expect(out.first.padding, 4);
      expect(out.first.borderRadius, 2);
      expect(out.last.textSize, isNull);
      expect(out.last.padding, isNull);
    });

    test('плоская кнопка уменьшается вместе с корпусом, включая разрядку', () {
      // 0.4 * 0.5 округлить до целого — это 0: правка размера украла бы у
      // автора настройку, о которой он не просил.
      final button = _box('b', 0, 0, 200, 80).copyWith(
        buttonStyle: const ButtonStyleConfig(
          moduleSize: 12,
          textSize: 20,
          letterSpacing: 0.4,
          borderRadius: 6,
          paddingH: 12,
        ),
      );
      final style = scaleStackContent(
        children: [button],
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 240,
      ).single.buttonStyle!;
      expect(style.textSize, 10);
      expect(style.letterSpacing, 0.2);
      expect(style.borderRadius, 3);
      expect(style.paddingH, 6);
      expect(style.moduleSize, 6);
    });

    test('вид слоя не ползёт: scale, поворот и прозрачность свои', () {
      final out = scaleStackContent(
        children: [
          _box(
            'a',
            0,
            0,
            200,
            80,
          ).copyWith(scale: 1.5, rotation: 30, opacity: 0.4),
        ],
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 240,
      ).single;
      expect(out.scale, 1.5);
      expect(out.rotation, 30);
      expect(out.opacity, 0.4);
    });

    test('keep оставляет список детей без изменений', () {
      final children = [_box('a', 0, 0, 200, 80)];
      final out = scaleStackContent(
        children: children,
        fromWidth: 720,
        fromHeight: 240,
        toWidth: 360,
        toHeight: 240,
        mode: StackContentScale.keep,
      );
      expect(identical(out, children), isTrue);
    });

    test('направляющие едут по своей оси и остаются целыми пикселями', () {
      expect(scaleStackGuides(guides: const [100, 33], factor: 0.5), [50, 17]);
      expect(scaleStackGuides(guides: const [], factor: 3), isEmpty);
    });
  });
}
