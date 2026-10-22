import 'dart:ui' show Rect;

// ============================================================================
//  КУДА ВСТАВЛЯТЬ БЛОК
// ============================================================================
//
//  Раньше выбранный в палитре блок «зависал» плавающей карточкой, и автор
//  должен был притащить её пальцем в нужный разрыв списка. Тап по палитре
//  должен давать результат сразу: блок появляется там, куда человек смотрит.
//
//  «Смотрит» = разрыв между блоками, ближайший к центру видимой области.
//  Позиции берутся из реальных экранных координат блоков (GlobalKey есть у
//  каждого блока списка), поэтому правило работает и после прокрутки, и в
//  скрипте с несколькими событиями.
//
//  Отдельного условия «не вылезти за экран» тут нет намеренно: центр
//  симметричен, поэтому любой разрыв вне viewport дальше от него, чем любой
//  разрыв внутри. Достаточно одного argmin.
// ============================================================================

/// Место вставки: [listIndex] — индекс списка-владельца в [lists],
/// [insertIndex] — позиция в нём (0 = перед первым блоком).
typedef BlockInsertion = ({int listIndex, int insertIndex});

/// Один список-владельца: прямоугольники его блоков в экраных координатах,
/// в том же порядке, что и сами блоки.
typedef MeasuredBlocks = List<Rect>;

/// Экранная координата разрыва [gapIndex]: 0 — верх первого блока,
/// [rects].length — низ последнего, иначе середина щели между соседями
/// (именно там лежит DragTarget вставки в ReorderableBlockList).
double? gapCenterY(MeasuredBlocks rects, int gapIndex) {
  if (rects.isEmpty) return null;
  if (gapIndex <= 0) return rects.first.top;
  if (gapIndex >= rects.length) return rects.last.bottom;
  return (rects[gapIndex - 1].bottom + rects[gapIndex].top) / 2;
}

/// Ближайший к центру [viewport] разрыв. При равных расстояниях выигрывает
/// тот, что выше по списку: вставка «перед блоком» предсказуемее, чем «после».
///
/// Возвращает null, если замерить нечего (списки пустые или блоки ещё не
/// построены) — вызывающий тогда решает сам, куда класть блок.
BlockInsertion? pickBlockInsertion({
  required List<MeasuredBlocks> lists,
  required Rect viewport,
}) {
  final centerY = viewport.center.dy;

  BlockInsertion? best;
  double bestDistance = double.infinity;

  for (int listIndex = 0; listIndex < lists.length; listIndex++) {
    final rects = lists[listIndex];
    for (int gap = 0; gap <= rects.length; gap++) {
      final y = gapCenterY(rects, gap);
      if (y == null) continue;
      final distance = (y - centerY).abs();
      if (distance < bestDistance) {
        best = (listIndex: listIndex, insertIndex: gap);
        bestDistance = distance;
      }
    }
  }

  return best;
}
