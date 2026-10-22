// Тап по палитре должен вставить блок туда, куда автор смотрит, а не в конец
// списка. Правило «разрыв, ближайший к центру видимой области» живёт здесь —
// отдельно от экрана, чтобы его было чем проверить без сборки редактора.

import 'dart:ui';

import 'package:canvas_app/features/editor/screens/visual_script_editor/block_insertion.dart';
import 'package:flutter_test/flutter_test.dart';

Rect _rectAt(double top, {double height = 100}) =>
    Rect.fromLTWH(0, top, 400, height);

/// Viewport 100-700, то есть центр на 400.
const Rect _viewport = Rect.fromLTWH(0, 100, 400, 600);

void main() {
  test('разрыв = середина щели, у краёв списка — верх первого и низ последнего',
      () {
    final rects = [_rectAt(200), _rectAt(320)];

    expect(gapCenterY(rects, 0), 200);
    expect(gapCenterY(rects, 1), 310);
    expect(gapCenterY(rects, 2), 420);
    // Индекс за краем списка не улетает в бесконечность: вставка всё равно в
    // конец, а координата — у последнего блока.
    expect(gapCenterY(rects, 99), 420);
    expect(gapCenterY(const [], 0), isNull);
  });

  test('выбирается разрыв ближе всего к центру экрана, а не конец списка', () {
    // Блоки 150-250, 260-360, 370-470, 480-580. Центр 400 лежит внутри
    // третьего, ближайшая щель — перед ним (365), а не после него (475).
    final picked = pickBlockInsertion(
      lists: [
        [
          _rectAt(150),
          _rectAt(260),
          _rectAt(370),
          _rectAt(480),
        ],
      ],
      viewport: _viewport,
    );

    expect(picked, isNotNull);
    expect(picked!.insertIndex, 2);
    expect(picked.listIndex, 0);
  });

  test('прокрутка меняет выбор: блок встаёт под новым центром', () {
    // Те же блоки плюс два ниже, экран уехал: viewport 600-1200, центр 900.
    final picked = pickBlockInsertion(
      lists: [
        [
          _rectAt(150),
          _rectAt(260),
          _rectAt(370),
          _rectAt(480),
          _rectAt(830),
          _rectAt(960),
        ],
      ],
      viewport: const Rect.fromLTWH(0, 600, 400, 600),
    );

    expect(picked!.insertIndex, 5);
  });

  test('разрывы вне экрана проигрывают: до них дальше от центра', () {
    // Первый список уехал за верхний край (щели на -30 и 80), второй стоит
    // посреди экрана, и его верхняя щель — ровно по центру (400).
    final picked = pickBlockInsertion(
      lists: [
        [_rectAt(-30, height: 110)],
        [_rectAt(400, height: 100), _rectAt(520, height: 100)],
      ],
      viewport: _viewport,
    );

    expect(picked!.listIndex, 1);
    expect(picked.insertIndex, 0);
  });

  test('из нескольких событий выбирается то, чей разрыв ближе к центру', () {
    final picked = pickBlockInsertion(
      lists: [
        [_rectAt(120, height: 90)],
        [_rectAt(380, height: 90)],
      ],
      viewport: _viewport,
    );

    expect(picked!.listIndex, 1);
    expect(picked.insertIndex, 0);
  });

  test('при равных расстояниях выигрывает разрыв выше по списку', () {
    // 300 и 500 одинаково далеко от центра 400: щель под первым событием и
    // щель над вторым. Побеждает та, что выше, — иначе выбор зависел бы от
    // порядка обхода.
    final picked = pickBlockInsertion(
      lists: [
        [_rectAt(200, height: 100)],
        [_rectAt(500, height: 100)],
      ],
      viewport: _viewport,
    );

    expect(picked!.listIndex, 0);
    expect(picked.insertIndex, 1);
  });

  test('замерить нечего — решения нет, вызывающий решает сам', () {
    expect(pickBlockInsertion(lists: const [], viewport: _viewport), isNull);
    expect(
      pickBlockInsertion(
        lists: const <MeasuredBlocks>[[]],
        viewport: _viewport,
      ),
      isNull,
    );
  });
}
