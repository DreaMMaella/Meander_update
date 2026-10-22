import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:canvas_app/models/content_item_model.dart';

// ============================================================================
//  ГЕОМЕТРИЧЕСКИЕ ОПЕРАЦИИ НАД ДЕТЬМИ СТЕКА
//
//  Чистые функции: вход — список детей и id, выход — новый список. Ни жестов,
//  ни виджетов, ни сторов: за счёт этого групповые операции можно проверять
//  юнит-тестами, а экран остаётся только отображением состояния.
//
//  Координаты — «стековые» пиксели канваса (720 × stackHeight); модель ребёнка
//  при этом якорная (anchor+offset), поэтому каждая операция переводит rect ↔
//  модель через stackChildRect / stackChildWithRect.
// ============================================================================

/// Design-ширина канваса стека: дети раскладываются в ней, а в игре масштаб
/// берётся по доступной ширине ноды. Та же константа в `mnd_core` — под неё
/// же вписывает стек и плеер, чтобы рантайм совпадал с превью.
const double kStackCanvasWidth = kStackDesignWidth;

/// Смещение выделенных детей на [delta]; остальные объекты возвращаются те же
/// самые экземпляры (identical) — историю это не трясёт.
List<ContentItem> translateChildren({
  required List<ContentItem> children,
  required Set<String> ids,
  required Offset delta,
  required double height,
  double width = kStackCanvasWidth,
}) {
  if (delta == Offset.zero || ids.isEmpty) return children;
  return [
    for (final child in children)
      if (!ids.contains(child.id))
        child
      else
        child.stackChildWithRect(
          child.stackChildRect(width, height).shift(delta),
          width,
          height,
        ),
  ];
}

/// Ограничивающий rect группы — база для снаппинга и выравнивания.
Rect? unionOfChildren({
  required Iterable<ContentItem> children,
  required double height,
  double width = kStackCanvasWidth,
}) {
  Rect? acc;
  for (final child in children) {
    final r = child.stackChildRect(width, height);
    if (r.width <= 0 || r.height <= 0) continue;
    acc = acc == null ? r : acc.expandToInclude(r);
  }
  return acc;
}

/// Rect ребёнка при ресайзе группы: аффинное отображение из старого
/// ограничивающего rect'а в новый. Масштабируются и размеры, и смещения —
/// группа ведёт себя как одна картинка, а не как набор независимых ручек.
Rect scaleRectIntoGroup(Rect child, Rect from, Rect to) {
  // Нулевой union (все дети сложены в одну точку) масштабировать нельзя:
  // остаётся только перенос, иначе получили бы Inf в координатах.
  final sx = from.width <= 0 ? 1.0 : to.width / from.width;
  final sy = from.height <= 0 ? 1.0 : to.height / from.height;
  return Rect.fromLTRB(
    to.left + (child.left - from.left) * sx,
    to.top + (child.top - from.top) * sy,
    to.left + (child.right - from.left) * sx,
    to.top + (child.bottom - from.top) * sy,
  );
}

/// Меньше этого объект не сжимается ни ручкой, ни клавиатурой: текст в нём
/// перестаёт читаться, а группа схлопывается в линию.
const double kStackChildMinWidth = 20;
const double kStackChildMinHeight = 12;

// ── Визуальные габариты: масштаб и поворот ──────────────────────────────
//
// Модель хранит неповёрнутый бокс (anchor+offset), а рисует его та же пара
// трансформаций, что и плеер: масштаб и поворот вокруг центра. Всё, что
// редактор показывает пользователю и во что он тыкает, живёт в визуальных
// координатах — отсюда этот набор функций.

double _scaleOf(double scale) => scale > 0 && scale.isFinite ? scale : 1.0;

