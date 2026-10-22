import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/widgets/content_display_factory.dart'
    show ImageItemWidget;
import 'package:mnd_player/widgets/items/game_stack_widget.dart';

void main() {
  Widget wrap(ContentItem stack, {void Function(ContentItem)? onInteract}) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: SingleChildScrollView(
              child: GameStackWidget(
                item: stack,
                questId: 'q1',
                onInteract: onInteract ?? (_) {},
                onInputSubmitted: (_, __) {},
                onComplete: () {},
                onTransition: (_) {},
                onNavigateToNode: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('стек раскладывает детей по якорям (верх-лево / низ-лево)', (
    tester,
  ) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      backgroundColor: const Color(0x14000000),
      borderRadius: 8,
      children: [
        ContentItem(
          id: 'top',
          type: 'text',
          text: 'ВЕРХ',
          anchorLeft: 0,
          anchorTop: 0,
          anchorRight: 0,
          anchorBottom: 0,
          offsetLeft: 8,
          offsetTop: 8,
          offsetRight: 108,
          offsetBottom: 48,
        ),
        ContentItem(
          id: 'bottom',
          type: 'text',
          text: 'НИЗ',
          anchorLeft: 0,
          anchorTop: 1,
          anchorRight: 0,
          anchorBottom: 1,
          offsetLeft: 8,
          offsetTop: -48,
          offsetRight: 108,
          offsetBottom: -8,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));

    expect(find.text('ВЕРХ'), findsOneWidget);
    expect(find.text('НИЗ'), findsOneWidget);

    // Холст 720 втиснут в 400: масштаб 0.556, высота 200 → 111. Оба ребёнка
    // остаются внутри — «низ» прижат к нижней кромке, а не уехал за экран.
    final topRect = tester.getRect(find.text('ВЕРХ'));
    final bottomRect = tester.getRect(find.text('НИЗ'));
    expect(topRect.top, lessThan(30));
    expect(topRect.left, lessThan(60));
    expect(bottomRect.top, greaterThan(topRect.bottom));
    expect(bottomRect.bottom, lessThanOrEqualTo(112));
    expect(bottomRect.left, lessThan(60));
  });

  testWidgets('своя ширина холста: масштаб считается от неё', (tester) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackWidth: 400,
      stackHeight: 100,
      children: const [],
    );

    await tester.pumpWidget(wrap(stack));

    // Бокс теста ровно 400 px — это и есть авторская ширина холста, поэтому
    // масштаб 1 и высота остаётся пиксельной (100), а не 400/720*100 = 55,6.
    expect(tester.getSize(find.byType(GameStackWidget)), const Size(400, 100));
  });

  testWidgets('узкий холст не растягивается на доступную ширину', (
    tester,
  ) async {
    // Закреплённая панель 290×300 в колонке 720: раньше стек брал всю
    // доступную ширину, масштаб выходил 720/290, и панель в игре вырастала
    // до полутора экранов вместо того, что автор видел на канвасе.
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackWidth: 290,
      stackHeight: 300,
      stackPin: 'center',
      children: const [],
    );

    // Align — те же свободные ограничения, что у закреплённого слоя на экране
    // игры; в тесной колонке ноды ширину задаёт сам родитель.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: Align(
                alignment: Alignment.topLeft,
                child: GameStackWidget(
                  item: stack,
                  questId: 'q1',
                  onInteract: (_) {},
                  onInputSubmitted: (_, __) {},
                  onComplete: () {},
                  onTransition: (_) {},
                  onNavigateToNode: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(GameStackWidget)), const Size(290, 300));
  });

  testWidgets('fill: холст добирает высоту под доступное место', (
    tester,
  ) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackWidth: 720,
      stackHeight: 200,
      stackPin: 'fill',
      children: [
        ContentItem(
          id: 'top',
          type: 'text',
          text: 'ШАПКА',
          anchorLeft: 0,
          anchorTop: 0,
          anchorRight: 1,
          anchorBottom: 0,
          offsetLeft: 8,
          offsetTop: 8,
          offsetRight: -8,
          offsetBottom: 40,
        ),
        ContentItem(
          id: 'bottom',
          type: 'text',
          text: 'НИЖНЯЯ ПАНЕЛЬ',
          anchorLeft: 0,
          anchorTop: 1,
          anchorRight: 1,
          anchorBottom: 1,
          offsetLeft: 8,
          offsetTop: -40,
          offsetRight: -8,
          offsetBottom: -8,
        ),
      ],
    );

    // Экран 360×600: масштаб 0,5 ⇒ холст становится 720×1200 в px дизайна.
    // Авторская height 200 в этом режиме — только эскиз, иначе нижняя панель
    // сидела бы на дне 100-пиксельной полосы посередине экрана.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 600,
                child: GameStackWidget(
                  item: stack,
                  questId: 'q1',
                  onInteract: (_) {},
                  onInputSubmitted: (_, __) {},
                  onComplete: () {},
                  onTransition: (_) {},
                  onNavigateToNode: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(GameStackWidget)), const Size(360, 600));
    final top = tester.getRect(find.text('ШАПКА'));
    final bottom = tester.getRect(find.text('НИЖНЯЯ ПАНЕЛЬ'));
    expect(top.top, greaterThanOrEqualTo(0));
    expect(top.top, lessThan(30));
    expect(bottom.bottom, lessThanOrEqualTo(600));
    expect(bottom.bottom, greaterThan(550));
  });

  testWidgets('ребёнок с дефолтными якорями центрируется в стеке', (
    tester,
  ) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      children: [
        // Дефолт: все якоря 0.5, симметричные offset → бокс по центру.
        ContentItem(
          id: 'c',
          type: 'text',
          text: 'ЦЕНТР',
          offsetLeft: -80,
          offsetRight: 80,
          offsetTop: -22,
          offsetBottom: 22,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));

    final rect = tester.getRect(find.text('ЦЕНТР'));
    // Холст 720×200 втиснут в 400: центр (360, 100) → (200, 55.6).
    expect(rect.center.dx, closeTo(200, 20));
    expect(rect.center.dy, closeTo(200 * 400 / 720 / 2, 20));
  });

  testWidgets('стек вписывается в узкую ширину целиком, а не режется', (
    tester,
  ) async {
    // Реальный случай квеста: объект в правом нижнем углу дизайн-холста.
    // При раскладке по фактической ширине он уезжал за край экрана.
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 545,
      children: [
        ContentItem(
          id: 'corner',
          type: 'text',
          text: 'УГОЛ',
          anchorLeft: 0,
          anchorTop: 0,
          anchorRight: 0,
          anchorBottom: 0,
          offsetLeft: 600,
          offsetTop: 480,
          offsetRight: 700,
          offsetBottom: 520,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));

    final box = tester.getRect(find.byType(GameStackWidget));
    // Высота следует за шириной: пропорции дизайн-холста сохранены.
    expect(box.height, closeTo(400 * 545 / 720, 1));
    final corner = tester.getRect(find.text('УГОЛ'));
    expect(corner.right, lessThanOrEqualTo(box.right + 0.5));
    expect(corner.bottom, lessThanOrEqualTo(box.bottom + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ребёнок за пределами стека не ломает рендер', (tester) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 100,
      children: [
        // Вырожденный rect (ширина 0) — должен быть пропущен.
        ContentItem(
          id: 'bad',
          type: 'text',
          text: 'БАД',
          anchorLeft: 0.5,
          anchorTop: 0.5,
          anchorRight: 0.5,
          anchorBottom: 0.5,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));
    expect(find.text('БАД'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Finder coloredContainers(Color? color) {
    return find.descendant(
      of: find.byType(GameStackWidget),
      matching: find.byWidgetPredicate((w) {
        if (w is! Container || w.decoration is! BoxDecoration) return false;
        final d = w.decoration as BoxDecoration;
        return color != null ? d.color == color : d.color != null;
      }),
    );
  }

  testWidgets('без backgroundColor стек прозрачный (нет панели-Container)', (
    tester,
  ) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      // borderRadius без цвета не должен создавать видимую панель.
      borderRadius: 12,
      children: [
        ContentItem(
          id: 'c',
          type: 'text',
          text: 'ХИ',
          offsetLeft: -60,
          offsetRight: 60,
          offsetTop: -20,
          offsetBottom: 20,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));
    expect(find.text('ХИ'), findsOneWidget);
    expect(coloredContainers(null), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('с backgroundColor стек рисует Container с этим цветом', (
    tester,
  ) async {
    const bg = Color(0xFFFF00FF);
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      backgroundColor: bg,
      children: [
        ContentItem(
          id: 'c',
          type: 'text',
          text: 'ХИ',
          offsetLeft: -60,
          offsetRight: 60,
          offsetTop: -20,
          offsetBottom: 20,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));
    expect(coloredContainers(bg), findsOneWidget);
  });

  testWidgets('картинка-фон — первый слой холста, слои поверх неё', (
    tester,
  ) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      backgroundColor: const Color(0x14000000),
      // Файла в тестовом квесте нет — проверяем раскладку: фон встроен в холст
      // и идёт до детей, поэтому картинка не может закрыть кнопку.
      stackBackgroundPath: 'res/images/закат.png',
      stackBackgroundFit: 'tile',
      children: [
        ContentItem(
          id: 'c',
          type: 'text',
          text: 'ХИ',
          offsetLeft: -60,
          offsetRight: 60,
          offsetTop: -20,
          offsetBottom: 20,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));

    final canvas = tester
        .widgetList<Stack>(find.byType(Stack))
        .where(
          (s) => s.children.any(
            (c) => c is Positioned && c.child is StackBackgroundFile,
          ),
        )
        .single;
    expect(canvas.children.first, isA<Positioned>());
    expect(
      (canvas.children.first as Positioned).child,
      isA<StackBackgroundFile>(),
    );
    // Фон и слой: больше ничего в холст не подмешано.
    expect(canvas.children.length, 2);
    expect(find.text('ХИ'), findsOneWidget);
  });

  testWidgets('без картинки-фона вида фона в дереве нет', (tester) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      backgroundColor: const Color(0x14000000),
      children: [
        ContentItem(
          id: 'c',
          type: 'text',
          text: 'ХИ',
          offsetLeft: -60,
          offsetRight: 60,
          offsetTop: -20,
          offsetBottom: 20,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));
    expect(find.byType(StackBackgroundFile), findsNothing);
  });

  test('режимы картинки-фона: что значит каждый', () {
    expect(stackBackgroundBoxFit('cover'), BoxFit.cover);
    expect(stackBackgroundBoxFit('contain'), BoxFit.contain);
    expect(stackBackgroundBoxFit('fill'), BoxFit.fill);
    // Мозаика — не масштаб: картинка кладётся в своих px, а повтор делает
    // ImageRepeat, которого здесь нет.
    expect(stackBackgroundBoxFit('tile'), BoxFit.none);
    expect(stackBackgroundBoxFit('написано руками'), BoxFit.cover);
  });

  testWidgets('картинка в стеке рендерится с BoxFit.contain (пропорции)', (
    tester,
  ) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      children: [
        ContentItem(
          id: 'img',
          type: 'image',
          resourcePath: 'images/x.png',
          anchorLeft: 0,
          anchorTop: 0,
          anchorRight: 0,
          anchorBottom: 0,
          offsetLeft: 10,
          offsetTop: 10,
          offsetRight: 210,
          offsetBottom: 110,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));
    final images = tester.widgetList<ImageItemWidget>(
      find.byType(ImageItemWidget),
    );
    expect(images, isNotEmpty);
    expect(images.first.boxFit, BoxFit.contain);
  });

  testWidgets('opacity, rotation и scale ребёнка доходят до дерева виджетов', (
    tester,
  ) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      children: [
        ContentItem(
          id: 'c',
          type: 'text',
          text: 'КРивой',
          opacity: 0.5,
          rotation: 90,
          scale: 2,
          offsetLeft: -60,
          offsetRight: 60,
          offsetTop: -20,
          offsetBottom: 20,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));

    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('КРивой'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 0.5);

    // Transform'ов в дереве больше одного — ищем наш, у поворота на 90°
    // sin стоит в entry(1, 0).
    final rotation = tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.text('КРивой'),
            matching: find.byType(Transform),
          ),
        )
        .firstWhere(
          (t) => (t.transform.entry(1, 0) - 1).abs() < 1e-6,
          orElse: () => fail('поворота ребёнка в дереве не нашлось'),
        );
    // cos 90° ≈ 0, sin 90° = 1: матрица чистого поворота.
    expect(rotation.transform.entry(0, 0), closeTo(0, 1e-6));
    expect(rotation.transform.entry(0, 1), closeTo(-1, 1e-6));
    expect(rotation.transform.entry(1, 1), closeTo(0, 1e-6));

    // Масштаб — отдельная обёртка: чистая диагональ 2 без поворотных членов.
    // Именно она даёт кнопку и текст крупнее, не трогая бокс слоя.
    final scaling = tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.text('КРивой'),
            matching: find.byType(Transform),
          ),
        )
        .firstWhere(
          (t) => (t.transform.entry(0, 0) - 2).abs() < 1e-6,
          orElse: () => fail('масштаба ребёнка в дереве не нашлось'),
        );
    expect(scaling.transform.entry(1, 1), closeTo(2, 1e-6));
    expect(scaling.transform.entry(0, 1), closeTo(0, 1e-6));
    expect(scaling.transform.entry(1, 0), closeTo(0, 1e-6));
  });

  testWidgets('без opacity и rotation лишних обёрток нет', (tester) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      children: [
        ContentItem(
          id: 'c',
          type: 'text',
          text: 'Чистый',
          offsetLeft: -60,
          offsetRight: 60,
          offsetTop: -20,
          offsetBottom: 20,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));
    expect(
      find.ancestor(of: find.text('Чистый'), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('скрытый слой не строится вообще', (tester) async {
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      children: [
        // Геометрия обязательна: нулевой rect ребёнок не рендерится и без
        // isHidden, и тест проходил бы вхолостую.
        ContentItem(
          id: 'v',
          type: 'text',
          text: 'Видим',
          offsetRight: 100,
          offsetBottom: 40,
        ),
        ContentItem(
          id: 'h',
          type: 'text',
          text: 'Скрыт',
          offsetRight: 100,
          offsetBottom: 40,
          isHidden: true,
        ),
      ],
    );

    await tester.pumpWidget(wrap(stack));
    expect(find.text('Видим'), findsOneWidget);
    expect(find.text('Скрыт'), findsNothing);
  });

  testWidgets('скругление картинок в стеке регулируется самим стеком', (
    tester,
  ) async {
    ContentItem stackWith({bool? roundChildren}) => ContentItem(
      id: 's1',
      type: 'stack',
      stackHeight: 200,
      childImageRoundedCorners: roundChildren,
      children: [
        ContentItem(
          id: 'img',
          type: 'image',
          resourcePath: 'images/x.png',
          offsetRight: 200,
          offsetBottom: 100,
        ),
      ],
    );

    // Без своей настройки — как у ноды: здесь нода просит острые углы.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: GameStackWidget(
                item: stackWith(),
                questId: 'q1',
                onInteract: (_) {},
                onInputSubmitted: (_, __) {},
                onComplete: () {},
                onTransition: (_) {},
                onNavigateToNode: (_) {},
                imageRoundedCornersOverride: false,
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<ImageItemWidget>(find.byType(ImageItemWidget))
          .roundedCornersOverride,
      isFalse,
    );

    // А со своей — стек перекрывает ноду в обе стороны.
    await tester.pumpWidget(wrap(stackWith(roundChildren: true)));
    expect(
      tester
          .widget<ImageItemWidget>(find.byType(ImageItemWidget))
          .roundedCornersOverride,
      isTrue,
    );
  });

  // ---------------------------------------------------------------------------
  //  Триггеры на слоях. Путь тапа должен доходить до onInteract в обоих
  //  форматах wiring (legacy scriptTriggers и новые behaviours), картинка —
  //  отдавать тап движку вместо полноэкранного просмотра, а стек со своим
  //  действием — по-прежнему глушить детей.
  // ---------------------------------------------------------------------------

  ContentItem wiredLayer({
    required String type,
    Map<String, String>? triggers,
    List<ContentTrigger>? behaviours,
  }) => ContentItem(
    id: 'layer-$type',
    type: type,
    text: type == 'text' ? 'СЧЁТ' : null,
    resourcePath: type == 'image' ? 'images/x.png' : null,
    scriptTriggers: triggers,
    behaviours: behaviours,
    offsetRight: 100,
    offsetBottom: 40,
  );

  ContentItem stackOf(
    List<ContentItem> layers, {
    Map<String, String>? selfTriggers,
  }) => ContentItem(
    id: 's1',
    type: 'stack',
    stackHeight: 200,
    scriptTriggers: selfTriggers,
    children: layers,
  );

  Future<ContentItem?> tappedLayer(
    WidgetTester tester,
    ContentItem stack,
    Finder layerFinder,
  ) async {
    ContentItem? got;
    await tester.pumpWidget(wrap(stack, onInteract: (item) => got = item));
    await tester.tap(layerFinder, warnIfMissed: false);
    await tester.pump();
    return got;
  }

  testWidgets('onPress текста в стеке доходит до движка (legacy формат)', (
    tester,
  ) async {
    final layer = wiredLayer(
      type: 'text',
      triggers: {'onPress': 'scripts/1.json'},
    );
    final got = await tappedLayer(tester, stackOf([layer]), find.text('СЧЁТ'));
    expect(got?.id, 'layer-text');
  });

  testWidgets('onPress текста в стеке доходит до движка (behaviours)', (
    tester,
  ) async {
    final layer = wiredLayer(
      type: 'text',
      behaviours: [ContentTrigger(event: 'onPress', script: 'scripts/1.json')],
    );
    final got = await tappedLayer(tester, stackOf([layer]), find.text('СЧЁТ'));
    expect(got?.id, 'layer-text');
  });

  testWidgets('onPress у картинки в стеке ведёт в движок, а не в просмотр', (
    tester,
  ) async {
    final layer = wiredLayer(
      type: 'image',
      triggers: {'onPress': 'scripts/1.json'},
    );
    ContentItem? got;
    await tester.pumpWidget(
      wrap(stackOf([layer]), onInteract: (item) => got = item),
    );
    final image = tester.widget<ImageItemWidget>(find.byType(ImageItemWidget));
    // Просмотр картинки выключен, тап уходит на обёртку триггера.
    expect(image.suppressInteractions, isTrue);
    final ink = tester.widget<InkWell>(
      find.ancestor(
        of: find.byType(ImageItemWidget),
        matching: find.byType(InkWell),
      ),
    );
    ink.onTap!();
    expect(got?.id, 'layer-image');
  });

  testWidgets('картинка в стеке без триггера тап не перехватывает', (
    tester,
  ) async {
    ContentItem? got;
    await tester.pumpWidget(
      wrap(
        stackOf([wiredLayer(type: 'image')]),
        onInteract: (item) => got = item,
      ),
    );
    final image = tester.widget<ImageItemWidget>(find.byType(ImageItemWidget));
    expect(image.suppressInteractions, isFalse);
    expect(
      find.ancestor(
        of: find.byType(ImageItemWidget),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(got, isNull);
  });

  testWidgets('стек со своим действием не отдаёт тап детям', (tester) async {
    final layer = wiredLayer(
      type: 'text',
      triggers: {'onPress': 'scripts/1.json'},
    );
    ContentItem? got;
    await tester.pumpWidget(
      wrap(
        stackOf([layer], selfTriggers: {'onPress': 'scripts/stack.json'}),
        onInteract: (item) => got = item,
      ),
    );
    expect(
      find.ancestor(of: find.text('СЧЁТ'), matching: find.byType(InkWell)),
      findsNothing,
    );
    await tester.tap(find.text('СЧЁТ'), warnIfMissed: false);
    await tester.pump();
    // Тап по слою не долетает до onInteract: стек забирает нажатие себе
    // (его собственная обёртка строится выше, на уровне ноды).
    expect(got, isNull);
  });

  testWidgets('стек уже доступной ширины: холст не растягивается по X', (
    tester,
  ) async {
    // Авторский холст 183×220 в ноде шириной 400. Без Align жёсткий SizedBox
    // получал чужую ширину 400, FittedBox с BoxFit.fill растягивал холст
    // только по горизонтали, и картинка в игре превращалась в блин, а текст
    // залезал за край — то, что автор видел только при запуске симуляции.
    final stack = ContentItem(
      id: 's1',
      type: 'stack',
      stackWidth: 183,
      stackHeight: 220,
      children: [
        ContentItem(
          id: 'layer',
          type: 'text',
          text: 'А',
          offsetLeft: 18.4,
          offsetTop: 23.2,
          offsetRight: 178.4,
          offsetBottom: 67.2,
        ),
      ],
    );
    await tester.pumpWidget(wrap(stack));

    final canvas = tester.getRect(find.byType(GameStackWidget));
    final box = tester.getRect(find.byType(FittedBox));

    // Холст остаётся в авторских 183×220 и центрируется в доступной ширине,
    // а не размазывается по ней.
    expect(box.width, closeTo(183, 0.6));
    expect(box.height, closeTo(220, 0.6));
    expect(box.left, closeTo(canvas.left + (canvas.width - 183) / 2, 0.6));
  });
}
