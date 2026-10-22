import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

void main() {
  test('stack: round-trip stackHeight, якоря и смещения', () {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 240,
      children: [
        ContentItem(
          id: 'c1',
          type: 'text',
          text: 'hi',
          anchorLeft: 0,
          anchorTop: 0,
          anchorRight: 0,
          anchorBottom: 0,
          offsetLeft: 12,
          offsetTop: 8,
        ),
      ],
    );

    final json = stack.toJson();
    expect(json['stackHeight'], 240.0);
    expect(json['children'][0]['offsetTop'], 8.0);
    // Якоря у ребёнка все 0 (не дефолт 0.5) — пишутся.
    expect(json['children'][0]['anchorRight'], 0.0);
    // Дефолтные offsetRight/offsetBottom (0) не пишутся.
    expect(json['children'][0].containsKey('offsetRight'), isFalse);
    expect(json['children'][0].containsKey('offsetBottom'), isFalse);

    final restored = ContentItem.fromJson(json);
    expect(restored.stackHeight, 240.0);
    final child = restored.children!.first;
    expect(child.anchorLeft, 0.0);
    expect(child.anchorTop, 0.0);
    expect(child.offsetLeft, 12.0);
    expect(child.offsetTop, 8.0);
  });

  test('stack: дефолт ребёнка — по центру', () {
    final child = ContentItem.fromJson(const {
      'id': 'c1',
      'type': 'text',
      'text': 'hi',
    });
    expect(child.anchorLeft, 0.5);
    expect(child.anchorTop, 0.5);
    expect(child.anchorRight, 0.5);
    expect(child.anchorBottom, 0.5);
    expect(child.offsetLeft, 0.0);
  });

  test(
    'opacity/rotation/scale: дефолты не сериализуются, заданные — переживают round-trip',
    () {
      final plain = ContentItem.fromJson(const {
        'id': 'c1',
        'type': 'text',
        'text': 'hi',
      });
      expect(plain.opacity, 1.0);
      expect(plain.rotation, 0.0);
      expect(plain.scale, 1.0);
      expect(plain.toJson().containsKey('opacity'), isFalse);
      expect(plain.toJson().containsKey('rotation'), isFalse);
      expect(plain.toJson().containsKey('scale'), isFalse);

      final styled = plain.copyWith(opacity: 0.4, rotation: -30, scale: 1.8);
      final restored = ContentItem.fromJson(styled.toJson());
      expect(restored.opacity, 0.4);
      expect(restored.rotation, -30.0);
      // Геометрия от стиля не зависит.
      expect(restored.anchorLeft, plain.anchorLeft);
      expect(restored.offsetLeft, plain.offsetLeft);
    },
  );

  test('stackChildRect: Godot-модель', () {
    final child = ContentItem(
      id: 'c1',
      type: 'text',
      anchorLeft: 0,
      anchorTop: 0,
      anchorRight: 1,
      anchorBottom: 1,
      offsetLeft: 10,
      offsetTop: 20,
      offsetRight: -10,
      offsetBottom: -20,
    );
    // left=0*400+10=10, right=1*400-10=390, top=0*200+20=20, bottom=200-20=180
    final rect = child.stackChildRect(400, 200);
    expect(rect.left, 10);
    expect(rect.top, 20);
    expect(rect.right, 390);
    expect(rect.bottom, 180);
  });

  test('stackChildWithRect: двигает offsets, якоря не трогает', () {
    // Центр-якорный ребёнок 160×44 в стеке 720×300.
    final child = ContentItem(
      id: 'c1',
      type: 'text',
      anchorLeft: 0.5,
      anchorTop: 0.5,
      anchorRight: 0.5,
      anchorBottom: 0.5,
      offsetLeft: -80,
      offsetTop: -22,
      offsetRight: 80,
      offsetBottom: 22,
    );
    final start = child.stackChildRect(720, 300);
    // Перемещаем на (30, 10) — новые offsets симметрично сдвигаются.
    final moved = child.stackChildWithRect(
      start.shift(const Offset(30, 10)),
      720,
      300,
    );
    expect(moved.offsetLeft, closeTo(-50, 0.001));
    expect(moved.offsetRight, closeTo(110, 0.001));
    expect(moved.offsetTop, closeTo(-12, 0.001));
    expect(moved.offsetBottom, closeTo(32, 0.001));
    expect(moved.anchorLeft, 0.5); // якоря не изменились
    expect(moved.anchorRight, 0.5);
    // round-trip rect совпадает
    final r2 = moved.stackChildRect(720, 300);
    expect(r2.left, closeTo(start.left + 30, 0.001));
    expect(r2.top, closeTo(start.top + 10, 0.001));
    expect(r2.width, closeTo(160, 0.001));
    expect(r2.height, closeTo(44, 0.001));
  });

  test('applyStackChildDrag: move и 4 угла resize', () {
    const start = Rect.fromLTRB(100, 50, 260, 150);
    const d = Offset(12, -8);

    expect(
      applyStackChildDrag(start, StackChildDragMode.move, d),
      start.shift(d),
    );

    expect(
      applyStackChildDrag(start, StackChildDragMode.resizeTL, d),
      const Rect.fromLTRB(112, 42, 260, 150),
    );
    expect(
      applyStackChildDrag(start, StackChildDragMode.resizeTR, d),
      const Rect.fromLTRB(100, 42, 272, 150),
    );
    expect(
      applyStackChildDrag(start, StackChildDragMode.resizeBL, d),
      const Rect.fromLTRB(112, 50, 260, 142),
    );
    expect(
      applyStackChildDrag(start, StackChildDragMode.resizeBR, d),
      const Rect.fromLTRB(100, 50, 272, 142),
    );
  });

  test('applyStackChildDrag: середины сторон тянут одну ось', () {
    const start = Rect.fromLTRB(100, 50, 260, 150);
    const d = Offset(12, -8);

    expect(
      applyStackChildDrag(start, StackChildDragMode.resizeLeft, d),
      const Rect.fromLTRB(112, 50, 260, 150),
    );
    expect(
      applyStackChildDrag(start, StackChildDragMode.resizeRight, d),
      const Rect.fromLTRB(100, 50, 272, 150),
    );
    expect(
      applyStackChildDrag(start, StackChildDragMode.resizeTop, d),
      const Rect.fromLTRB(100, 42, 260, 150),
    );
    expect(
      applyStackChildDrag(start, StackChildDragMode.resizeBottom, d),
      const Rect.fromLTRB(100, 50, 260, 142),
    );
  });

  test('applyStackChildDrag: Shift-пропорции держат только угловые ручки', () {
    const start = Rect.fromLTRB(100, 50, 260, 150);
    const d = Offset(12, -8);

    // Угол с keepAspect меняет обе оси: ведущая здесь высота (палец ушёл
    // дальше относительно своего размера), ширина подстраивается под неё.
    final corner = applyStackChildDrag(
      start,
      StackChildDragMode.resizeBR,
      d,
      keepAspect: true,
    );
    expect(corner.bottom, 142);
    expect(corner.width / corner.height, closeTo(1.6, 0.001));
    expect(corner.right, isNot(272));

    // …а середина стороны остаётся одноосной: вторая ось растётся сама.
    expect(
      applyStackChildDrag(
        start,
        StackChildDragMode.resizeRight,
        d,
        keepAspect: true,
      ),
      const Rect.fromLTRB(100, 50, 272, 150),
    );
    expect(
      applyStackChildDrag(
        start,
        StackChildDragMode.resizeTop,
        d,
        keepAspect: true,
      ),
      const Rect.fromLTRB(100, 42, 260, 150),
    );
  });

  test('stackChildWithRect + applyStackChildDrag: визуальный драг целиком', () {
    // Симуляция: драг за верхний-левый угол центрированного ребёнка.
    final child = ContentItem(
      id: 'c1',
      type: 'text',
      anchorLeft: 0.5,
      anchorTop: 0.5,
      anchorRight: 0.5,
      anchorBottom: 0.5,
      offsetLeft: -80,
      offsetTop: -22,
      offsetRight: 80,
      offsetBottom: 22,
    );
    final start = child.stackChildRect(720, 300);
    final dragged = applyStackChildDrag(
      start,
      StackChildDragMode.resizeBR,
      const Offset(40, 18),
    );
    final updated = child.stackChildWithRect(dragged, 720, 300);
    // Правый нижний угол уехал, левый верхний на месте.
    expect(updated.stackChildRect(720, 300).left, closeTo(start.left, 0.001));
    expect(updated.stackChildRect(720, 300).top, closeTo(start.top, 0.001));
    expect(
      updated.stackChildRect(720, 300).right,
      closeTo(start.right + 40, 0.001),
    );
    expect(
      updated.stackChildRect(720, 300).bottom,
      closeTo(start.bottom + 18, 0.001),
    );
    expect(updated.offsetRight, closeTo(120, 0.001));
    expect(updated.offsetBottom, closeTo(40, 0.001));
  });

  test('keepAspect: пропорции держатся, ведущая — ось с большим уходом', () {
    // 160×100, т.е. 1.6: противоложный угол (верх-лево) на месте.
    const start = Rect.fromLTRB(100, 50, 260, 150);

    // Только по x: высота добирается по пропорции.
    expect(
      applyStackChildDrag(
        start,
        StackChildDragMode.resizeBR,
        const Offset(40, 0),
        keepAspect: true,
      ),
      const Rect.fromLTRB(100, 50, 300, 175),
    );

    // Здесь палец сильнее ушёл по y (60 из 100 против 40 из 160), поэтому
    // ширина считается от высоты: 160 * 1.6 = 256.
    expect(
      applyStackChildDrag(
        start,
        StackChildDragMode.resizeBR,
        const Offset(40, 60),
        keepAspect: true,
      ),
      const Rect.fromLTRB(100, 50, 356, 210),
    );
  });

  test('keepAspect: противоположный угол закреплён для каждого из 4', () {
    const start = Rect.fromLTRB(100, 50, 260, 150);
    const corners = {
      StackChildDragMode.resizeTL: Offset(-40, -25),
      StackChildDragMode.resizeTR: Offset(40, -25),
      StackChildDragMode.resizeBL: Offset(-40, 25),
      StackChildDragMode.resizeBR: Offset(40, 25),
    };

    for (final entry in corners.entries) {
      final rect = applyStackChildDrag(
        start,
        entry.key,
        entry.value,
        keepAspect: true,
      );
      expect(
        rect.width / rect.height,
        closeTo(1.6, 0.001),
        reason: '${entry.key}',
      );
      final anchored = switch (entry.key) {
        StackChildDragMode.resizeTL => start.bottomRight,
        StackChildDragMode.resizeTR => start.bottomLeft,
        StackChildDragMode.resizeBL => start.topRight,
        _ => start.topLeft,
      };
      final kept = switch (entry.key) {
        StackChildDragMode.resizeTL => rect.bottomRight,
        StackChildDragMode.resizeTR => rect.bottomLeft,
        StackChildDragMode.resizeBL => rect.topRight,
        _ => rect.topLeft,
      };
      expect(kept, anchored, reason: '${entry.key}: закреплённый угол уехал');
    }
  });

  test('keepAspect: вырожденный rect не даёт NaN, move игнорирует флаг', () {
    const flat = Rect.fromLTRB(0, 0, 100, 0);
    final resized = applyStackChildDrag(
      flat,
      StackChildDragMode.resizeBR,
      const Offset(10, 10),
      keepAspect: true,
    );
    expect(resized, const Rect.fromLTRB(0, 0, 110, 10));

    expect(
      applyStackChildDrag(
        flat,
        StackChildDragMode.move,
        const Offset(10, 10),
        keepAspect: true,
      ),
      const Rect.fromLTRB(10, 10, 110, 10),
    );
  });

  test('locked: замок слоя доживает до json и обратно', () {
    final plain = ContentItem(id: 'c1', type: 'text', text: 'hi');
    expect(plain.locked, isFalse);

    final child = plain.copyWith(locked: true);
    expect(child.locked, isTrue);
    // copyWith геометрии не должен ронять замок.
    expect(
      child
          .stackChildWithRect(const Rect.fromLTWH(0, 0, 10, 10), 720, 240)
          .locked,
      isTrue,
    );

    final restored = ContentItem.fromJson(child.toJson());
    expect(restored.locked, isTrue);
    // Старый файл без ключа — разблокирован.
    expect(
      ContentItem.fromJson(plain.toJson()..remove('locked')).locked,
      isFalse,
    );
  });

  test('groupName: группа слоя доживает до json и обратно', () {
    final plain = ContentItem(id: 'c1', type: 'text', text: 'hi');
    expect(plain.groupName, isNull);
    // Старый файл и объект вне группы ключа не получают.
    expect(plain.toJson().containsKey('groupName'), isFalse);

    final grouped = plain.copyWith(groupName: 'Группа 1');
    expect(grouped.groupName, 'Группа 1');
    // Геометрические правки группу не сбрасывают.
    expect(
      grouped
          .stackChildWithRect(const Rect.fromLTWH(0, 0, 10, 10), 720, 240)
          .groupName,
      'Группа 1',
    );

    expect(ContentItem.fromJson(grouped.toJson()).groupName, 'Группа 1');

    // Разгруппировка — только через clear: copyWith(groupName: null) не трогает.
    expect(grouped.copyWith(groupName: null).groupName, 'Группа 1');
    final ungrouped = grouped.copyWith(clearGroupName: true);
    expect(ungrouped.groupName, isNull);
    expect(ungrouped.toJson().containsKey('groupName'), isFalse);
  });

  test('layerName: имя слоя доживает до json и обратно', () {
    final plain = ContentItem(id: 'c1', type: 'text', text: 'hi');
    expect(plain.layerName, isNull);
    expect(plain.toJson().containsKey('layerName'), isFalse);

    final named = plain.copyWith(layerName: 'Шапка');
    expect(named.layerName, 'Шапка');
    // Правки геометрии и группировка имя слоя не сбрасывают.
    expect(
      named
          .stackChildWithRect(const Rect.fromLTWH(0, 0, 10, 10), 720, 240)
          .layerName,
      'Шапка',
    );
    expect(named.copyWith(groupName: 'Группа 1').layerName, 'Шапка');

    expect(ContentItem.fromJson(named.toJson()).layerName, 'Шапка');

    // Сброс имени — только через clear.
    expect(named.copyWith(layerName: null).layerName, 'Шапка');
    final cleared = named.copyWith(clearLayerName: true);
    expect(cleared.layerName, isNull);
    expect(cleared.toJson().containsKey('layerName'), isFalse);
  });

  test('направляющие доживают до json и обратно', () {
    final plain = ContentItem(id: 's1', type: 'stack');
    expect(plain.guidesX, isNull);
    expect(plain.toJson().containsKey('guidesX'), isFalse);

    final guided = plain.copyWith(
      guidesX: const [120, 480.5],
      guidesY: const [64],
    );
    expect(guided.guidesX, [120, 480.5]);
    expect(ContentItem.fromJson(guided.toJson()).guidesY, [64]);

    // Пустой список в json — это «направляющих нет», а не «пустой список»:
    // иначе удалённая линейка возвращалась бы мусорным полем.
    final emptied = ContentItem.fromJson({'type': 'stack', 'guidesX': []});
    expect(emptied.guidesX, isNull);
    expect(emptied.toJson().containsKey('guidesX'), isFalse);
    expect(
      ContentItem.fromJson({'type': 'stack', 'guidesX': '120'}).guidesX,
      isNull,
    );

    // Сброс — только через clear (тот же механизм, что у layerName).
    expect(guided.copyWith(guidesX: null).guidesX, [120, 480.5]);
    expect(
      guided.copyWith(clearGuidesX: true).guidesX,
      isNull,
      reason: 'горизонтальные остаются: правка по одной оси',
    );
    expect(guided.copyWith(clearGuidesX: true).guidesY, [64]);
  });

  test('stackPin: закрепление доживает до json и обратно', () {
    final plain = ContentItem(id: 's1', type: 'stack');
    expect(plain.stackPin, isNull);
    expect(plain.isPinnedStack, isFalse);
    expect(plain.toJson().containsKey('stackPin'), isFalse);

    final pinned = plain.copyWith(stackPin: 'bottom');
    expect(pinned.stackPin, 'bottom');
    expect(pinned.isPinnedStack, isTrue);
    expect(ContentItem.fromJson(pinned.toJson()).stackPin, 'bottom');

    // Сброс — только через clear (тот же механизм, что у layerName).
    expect(pinned.copyWith(stackPin: null).stackPin, 'bottom');
    final cleared = pinned.copyWith(clearStackPin: true);
    expect(cleared.stackPin, isNull);
    expect(cleared.isPinnedStack, isFalse);
    expect(cleared.toJson().containsKey('stackPin'), isFalse);

    // «left»/«right» — колонки у края: ряд панелей собирается именно так.
    expect(
      ContentItem.fromJson(const {
        'type': 'stack',
        'stackPin': ' left ',
      }).stackPin,
      'left',
    );
    // А написанное руками «topLeft» — не край: трактуем как «не закреплено»,
    // ровно как ядро (crates/mnd-core · parse_stack_pin).
    expect(
      ContentItem.fromJson(const {
        'type': 'stack',
        'stackPin': 'topLeft',
      }).stackPin,
      isNull,
    );
    // …а валидное значение в верхнем регистре с пробелами — валидное.
    expect(
      ContentItem.fromJson(const {
        'type': 'stack',
        'stackPin': ' TOP',
      }).stackPin,
      'top',
    );
    // Не стек закреплением не становится.
    expect(
      ContentItem(id: 't1', type: 'text', stackPin: 'center').isPinnedStack,
      isFalse,
    );
  });

  test('stackWidth: своя ширина холста доживает до json и обратно', () {
    final plain = ContentItem(id: 's1', type: 'stack');
    expect(plain.stackWidth, isNull);
    expect(plain.stackCanvasWidth, kStackDesignWidth);
    expect(plain.toJson().containsKey('stackWidth'), isFalse);

    final wide = plain.copyWith(stackWidth: 1280);
    expect(wide.stackCanvasWidth, 1280);
    expect(ContentItem.fromJson(wide.toJson()).stackWidth, 1280);

    // Сброс — только через clear: copyWith(...: null) опирается на ??.
    expect(wide.copyWith(stackWidth: null).stackWidth, 1280);
    expect(wide.copyWith(clearStackWidth: true).stackWidth, isNull);
  });

  test('размеры холста: пределы и дефолт одинаковы у редактора и плеера', () {
    // У модели и у редактора были разные пределы: введённая ширина 100 молча
    // становилась 240, а высота по умолчанию в превью и в игре отличалась.
    final stack = ContentItem(id: 's1', type: 'stack');
    expect(stack.stackCanvasHeight, kStackDesignHeight);

    expect(stack.copyWith(stackWidth: 100).stackCanvasWidth, 100);
    expect(stack.copyWith(stackHeight: 100).stackCanvasHeight, 100);
    expect(stack.copyWith(stackHeight: 3000).stackCanvasHeight, 3000);

    expect(
      stack.copyWith(stackWidth: 1).stackCanvasWidth,
      kStackCanvasWidthMin,
    );
    expect(
      stack.copyWith(stackWidth: 99999).stackCanvasWidth,
      kStackCanvasWidthMax,
    );
    expect(
      stack.copyWith(stackHeight: 1).stackCanvasHeight,
      kStackCanvasHeightMin,
    );
    expect(
      stack.copyWith(stackHeight: 99999).stackCanvasHeight,
      kStackCanvasHeightMax,
    );
  });

  test('fill: закрепление на весь экран — валидный край', () {
    final fill = ContentItem(id: 's1', type: 'stack', stackPin: 'fill');
    expect(fill.isPinnedStack, isTrue);
    expect(ContentItem.fromJson(fill.toJson()).stackPin, 'fill');
  });

  test('stack: clearBackgroundColor реально обнуляет фон', () {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      backgroundColor: const Color(0x14FFFFFF),
    );
    expect(stack.backgroundColor, isNotNull);

    // copyWith(backgroundColor: null) НЕ должен обнулять — это опора на ?? .
    final broken = stack.copyWith(backgroundColor: null);
    expect(
      broken.backgroundColor,
      isNotNull,
      reason: 'copyWith(backgroundColor: null) не работает без clear!',
    );

    // clearBackgroundColor: true — правильный способ.
    final cleared = stack.copyWith(clearBackgroundColor: true);
    expect(cleared.backgroundColor, isNull);

    // JSON не содержит backgroundColor, round-trip даёт null.
    final json = cleared.toJson();
    expect(json.containsKey('backgroundColor'), isFalse);
    final restored = ContentItem.fromJson(json);
    expect(restored.backgroundColor, isNull);
  });

  group('рамка закрепления стека на экране', () {
    // Вьюпорт телефона: 400×800 логических px.
    const screen = Size(400, 800);
    ContentItem pin(String kind) => ContentItem(
      id: 's',
      type: 'stack',
      stackPin: kind,
      stackWidth: 290,
      stackHeight: 300,
    );

    test('легаси-ярлык даёт ту же рамку, что рисовал плеер раньше', () {
      // 290 px по центру по X, прижата к верхнему краю.
      expect(
        pin('top').stackPinRect(screen),
        const Rect.fromLTRB(55, 0, 345, 300),
      );
      expect(
        pin('bottom').stackPinRect(screen),
        const Rect.fromLTRB(55, 500, 345, 800),
      );
      expect(
        pin('center').stackPinRect(screen),
        const Rect.fromLTRB(55, 250, 345, 550),
      );
      // Колонки у края — из них собирается ряд.
      expect(
        pin('left').stackPinRect(screen),
        const Rect.fromLTRB(0, 250, 290, 550),
      );
      expect(
        pin('right').stackPinRect(screen),
        const Rect.fromLTRB(110, 250, 400, 550),
      );
      // `fill` растянут по обеим осям: рамка = весь вьюпорт.
      final filled = pin('fill');
      expect(filled.stackPinRect(screen), const Rect.fromLTRB(0, 0, 400, 800));
      expect(filled.stackPinStretchesWidth, isTrue);
      expect(filled.stackPinStretchesHeight, isTrue);
    });

    test('схлопнутая ось = холст в px экрана, а не весь экран', () {
      final wide = ContentItem(
        id: 's',
        type: 'stack',
        stackPin: 'top',
        stackWidth: 4000,
        stackHeight: 4000,
      );
      // Холст 4000×4000 втиснут в 400 px по ширине ⇒ масштаб 0,1 ⇒ и высота
      // рамки 400 px. Рамка обязана совпадать с тем, что рисует стек, иначе
      // плеер растягивал бы картинку по одной оси без второй.
      expect(wide.stackPinRect(screen), const Rect.fromLTRB(0, 0, 400, 400));
    });

    test(
      'растянутая ширина + схлопнутая высота: пропорция холста держится',
      () {
        final panel = ContentItem(
          id: 's',
          type: 'stack',
          stackPin: 'custom',
          pinAnchorLeft: 0,
          pinAnchorRight: 1,
          pinAnchorTop: 0.5,
          pinAnchorBottom: 0.5,
          stackWidth: 200,
          stackHeight: 300,
        );
        // 400 px рамки на холст 200 ⇒ масштаб 2 ⇒ высота 600, по центру
        // по Y: 400 ± 300.
        expect(panel.stackPinStretchesWidth, isTrue);
        expect(panel.stackPinStretchesHeight, isFalse);
        expect(
          panel.stackPinRect(screen),
          const Rect.fromLTRB(0, 100, 400, 700),
        );
      },
    );

    test('рамка бьёт экран на доли: половина ширины = панель ряда', () {
      final leftHalf = ContentItem(
        id: 's',
        type: 'stack',
        stackPin: 'custom',
        pinAnchorLeft: 0,
        pinAnchorTop: 0,
        pinAnchorRight: 0.5,
        pinAnchorBottom: 1,
      );
      expect(
        leftHalf.stackPinRect(screen),
        const Rect.fromLTRB(0, 0, 200, 800),
      );
      expect(leftHalf.stackPinStretchesWidth, isTrue);

      // Отступы — в px экрана: панель слева с зазором 8, от верха до
      // 120 px выше нижнего края.
      final drawer = ContentItem(
        id: 's',
        type: 'stack',
        stackPin: 'left',
        pinAnchorTop: 0,
        pinAnchorBottom: 1,
        pinOffsetLeft: 8,
        pinOffsetBottom: -120,
        stackWidth: 100,
      );
      expect(drawer.stackPinRect(screen), const Rect.fromLTRB(8, 0, 108, 680));
    });

    test('stackPinWithRect — точное зеркало: рамка → поля → та же рамка', () {
      const wanted = Rect.fromLTRB(12, 64, 312, 364);
      for (final kind in ['top', 'bottom', 'center', 'left', 'right']) {
        final written = pin(kind).stackPinWithRect(wanted, screen);
        expect(
          written.stackPinRect(screen),
          wanted,
          reason: 'ярлык $kind: редактор ввёл X/Y/W/H, плеер обязан увидеть их',
        );
      }
      // Растянутая рамка: смещения задают поля, якоря не меняются.
      final filled = pin(
        'fill',
      ).stackPinWithRect(const Rect.fromLTRB(8, 8, 392, 792), screen);
      expect(filled.stackPinRect(screen), const Rect.fromLTRB(8, 8, 392, 792));
      // Якоря не переписываются: останутся выведенными из 'fill' (0,0,1,1).
      expect(filled.pinAnchorLeft, isNull);
      // Обе оси растянуты ⇒ размер холста не трогается.
      expect(filled.stackWidth, 290);
      expect(filled.stackHeight, 300);

      // Схлопнутая по X ось: W рамки — это и есть ширина холста.
      expect(pin('top').stackPinWithRect(wanted, screen).stackWidth, 300);

      // Смешанная рамка (тянется по X, высота авторская): H пересчитывается в
      // px дизайна через масштаб рамки, иначе поле «высота» ничего бы не делало.
      final band = ContentItem(
        id: 's',
        type: 'stack',
        stackPin: 'custom',
        pinAnchorLeft: 0,
        pinAnchorRight: 1,
        pinAnchorTop: 0.5,
        pinAnchorBottom: 0.5,
        stackWidth: 200,
        stackHeight: 300,
      );
      final moved = band.stackPinWithRect(
        const Rect.fromLTRB(0, 200, 400, 500),
        screen,
      );
      expect(
        moved.stackWidth,
        200,
        reason: 'ось X растянута — холст не трогаем',
      );
      expect(moved.stackHeight, 150);
      expect(moved.stackPinRect(screen), const Rect.fromLTRB(0, 200, 400, 500));
    });

    test('сетка позиции: рамка переезжает, но не меняет размер', () {
      final panel = pin('center');
      final before = panel.stackPinRect(screen);
      // Верхний левый угол: якоря в (0,0), холст остаётся 290×300.
      final topLeft = panel.stackPinWithAnchors(const [0, 0, 0, 0], screen);
      expect(topLeft.stackPin, 'custom');
      expect(topLeft.stackPinRect(screen), Rect.fromLTWH(0, 0, 290, 300));
      expect(topLeft.stackWidth, closeTo(before.width, 0.01));
      expect(topLeft.stackHeight, closeTo(before.height, 0.01));
      // Правый нижний угол — то же зеркально.
      expect(
        panel
            .stackPinWithAnchors(const [1, 1, 1, 1], screen)
            .stackPinRect(screen),
        const Rect.fromLTRB(110, 500, 400, 800),
      );
    });

    test(
      'растяжение оси: рамка доезжает до краёв, холст не переписывается',
      () {
        final panel = pin('center');
        final stretched = panel.stackPinWithAnchors(const [
          0,
          0.5,
          1,
          0.5,
        ], screen);
        expect(stretched.stackPinStretchesWidth, isTrue);
        expect(stretched.stackPinStretchesHeight, isFalse);
        // 290-холст в 400 px рамки ⇒ масштаб 1,379 ⇒ высота 300*1,379.
        final rect = stretched.stackPinRect(screen);
        expect(rect.left, 0);
        expect(rect.right, 400);
        expect(rect.height, closeTo(300 * 400 / 290, 0.5));
        expect(
          rect.center.dy,
          closeTo(400, 0.5),
          reason: 'центр по Y не уехал',
        );
        expect(stretched.stackWidth, 290);
        expect(stretched.stackHeight, 300);

        // Отмена растяжения — якоря схлопываются в долю центра рамки.
        final center = stretched.stackPinCenterFractions(screen);
        expect(center[0], closeTo(0.5, 1e-6));
        final shrunk = stretched.stackPinWithAnchors([
          center[0],
          center[1],
          center[0],
          center[1],
        ], screen);
        expect(
          shrunk.stackPinRect(screen),
          const Rect.fromLTRB(55, 250, 345, 550),
        );
      },
    );

    test('«custom» доживает до ядра, а самодельный край — нет', () {
      expect(normalizeStackPin('custom'), 'custom');
      expect(normalizeStackPin('Custom '), 'custom');
      expect(normalizeStackPin('topLeft'), isNull);
    });

    test('растяжение второй оси не сдирает поля с первой', () {
      // Горизонтальная штора с зазорами 8 по краям: растягиваем высоту — поля
      // по X обязаны остаться, иначе панель прыгнет на весь экран.
      final band = ContentItem(
        id: 's',
        type: 'stack',
        stackPin: 'custom',
        pinAnchorLeft: 0,
        pinAnchorRight: 1,
        pinAnchorTop: 0.25,
        pinAnchorBottom: 0.25,
        pinOffsetLeft: 8,
        pinOffsetRight: -8,
        stackWidth: 200,
        stackHeight: 100,
      );
      final tall = band.stackPinWithAnchors(const [0, 0, 1, 1], screen);
      expect(tall.pinOffsetLeft, 8);
      expect(tall.pinOffsetRight, -8);
      final rect = tall.stackPinRect(screen);
      expect(rect, const Rect.fromLTRB(8, 0, 392, 800));
    });

    test('модалка: затемнение и закрытие только у закреплённого окна', () {
      final modal = ContentItem(
        id: 's',
        type: 'stack',
        stackPin: 'center',
        stackModal: true,
      );
      expect(modal.isModalStack, isTrue);
      expect(modal.stackScrimOpacity, kStackModalScrimDefault);
      expect(modal.stackDismissesOnTapOutside, isTrue);

      final dimmed = modal.copyWith(
        stackScrim: 0.2,
        stackDismissOnTapOutside: false,
      );
      expect(dimmed.stackScrimOpacity, 0.2);
      expect(dimmed.stackDismissesOnTapOutside, isFalse);

      // Незакреплённое «окно» — обычный слой в потоке, без скрима.
      final flow = ContentItem(id: 's', type: 'stack', stackModal: true);
      expect(flow.isModalStack, isFalse);
      expect(flow.stackScrimOpacity, 0);
    });

    test('фон картинкой: round-trip, дефолты и чистка', () {
      final stack = ContentItem(id: 's', type: 'stack');
      // Пока фон не выбран, ключей в файле нет: автосейв не должен превращать
      // каждый стек в документ с пустыми полями.
      expect(stack.hasStackBackgroundImage, isFalse);
      expect(stack.toJson().containsKey('stackBackgroundPath'), isFalse);
      expect(stack.toJson().containsKey('stackBackgroundFit'), isFalse);

      final photo = stack.copyWith(stackBackgroundPath: 'res/images/закат.png');
      expect(photo.hasStackBackgroundImage, isTrue);
      // Режим по умолчанию в файле не живёт: cover — это отсутствие ключа.
      expect(photo.toJson().containsKey('stackBackgroundFit'), isFalse);
      var restored = ContentItem.fromJson(photo.toJson());
      expect(restored.stackBackgroundPath, 'res/images/закат.png');
      expect(restored.stackBackgroundFit, 'cover');

      final textured = photo.copyWith(stackBackgroundFit: 'tile');
      restored = ContentItem.fromJson(textured.toJson());
      expect(restored.stackBackgroundFit, 'tile');
      expect(restored.stackBackgroundPath, 'res/images/закат.png');

      // «Убрать фон» снимает и режим: следующий фон не должен наследовать
      // чужую мозаику.
      final cleared = textured.copyWith(clearStackBackground: true);
      expect(cleared.stackBackgroundPath, isNull);
      expect(cleared.stackBackgroundFit, 'cover');
      expect(cleared.toJson().containsKey('stackBackgroundFit'), isFalse);

      // Пустое поле и написанное руками «мозаика» — не фон и не режим.
      final junk = ContentItem.fromJson(const {
        'id': 'j',
        'type': 'stack',
        'stackBackgroundPath': '  ',
        'stackBackgroundFit': 'мозаика',
      });
      expect(junk.hasStackBackgroundImage, isFalse);
      expect(junk.stackBackgroundFit, 'cover');
      expect(junk.toJson().containsKey('stackBackgroundFit'), isFalse);
    });

    test('round-trip: поля рамки и окна доживают до плеера', () {
      final stack = ContentItem(
        id: 's',
        type: 'stack',
        stackPin: 'left',
        pinAnchorTop: 0.25,
        pinOffsetTop: -40,
        stackModal: true,
        stackScrim: 0.4,
        stackDismissOnTapOutside: false,
      );
      final restored = ContentItem.fromJson(stack.toJson());
      expect(restored.pinAnchorTop, 0.25);
      expect(restored.pinOffsetTop, -40);
      expect(restored.stackModal, isTrue);
      expect(restored.stackScrim, 0.4);
      expect(restored.stackDismissOnTapOutside, isFalse);
      // Незаданные поля не пишутся и возвращаются null, а не нулём.
      final plain = ContentItem.fromJson(
        ContentItem(id: 'p', type: 'stack').toJson(),
      );
      expect(plain.pinAnchorLeft, isNull);
      expect(plain.stackModal, isNull);
      // clear — единственный способ убрать рамку (copyWith с null не кансит).
      expect(
        stack
            .copyWith(clearStackPinBox: true, clearStackModal: true)
            .pinAnchorTop,
        isNull,
      );
      expect(
        stack
            .copyWith(clearStackPinBox: true, clearStackModal: true)
            .stackModal,
        isNull,
      );
    });
  });
}