/// Поворот вектора вокруг начала координат на [degrees] — той же матрицей, что
/// `Transform.rotate` (в экранных координатах, где y вниз, это по часовой).
Offset _rotateVector(Offset v, double degrees) {
  if (degrees == 0) return v;
  final a = degrees * math.pi / 180;
  final c = math.cos(a);
  final s = math.sin(a);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

/// Локальный вектор бокса (от его центра) → тот же вектор на канвасе после
/// масштаба и поворота.
Offset stackChildVisualVector(
  Offset local, {
  required double rotation,
  double scale = 1,
}) => _rotateVector(local * _scaleOf(scale), rotation);

/// Обратное преобразование: вектор канваса → координаты неповёрнутого бокса.
Offset stackChildLocalVector(
  Offset visual, {
  required double rotation,
  double scale = 1,
}) => _rotateVector(visual, -rotation) / _scaleOf(scale);

/// Видимые углы бокса: TL, TR, BR, BL в координатах канваса. При нулевом
/// повороте и масштабе 1 совпадают с углами [rect].
List<Offset> stackChildVisualCorners(
  Rect rect, {
  double rotation = 0,
  double scale = 1,
}) {
  final c = rect.center;
  final half = Offset(rect.width / 2, rect.height / 2);
  Offset v(Offset local) =>
      c + stackChildVisualVector(local, rotation: rotation, scale: scale);
  return [
    v(Offset(-half.dx, -half.dy)),
    v(Offset(half.dx, -half.dy)),
    v(Offset(half.dx, half.dy)),
    v(Offset(-half.dx, half.dy)),
  ];
}

/// Ограничивающий rect того, что реально нарисовано: после поворота объект
/// занимает больше места, чем его модельный бокс.
Rect stackChildVisualRect(Rect rect, {double rotation = 0, double scale = 1}) {
  if (rotation == 0 && _scaleOf(scale) == 1.0) return rect;
  final corners = stackChildVisualCorners(
    rect,
    rotation: rotation,
    scale: scale,
  );
  var out = Rect.fromLTWH(corners.first.dx, corners.first.dy, 0, 0);
  for (final corner in corners.skip(1)) {
    out = out.expandToInclude(Rect.fromLTWH(corner.dx, corner.dy, 0, 0));
  }
  return out;
}

/// Где под полосой линейки лежит содержимое. Полоса рисуется поверх холста и
/// без этого прятала бы слой, придвинутый к краю: эти rect'ы линейка отдаёт
/// лёгкой дымкой, а плотной подложка остаётся только над пустым холстом.
/// Координаты — локальные для полосы; пустое пересечение в список не входит.
List<Rect> rulerContentGaps({required Rect band, required List<Rect> content}) {
  final gaps = <Rect>[];
  for (final rect in content) {
    final hole = rect.intersect(band);
    if (hole.isEmpty) continue;
    gaps.add(hole.shift(-band.topLeft));
  }
  return gaps;
}

/// Тап по объекту: точка проверяется в собственных осях бокса, поэтому в
/// повёрнутом слое попадает по картинке, а не по описанному вокруг неё rect'у
/// (и не по пустым углам вокруг неё).
bool stackChildContains(
  Offset point,
  Rect rect, {
  double rotation = 0,
  double scale = 1,
}) => rect.contains(
  rect.center +
      stackChildLocalVector(
        point - rect.center,
        rotation: rotation,
        scale: scale,
      ),
);

/// Вектор от центра бокса к краю, который данный жест закрепляет.
Offset _pinnedCornerVector(Rect rect, StackChildDragMode mode) {
  final half = Offset(rect.width / 2, rect.height / 2);
  final dx = switch (mode) {
    StackChildDragMode.resizeTL ||
    StackChildDragMode.resizeBL ||
    StackChildDragMode.resizeLeft => half.dx,
    StackChildDragMode.resizeTR ||
    StackChildDragMode.resizeBR ||
    StackChildDragMode.resizeRight => -half.dx,
    _ => 0.0,
  };
  final dy = switch (mode) {
    StackChildDragMode.resizeTL ||
    StackChildDragMode.resizeTR ||
    StackChildDragMode.resizeTop => half.dy,
    StackChildDragMode.resizeBL ||
    StackChildDragMode.resizeBR ||
    StackChildDragMode.resizeBottom => -half.dy,
    _ => 0.0,
  };
  return Offset(dx, dy);
}

/// Ресайз повёрнутого или масштабированного бокса ручкой: сторона идёт по
/// собственным осям объекта, а противоположный край остаётся на экране там,
/// где стоял.
///
/// Без этой поправки трансформация вокруг центра уносила объект при росте:
/// [applyStackChildDrag] двигает стороны модельного rect'а, а рисование
/// доворачивает результат — закрепленный угол съезжал по диагонали.
Rect resizeStackChildRect({
  required Rect start,
  required StackChildDragMode mode,
  required Offset delta,
  double rotation = 0,
  double scale = 1,
  bool keepAspect = false,
}) {
  if (mode == StackChildDragMode.move) return start.shift(delta);
  final s = _scaleOf(scale);
  if (rotation == 0 && s == 1.0) {
    return applyStackChildDrag(start, mode, delta, keepAspect: keepAspect);
  }
  final local = applyStackChildDrag(
    start,
    mode,
    stackChildLocalVector(delta, rotation: rotation, scale: s),
    keepAspect: keepAspect,
  );
  final anchor =
      start.center +
      stackChildVisualVector(
        _pinnedCornerVector(start, mode),
        rotation: rotation,
        scale: s,
      );
  return Rect.fromCenter(
    center:
        anchor -
        stackChildVisualVector(
          _pinnedCornerVector(local, mode),
          rotation: rotation,
          scale: s,
        ),
    width: local.width,
    height: local.height,
  );
}

/// Ресайз с клавиатуры (Alt+стрелка): растут правый и нижний край, левый
/// верхний якорь стоит — как в Figma. Отрицательная дельта упирается в
/// [kStackChildMinWidth]/[kStackChildMinHeight]. Рамкой канваса рост не
/// ограничивается: холст — это окно, а не стена, и авторский фон-спрайт
/// заведомо больше 720 px. Группа масштабируется аффинно, тем же способом,
/// что и за ручку.
List<ContentItem> nudgeResize({
  required List<ContentItem> children,
  required Set<String> ids,
  required Offset delta,
  required double height,
  double width = kStackCanvasWidth,
}) {
  if (delta == Offset.zero || ids.isEmpty) return children;
  final union = unionOfChildren(
    children: [
      for (final child in children)
        if (ids.contains(child.id)) child,
    ],
    height: height,
    width: width,
  );
  if (union == null) return children;
  final right = math.max(
    union.left + kStackChildMinWidth,
    union.right + delta.dx,
  );
  final bottom = math.max(
    union.top + kStackChildMinHeight,
    union.bottom + delta.dy,
  );
  final to = Rect.fromLTRB(union.left, union.top, right, bottom);
  if (to == union) return children;
  return [
    for (final child in children)
      if (!ids.contains(child.id))
        child
      else
        child.stackChildWithRect(
          scaleRectIntoGroup(child.stackChildRect(width, height), union, to),
          width,
          height,
        ),
  ];
}

/// Rect'ы невыделенных детей — источники линий прилипания.
List<Rect> otherRects({
  required List<ContentItem> children,
  required Set<String> excludeIds,
  required double height,
  double width = kStackCanvasWidth,
}) {
  return [
    for (final child in children)
      if (!excludeIds.contains(child.id)) child.stackChildRect(width, height),
  ];
}

/// Id детей, попавших в рамку выделения (в z-порядке).
///
/// Рамка цепляет объект и за частичное пересечение: «обвёл угол кнопки» —
/// значит хотел её выделить, а не промахнулся.
List<String> idsInRect({
  required List<ContentItem> children,
  required Rect rect,
  required double height,
  double width = kStackCanvasWidth,
  bool partial = true,
}) {
  // Rect нулевой площади формально «пересекает» всё, что его содержит, а тап
  // без движения рамкой не считается.
  if (rect.width <= 0 || rect.height <= 0) return const [];
  bool inside(Rect r) => partial
      ? rect.overlaps(r)
      : rect.contains(r.topLeft) && rect.contains(r.bottomRight);
  return [
    for (final child in children)
      if (inside(
        // Рамка выделения ловит то, что видно: повёрнутый или масштабированный
        // слой пересекается с рамкой своим визуальным габаритом.
        stackChildVisualRect(
          child.stackChildRect(width, height),
          rotation: child.rotation,
          scale: child.scale,
        ),
      ))
        child.id,
  ];
}

// ── Прилипление и модификаторы драга ───────────────────────────────────────

/// Порог прилипания в пикселях стека. Меньше — цепляешь соседа на каждом кадре
/// драга, больше — не цепляешь вообще.
const double kStackSnapThreshold = 6.0;

/// Итог прилипания: на что сместить группу (уже с поправкой) и какие линии
/// нарисовать — x вертикальных и y горизонтальных, в координатах стека.
class StackSnap {
  final Offset delta;
  final List<double> verticalGuides;
  final List<double> horizontalGuides;

  const StackSnap({
    required this.delta,
    this.verticalGuides = const [],
    this.horizontalGuides = const [],
  });
}

/// Прилипление драга группы к соседям, рамке канваса, пользовательским
/// направляющим ([guidesX]/[guidesY]) и (если задан шаг) к сетке.
///
/// [moving] — rect группы до смещения, [desired] — сдвиг из жеста. Ось, по
/// которой ни одна цель не попала в порог, остаётся с честным [desired]:
/// подтаскивать «примерно по вертикали», когда цепляться не за что, нельзя.
/// [gridStep] <= 0 — сетки нет. Направляющие конкурируют с остальными целями
/// на равных: берётся ближайшая, как и везде.
StackSnap snapDrag({
  required Rect moving,
  required Offset desired,
  required List<Rect> others,
  double canvasWidth = kStackCanvasWidth,
  double canvasHeight = 220,
  double threshold = kStackSnapThreshold,
  double gridStep = 0,
  List<double> guidesX = const [],
  List<double> guidesY = const [],
}) {
  final shifted = moving.shift(desired);
  final x = _snapAxis(
    sources: [shifted.left, shifted.center.dx, shifted.right],
    targets: [
      for (final r in others) ...[r.left, r.center.dx, r.right],
      ...guidesX,
      0,
      canvasWidth / 2,
      canvasWidth,
      ...gridLines(
        gridStep,
        shifted.left - threshold,
        shifted.right + threshold,
      ),
    ],
    threshold: threshold,
  );
  final y = _snapAxis(
    sources: [shifted.top, shifted.center.dy, shifted.bottom],
    targets: [
      for (final r in others) ...[r.top, r.center.dy, r.bottom],
      ...guidesY,
      0,
      canvasHeight / 2,
      canvasHeight,
      ...gridLines(
        gridStep,
        shifted.top - threshold,
        shifted.bottom + threshold,
      ),
    ],
    threshold: threshold,
  );

  return StackSnap(
    delta: Offset(desired.dx + (x?.adjust ?? 0), desired.dy + (y?.adjust ?? 0)),
    verticalGuides: [if (x != null) x.target],
    horizontalGuides: [if (y != null) y.target],
  );
}

/// Линии сетки с шагом [step] в интервале [from..to] — цели прилипания.
/// Нулевой и отрицательный шаг = сетка выключена.
List<double> gridLines(double step, double from, double to) {
  if (step <= 0) return const [];
  return [for (var v = (from / step).ceil() * step; v <= to; v += step) v];
}

/// Прилипление ресайза: цепляются только свободные края rect'а (те, что трогает
/// ручка — угол или середина стороны), поэтому поправка по каждой оси
/// считается отдельно. В отличие от [snapDrag], [StackSnap.delta] — не итог, а
/// прибавка к дельте жеста.
StackSnap snapResize({
  required Rect rect,
  required StackChildDragMode mode,
  required List<Rect> others,
  double canvasWidth = kStackCanvasWidth,
  double canvasHeight = 220,
  double threshold = kStackSnapThreshold,
  double gridStep = 0,
  List<double> guidesX = const [],
  List<double> guidesY = const [],
}) {
  final touchesLeft =
      mode == StackChildDragMode.resizeTL ||
      mode == StackChildDragMode.resizeBL ||
      mode == StackChildDragMode.resizeLeft;
  final touchesRight =
      mode == StackChildDragMode.resizeTR ||
      mode == StackChildDragMode.resizeBR ||
      mode == StackChildDragMode.resizeRight;
  final touchesTop =
      mode == StackChildDragMode.resizeTL ||
      mode == StackChildDragMode.resizeTR ||
      mode == StackChildDragMode.resizeTop;
  final touchesBottom =
      mode == StackChildDragMode.resizeBL ||
      mode == StackChildDragMode.resizeBR ||
      mode == StackChildDragMode.resizeBottom;
  final x = _snapAxis(
    sources: [if (touchesLeft) rect.left else if (touchesRight) rect.right],
    targets: [
      ..._axisTargets(
        others: others,
        horizontal: true,
        canvasSize: canvasWidth,
      ),
      ...gridLines(gridStep, rect.left - threshold, rect.right + threshold),
      ...guidesX,
    ],
    threshold: threshold,
  );
  final y = _snapAxis(
    sources: [if (touchesTop) rect.top else if (touchesBottom) rect.bottom],
    targets: [
      ..._axisTargets(
        others: others,
        horizontal: false,
        canvasSize: canvasHeight,
      ),
      ...gridLines(gridStep, rect.top - threshold, rect.bottom + threshold),
      ...guidesY,
    ],
    threshold: threshold,
  );
  return StackSnap(
    delta: Offset(x?.adjust ?? 0, y?.adjust ?? 0),
    verticalGuides: [if (x != null) x.target],
    horizontalGuides: [if (y != null) y.target],
  );
}

List<double> _axisTargets({
  required List<Rect> others,
  required bool horizontal,
  required double canvasSize,
}) => [
  for (final r in others)
    if (horizontal) ...[
      r.left,
      r.center.dx,
      r.right,
    ] else ...[
      r.top,
      r.center.dy,
      r.bottom,
    ],
  0,
  canvasSize / 2,
  canvasSize,
];

class _SnapHit {
  final double adjust;
  final double target;

  const _SnapHit(this.adjust, this.target);
}

/// Ближайшая цель в пределах порога: край или центр движимой группы к краю
/// или центру соседа/рамки.
_SnapHit? _snapAxis({
  required List<double> sources,
  required List<double> targets,
  required double threshold,
}) {
  _SnapHit? best;
  for (final source in sources) {
    for (final target in targets) {
      final adjust = target - source;
      if (adjust.abs() > threshold) continue;
      if (best == null || adjust.abs() < best.adjust.abs()) {
        best = _SnapHit(adjust, target);
      }
    }
  }
  return best;
}

/// Shift на ходу: движение остаётся на одной оси — той, куда палец ушёл
/// дальше. Решаем по уже готовому смещению, иначе прилипание вернуло бы
/// поперечный сдвиг, которого пользователь не делал.
Offset constrainToAxis(Offset delta, {required bool locked}) {
  if (!locked) return delta;
  return delta.dx.abs() >= delta.dy.abs()
      ? Offset(delta.dx, 0)
      : Offset(0, delta.dy);
}

// ── Замеры при драге ───────────────────────────────────────────────────────

/// Расстояние от тащимого объекта до соседа (или края холста): отрезок вдоль
/// измеряемой оси от [from] до [to] на высоте (или ширине) [line], подпись —
/// [gap] px стека. [horizontal] — измеряем по x; тогда линия горизонтальная.
class StackMeasure {
  final bool horizontal;
  final double line;
  final double from;
  final double to;
  final double gap;

  const StackMeasure({
    required this.horizontal,
    required this.line,
    required this.from,
    required this.to,
    required this.gap,
  });
}

/// Ближайшие зазоры вокруг тащимого rect'а — по две на каждую ось, как их
/// показывает Figma, пока объект на ходу. Сосед считается только тогда, когда
/// он перекрывает движимый rect поперёк измеряемой оси: зазор «до объекта по
/// диагонали» невозможно ни прочитать, ни выровнять. Если по направлению
/// ничего нет — мерим до края холста.
List<StackMeasure> measureDrag({
  required Rect moving,
  required List<Rect> others,
  double canvasWidth = kStackCanvasWidth,
  double canvasHeight = 220,
}) => [
  ..._measureAxis(
    horizontal: true,
    moving: moving,
    others: others,
    canvasSize: canvasWidth,
  ),
  ..._measureAxis(
    horizontal: false,
    moving: moving,
    others: others,
    canvasSize: canvasHeight,
  ),
];

List<StackMeasure> _measureAxis({
  required bool horizontal,
  required Rect moving,
  required List<Rect> others,
  required double canvasSize,
}) {
  double start(Rect r) => horizontal ? r.left : r.top;
  double end(Rect r) => horizontal ? r.right : r.bottom;
  double crossStart(Rect r) => horizontal ? r.top : r.left;
  double crossEnd(Rect r) => horizontal ? r.bottom : r.right;

  final leading = start(moving);
  final trailing = end(moving);
  double? before;
  double? after;
  for (final r in others) {
    // Касание краями — ещё не сосед: дырки между ними нет.
    if (crossEnd(r) <= crossStart(moving) ||
        crossStart(r) >= crossEnd(moving)) {
      continue;
    }
    if (end(r) <= leading && (before == null || end(r) > before)) {
      before = end(r);
    }
    if (start(r) >= trailing && (after == null || start(r) < after)) {
      after = start(r);
    }
  }
  final line = horizontal ? moving.center.dy : moving.center.dx;
  final beforeEdge = before ?? 0;
  final afterEdge = after ?? canvasSize;
  return [
    if (leading - beforeEdge >= 0)
      StackMeasure(
        horizontal: horizontal,
        line: line,
        from: beforeEdge,
        to: leading,
        gap: leading - beforeEdge,
      ),
    if (afterEdge - trailing >= 0)
      StackMeasure(
        horizontal: horizontal,
        line: line,
        from: trailing,
        to: afterEdge,
        gap: afterEdge - trailing,
      ),
  ];
}

// ── Перенос стиля ──────────────────────────────────────────────────────────

/// Перенести оформление с [source] на детей [ids]: заливку, скругление,
/// отступ, шрифт, прозрачность и масштаб, стиль кнопки и режим подгонки
/// текста. Поворот остаётся свой: это геометрия, а не вид.
///
/// Всё остальное остаётся своим: геометрия, текст, имена слоёв и поведения.
/// «Стиль» — это вид, а не то, что слой делает и где стоит. Пустое поле в
/// источнике переносится как пустое: «без заливки» — тоже осознанный вид, и
/// вставка обязана давать именно его, а не оставлять цвет цели.
List<ContentItem> pasteStyle({
  required List<ContentItem> children,
  required Set<String> ids,
  required ContentItem source,
}) {
  final styled = [
    for (final c in children)
      if (!ids.contains(c.id))
        c
      else
        c.copyWith(
          backgroundColor: source.backgroundColor,
          clearBackgroundColor: source.backgroundColor == null,
          borderRadius: source.borderRadius,
          clearBorderRadius: source.borderRadius == null,
          padding: source.padding,
          clearPadding: source.padding == null,
          fontFamily: source.fontFamily,
          clearFontFamily: source.fontFamily == null,
          textSize: source.textSize,
          clearTextSize: source.textSize == null,
          buttonStyle: source.buttonStyle,
          clearButtonStyle: source.buttonStyle == null,
          opacity: source.opacity,
          scale: source.scale,
          textFit: source.textFit,
        ),
  ];
  // Числа выше переедают сами, а формулы — только у тех же полей: иначе цель
  // получила бы формулу отступа, которого ей не прилепили. `null` у источника
  // значит «формулы нет» — снимаем её и у цели, вместе с числом.
  return [
    for (final c in styled)
      if (!ids.contains(c.id))
        c
      else
        c.applyExprsFrom(source, const ['borderRadius', 'padding', 'textSize']),
  ];
}

/// Формулы (`numericExprs`) перечисленных полей от другого слоя. Пустое
/// значение снимает формулу у цели — вместе с числом того же поля.
extension on ContentItem {
  ContentItem applyExprsFrom(ContentItem source, List<String> fields) {
    var item = this;
    for (final field in fields) {
      item = item.withNumericExpr(field, source.numericExpr(field));
    }
    return item;
  }
}

// ── Выравнивание и распределение ───────────────────────────────────────────

/// Что совмещаем: край или центр ограничивающего rect'а группы.
enum StackAlign { left, centerX, right, top, centerY, bottom }

/// Выровнять выделенных по общему краю/центру группы. Один выделенный — по
/// рамке канваса: так ищут «центрировать заголовок».
List<ContentItem> alignChildren({
  required List<ContentItem> children,
  required Set<String> ids,
  required StackAlign align,
  required double height,
  double width = kStackCanvasWidth,
}) {
  final rects = [
    for (final c in children)
      if (ids.contains(c.id)) c.stackChildRect(width, height),
  ];
  if (rects.isEmpty) return children;
  final reference = rects.length > 1
      ? rects.reduce((a, b) => a.expandToInclude(b))
      : Rect.fromLTWH(0, 0, width, height);
  final horizontal =
      align != StackAlign.top &&
      align != StackAlign.centerY &&
      align != StackAlign.bottom;

  double shiftOf(Rect r) => switch (align) {
    StackAlign.left => reference.left - r.left,
    StackAlign.centerX => reference.center.dx - r.center.dx,
    StackAlign.right => reference.right - r.right,
    StackAlign.top => reference.top - r.top,
    StackAlign.centerY => reference.center.dy - r.center.dy,
    StackAlign.bottom => reference.bottom - r.bottom,
  };

  final next = <ContentItem>[];
  for (final child in children) {
    if (!ids.contains(child.id)) {
      next.add(child);
      continue;
    }
    final r = child.stackChildRect(width, height);
    final d = shiftOf(r);
    next.add(
      child.stackChildWithRect(
        r.shift(horizontal ? Offset(d, 0) : Offset(0, d)),
        width,
        height,
      ),
    );
  }
  return next;
}

/// Равные промежутки между выделенными вдоль оси; крайние остаются на своих
/// местах. Меньше трёх объектов промежутков не бывает — список возвращается
/// как есть, чтобы не плодить пустые шаги истории.
List<ContentItem> distributeChildren({
  required List<ContentItem> children,
  required Set<String> ids,
  required bool horizontal,
  required double height,
  double width = kStackCanvasWidth,
}) {
  final movers = [
    for (final c in children)
      if (ids.contains(c.id)) c,
  ];
  if (movers.length < 3) return children;

  double startOf(Rect r) => horizontal ? r.left : r.top;
  double sizeOf(Rect r) => horizontal ? r.width : r.height;
  final rects = {for (final c in movers) c.id: c.stackChildRect(width, height)};
  movers.sort((a, b) => startOf(rects[a.id]!).compareTo(startOf(rects[b.id]!)));

  final first = rects[movers.first.id]!;
  final last = rects[movers.last.id]!;
  final span = startOf(last) + sizeOf(last) - startOf(first);
  final sizes = movers.fold<double>(0, (sum, c) => sum + sizeOf(rects[c.id]!));
  final gap = (span - sizes) / (movers.length - 1);

  // Расстановка идёт вдоль оси, а обратно список собирается в исходном
  // z-порядке: распределение не должно перетасовывать слои.
  final placed = <String, ContentItem>{};
  var cursor = startOf(first);
  for (final c in movers) {
    final r = rects[c.id]!;
    placed[c.id] = c.stackChildWithRect(
      horizontal
          ? Rect.fromLTWH(cursor, r.top, r.width, r.height)
          : Rect.fromLTWH(r.left, cursor, r.width, r.height),
      width,
      height,
    );
    cursor += sizeOf(r) + gap;
  }
  return [for (final c in children) placed[c.id] ?? c];
}

// ── Якоря ──────────────────────────────────────────────────────────────────

/// Смена якорей слоя без прыжка: rect остаётся тем же, смещения пересчитываются
/// от новых якорей. Это то, чего не хватало при вёрстке интерфейса: чтобы
/// прижать плашку к правому нижнему углу, её раньше приходилось двигать
/// заново — и промахиваться.
///
/// Stretch-пресеты (0 и 1 на одной оси) дополнительно притягивают эту ось к
/// краям холста: «растянуть по ширине» обязано означать «во всю ширину», а не
/// «тот же rect, но записанный иначе».
ContentItem applyStackAnchorPreset(
  ContentItem child, {
  required List<double> anchors,
  required double width,
  required double height,
}) {
  final rect = child.stackChildRect(width, height);
  final al = anchors[0], at = anchors[1], ar = anchors[2], ab = anchors[3];
  final stretchH = al == 0.0 && ar == 1.0;
  final stretchV = at == 0.0 && ab == 1.0;
  return child.copyWith(
    anchorLeft: al,
    anchorTop: at,
    anchorRight: ar,
    anchorBottom: ab,
    offsetLeft: stretchH ? 0.0 : rect.left - al * width,
    offsetTop: stretchV ? 0.0 : rect.top - at * height,
    offsetRight: stretchH ? 0.0 : rect.right - ar * width,
    offsetBottom: stretchV ? 0.0 : rect.bottom - ab * height,
  );
}

// ── Масштаб стека вместе с содержимым ──────────────────────────────────────

/// Как содержимое едет при смене размера холста. Выбор отдаён автору: у двух
/// смыслов одинакового запроса «уменьши стек» разные последствия.
enum StackContentScale {
  /// Менять только рамку: слои остаются в старых пикселях. Это прежний смысл
  /// поля и тяги за край — правка обводки не должна сама двигать вёрстку,
  /// поэтому масштаб содержимого включается явно.
  keep,

  /// Один множитель на обе оси — тот, которым изменилась правая ось. Макет
  /// остаётся похожим на себя: круглые кнопки круглые, но в новом холсте может
  /// остаться пустое место.
  uniform,

  /// Каждая ось своим множителем: макет заполняет новый холст целиком, зато
  /// панель, ставшая уже, останется того же роста.
  stretch,
}

/// Множители (по x, по y) содержимого нового холста. Для uniform берётся ось,
/// которую реально правили: при 720→360 по ширине это 0.5 на обе оси, а не
/// среднее из 0.5 и 1. [StackContentScale.keep] — единичные.
({double x, double y}) stackContentFactors({
  required double fromWidth,
  required double fromHeight,
  required double toWidth,
  required double toHeight,
  required StackContentScale mode,
}) {
  bool sane(double v) => v.isFinite && v > 0;
  if (!sane(fromWidth) ||
      !sane(fromHeight) ||
      !sane(toWidth) ||
      !sane(toHeight)) {
    return (x: 1, y: 1);
  }
  final sx = toWidth / fromWidth;
  final sy = toHeight / fromHeight;
  if (mode == StackContentScale.keep) return (x: 1, y: 1);
  if (mode == StackContentScale.uniform) {
    final axis = sx != 1 ? sx : sy;
    return (x: axis, y: axis);
  }
  return (x: sx, y: sy);
}

/// Сменили размер холста — слои уезжают вместе с ним. Без этого «сделать макет
/// вдвое меньше» означает ручную правку каждого объекта: холст 360, а кнопка
/// всё ещё на 720.
///
/// Якоря остаются своими — offset'ы под новый холст пересчитывает
/// [ContentItem.stackChildWithRect]. Одномерные величины (шрифт, отступ,
/// скругление, стиль кнопки) ведутся средним из множителей: у них нет оси, а
/// оставить текст прежнего размера в уменьшенной рамке — значит получить
/// переполнение вместо масштаба. [ContentItem.scale], поворот и прозрачность не
/// трогаем: это множители вида, масштаб они уже учитывают.
List<ContentItem> scaleStackContent({
  required List<ContentItem> children,
  required double fromWidth,
  required double fromHeight,
  required double toWidth,
  required double toHeight,
  StackContentScale mode = StackContentScale.uniform,
}) {
  final factors = stackContentFactors(
    fromWidth: fromWidth,
    fromHeight: fromHeight,
    toWidth: toWidth,
    toHeight: toHeight,
    mode: mode,
  );
  final sx = factors.x;
  final sy = factors.y;
  if (sx == 1 && sy == 1) return children;
  final unit = math.sqrt(sx * sy);

  ContentItem scaled(ContentItem c) {
    final rect = c.stackChildRect(fromWidth, fromHeight);
    final next = Rect.fromLTWH(
      (rect.left * sx).roundToDouble(),
      (rect.top * sy).roundToDouble(),
      (rect.width * sx).roundToDouble(),
      (rect.height * sy).roundToDouble(),
    );
    return c
        .stackChildWithRect(next, toWidth, toHeight)
        .copyWith(
          textSize: _scaledLength(c.textSize, unit),
          padding: _scaledLength(c.padding, unit),
          borderRadius: _scaledLength(c.borderRadius, unit),
          itemSpacing: _scaledLength(c.itemSpacing, unit),
          buttonStyle: c.buttonStyle == null
              ? null
              : _scaleButtonStyle(c.buttonStyle!, unit),
        );
  }

  return [for (final c in children) scaled(c)];
}

/// Одномерная величина стиля. Дюймы до пикселя, не до целого: разрядка в 0.4
/// при целом округлении стала бы нулём, то есть правка «в пишем стек» украла бы
/// у автора настройку, которую он не просил трогать.
double? _scaledLength(double? value, double unit) =>
    value == null ? null : (value * unit * 100).roundToDouble() / 100;

/// Плоская кнопка несёт размеры в своём стиле: надпись, рамка, паддинги и
/// модуль формы. Без них кнопка уменьшается корпусом, а текст на ней остаётся
/// старого кегля.
ButtonStyleConfig _scaleButtonStyle(ButtonStyleConfig s, double unit) =>
    s.copyWith(
      moduleSize: (s.moduleSize * unit * 100).roundToDouble() / 100,
      textSize: _scaledLength(s.textSize, unit),
      letterSpacing: _scaledLength(s.letterSpacing, unit),
      borderRadius: _scaledLength(s.borderRadius, unit),
      borderWidth: _scaledLength(s.borderWidth, unit),
      shadowBlur: _scaledLength(s.shadowBlur, unit),
      shadowOffsetX: _scaledLength(s.shadowOffsetX, unit),
      shadowOffsetY: _scaledLength(s.shadowOffsetY, unit),
      paddingH: _scaledLength(s.paddingH, unit),
      paddingV: _scaledLength(s.paddingV, unit),
    );

/// Направляющие живут в пикселях от края холста, поэтому при масштабе стека
/// они едут по своей оси — иначе линия, притянутая к середине макета, стоит на
/// старой координате.
List<double> scaleStackGuides({
  required List<double> guides,
  required double factor,
}) => [for (final g in guides) (g * factor).roundToDouble()];
