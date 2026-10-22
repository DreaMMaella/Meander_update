// Блоки: корпус залит цветом категории, текст белый, поля — тёмные плашки.

// Задача автора (#325): категорию блока обязаны видеть сразу, как в
// Scratch-подобных редакторах, — это разворот решения #224/#237, где корпус
// брался из ролей темы, а категорию задавала трёхпиксельная полоса слева (на
// списке из двадцати блоков полоса не читалась). Теперь цвет = категория, от
// темы остаётся только оттенок: в светлой теме тот же цвет затемнён.
//
// Тест держит то, что глазом не проверяется:
//   * белый текст на КАЖДОМ корпусе тянет WCAG AA (подбор рампы по контрасту,
//     а не по сочности — прошлый золотой «Цикла» был красив и давал 3.8:1);
//   * корпус не едет за подменённым ColorScheme (все прогоны идут с фейковыми
//     ролями: верни Shell чтение темы — тесты 4–7 поедут сами);
//   * плашки полей — тёмная подложка с белой чертой, а не `surfaceContainer*`
//     темы и не акцент категории;
//   * у блока есть ручка перетаскивания, пустое обязательное поле сигналит
//     рамкой;
//   * поле — одна строка «подпись значение», короткие поля текут по строкам,
//     слайдеру достаётся ряд целиком, крестика в шапке по умолчанию нет (#333);
//   * дети контейнера лежат ПЛОСКИМИ карточками под его карточкой (#326), а
//     область кончается планкой в цвет контейнера;
//   * «шляпа» — подъём верхней кромки — есть только у события.

import 'dart:io';
import 'dart:math' as math;

import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _editorDir = 'lib/features/editor/screens/visual_script_editor';
final _shellFinder = find.byType(ScriptBlockShell);

// Фейковые роли темы: редизайн обязан игнорировать их целиком. Цвета подобраны
// так, чтобы не совпасть ни с одним корпусом рампы, ни с белым текстом.
const _fakeSurface = Color(0xFF123456);
const _fakeLeaf = Color(0xFF16161A);
const _fakeFieldFill = Color(0xFF303036);
const _fakeInk = Color(0xFF7766FF);

ColorScheme _fakeScheme(Brightness brightness) =>
    ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    ).copyWith(
      surface: _fakeSurface,
      surfaceContainerLow: _fakeLeaf,
      surfaceContainerHigh: _fakeFieldFill,
      surfaceContainerHighest: _fakeFieldFill,
      onSurface: _fakeInk,
      onSurfaceVariant: _fakeInk,
      primary: _fakeInk,
    );

// --- WCAG 2.1: относительная яркость и контраст -------------------------
// Считаем сами, чтобы тест не зависел от тем и плагинов.

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// Контраст пары; `fg` может быть полупрозрачным и подмешивается под `bg`.
double _contrast(Color fg, Color bg) {
  final a = _luminance(Color.alphaBlend(fg, bg));
  final b = _luminance(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// Карточка блока — первый Material под Shell (оболочка рисуется сама, Material
/// плашек лежит глубже).
Finder _cardFinder(WidgetTester tester) => find
    .descendant(of: _shellFinder, matching: find.byType(Material))
    .first;

ScriptBlockShape _cardShape(WidgetTester tester) =>
    tester.widget<Material>(_cardFinder(tester)).shape! as ScriptBlockShape;

Color _cardColor(WidgetTester tester) =>
    tester.widget<Material>(_cardFinder(tester)).color!;

/// Плашка поля — ближайший Material над подписью или значением.
Material _chipOf(WidgetTester tester, String text) => tester.widget<Material>(
  find.ancestor(of: find.text(text), matching: find.byType(Material)).first,
);

Future<void> _pumpShell(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  BlockCategory category = BlockCategory.action,
  String menuScope = ScriptBlockShell.leafScope,
  bool collapsible = false,
  bool collapsed = false,
  VoidCallback? onDelete,
  Widget? child,
  Widget? body,
  String? endLabel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        colorScheme: _fakeScheme(brightness),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScriptBlockShell(
            category: category,
            title: 'Показать текст',
            menuScope: menuScope,
            collapsible: collapsible,
            collapsed: collapsed,
            onDelete: onDelete,
            body: body,
            endLabel: endLabel,
            child:
                child ?? const ScriptFieldTile(label: 'Переменная', value: ''),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _underlineFinder(Color lineColor) => find.descendant(
  of: _shellFinder,
  matching: find.byWidgetPredicate(
    // Черта рисуется Container'ом с BoxDecoration, а не DecoratedBox'ом.
    (w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == lineColor,
  ),
);

void main() {
  test('счётчик контраста не врёт: проверка на заведомо провальном цвете', () {
    // Негативный контроль самого теста. Белый на белом = 1, чёрный на белом =
    // 21, а золотой корпус «Цикла» из прошлой рампы (#FFE066-семейство,
    // 0xFFA87C1B) — те самые 3.8:1 из комментария к [blockFg]: он сочен глазу и
    // не проходит AA. Пропал бы этот провал — рампа «прошла бы» любой мусор.
    expect(_contrast(blockFg, blockFg), closeTo(1.0, 0.001));
    expect(_contrast(blockFg, Colors.black), closeTo(21.0, 0.05));
    expect(
      _contrast(blockFg, const Color(0xFFA87C1B)),
      lessThan(4.5),
      reason: 'счётчик должен помечать прежний золотой как нечитаемый',
    );
    expect(_contrast(blockFg, const Color(0xFFA87C1B)), greaterThan(3.0));
  });

  test('белый текст на каждом корпусе держит AA, светлая тема — с запасом', () {
    for (final brightness in Brightness.values) {
      for (final category in BlockCategory.values) {
        final card = blockAccent(brightness, category);
        expect(
          _contrast(blockFg, card),
          greaterThanOrEqualTo(4.5),
          reason:
              '${category.name}/${brightness.name}: белый на $card не читается',
        );
      }
    }
    // Светлый корпус темнее тёмного — иначе в светлой теме белый текст тонет.
    for (final category in BlockCategory.values) {
      final dark = _contrast(blockFg, blockAccent(Brightness.dark, category));
      final light = _contrast(blockFg, blockAccent(Brightness.light, category));
      expect(
        light,
        greaterThan(dark),
        reason: '${category.name}: светлый корпус светлее тёмного',
      );
    }
  });

  test('подпись поля на тёмной плашке читается на каждом корпусе', () {
    // Подписи приглушены (0.82 белого) и лежат на плашке, а не на корпусе:
    // считаем бутылку «подпись → плашка → корпус». Для подписи AA не требуется,
    // но и 3:1 — не опция: ниже она на цветном корпусе сливается с пятном.
    for (final brightness in Brightness.values) {
      for (final category in BlockCategory.values) {
        final card = blockAccent(brightness, category);
        final chip = Color.alphaBlend(blockFieldFill, card);
        expect(
          _contrast(blockFg.withValues(alpha: 0.82), chip),
          greaterThanOrEqualTo(3.0),
          reason:
              '${category.name}/${brightness.name}: подпись поля нечитаема на $card',
        );
      }
    }
  });

  testWidgets('корпус = цвет категории и не смотрит на тему', (tester) async {
    await _pumpShell(tester, category: BlockCategory.action);
    expect(
      _cardColor(tester),
      blockAccent(Brightness.dark, BlockCategory.action),
      reason: 'листовой блок не залит акцентом категории',
    );

    await _pumpShell(
      tester,
      brightness: Brightness.light,
      category: BlockCategory.variable,
    );
    expect(
      _cardColor(tester),
      blockAccent(Brightness.light, BlockCategory.variable),
    );
    // Прямые запреты: любой из этих цветов означал бы, что корпус снова читает
    // роли темы.
    expect(_cardColor(tester), isNot(_fakeLeaf));
    expect(_cardColor(tester), isNot(_fakeSurface));
    expect(_cardColor(tester), isNot(_fakeFieldFill));
  });

  testWidgets('заголовок, подпись и значение поля — белые', (tester) async {
    await _pumpShell(
      tester,
      category: BlockCategory.event,
      child: const ScriptFieldsGroup(
        children: [
          ScriptFieldTile(label: 'Переменная', value: 'flag_door_open'),
        ],
      ),
    );

    final title = tester.widget<Text>(find.text('Показать текст'));
    expect(title.style!.color, blockFg);
    final value = tester.widget<Text>(find.text('flag_door_open'));
    expect(value.style!.color, blockFg);
    expect(value.style!.fontFamily, 'monospace');
    final label = tester.widget<Text>(find.text('Переменная'));
    expect(label.style!.color, blockFg.withValues(alpha: 0.82));
  });

  testWidgets(
    'плашка поля — своя тёмная подложка, а не surfaceContainer темы',
    (tester) async {
      await _pumpShell(
        tester,
        category: BlockCategory.script,
        child: const ScriptFieldTile(label: 'Текст', value: 'Привет'),
      );
      final chip = _chipOf(tester, 'Привет');
      expect(chip.color, blockFieldFill);
      expect(chip.color, isNot(_fakeFieldFill));
      expect(
        chip.color,
        isNot(blockAccent(Brightness.dark, BlockCategory.script)),
      );
    },
  );

  testWidgets('тема переопределена только под карточкой', (tester) async {
    await _pumpShell(tester, category: BlockCategory.control);

    final inner = Theme.of(
      tester.element(find.byIcon(Icons.sort_rounded)),
    ).colorScheme;
    expect(inner.onSurfaceVariant, blockFgMuted);
    expect(inner.onSurface, blockFg);
    expect(inner.primary, blockFg);
    expect(inner.surfaceContainerHighest, blockFieldFill);

    // Наружу правка не вытекает: палитра, шапка экрана и диалоги живут в
    // пользовательской теме.
    final outer = Theme.of(tester.element(_shellFinder)).colorScheme;
    expect(outer.onSurfaceVariant, _fakeInk);
    expect(outer.surfaceContainerHighest, _fakeFieldFill);
  });

  testWidgets('у блока есть ручка перетаскивания слева от заголовка', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(
      find.byTooltip('Удерживайте, чтобы перетащить блок'),
      findsOneWidget,
      reason: 'ручка потеряла подсказку — перетаскивание не найти',
    );
    final handle = find.byIcon(Icons.sort_rounded);
    expect(handle, findsOneWidget);
    expect(tester.widget<Icon>(handle).color, blockFg.withValues(alpha: 0.62));
    expect(
      tester.getTopLeft(handle).dx,
      lessThan(tester.getTopLeft(find.text('Показать текст')).dx),
      reason: 'ручка уехала из левого края карточки',
    );
    // Стрелка сворачивания больше не спорит с ручкой: она в правом конце
    // шапки, а не слева от заголовка.
    await _pumpShell(
      tester,
      collapsible: true,
      child: const ScriptFieldTile(label: 'Текст', value: 'Привет'),
    );
    final chevron = find.byIcon(Icons.expand_more_rounded);
    expect(chevron, findsOneWidget);
    expect(
      tester.getTopLeft(chevron).dx,
      greaterThan(tester.getTopLeft(find.text('Показать текст')).dx),
      reason: 'стрелка сворачивания уехала влево и спорит с ручкой',
    );
  });

  testWidgets('дети контейнера — плоские карточки под ним, а не внутри корпуса', (
    tester,
  ) async {
    // Негативный контроль: пока body не вынесен из Material карточки, дети
    // оказываются его потомками, и первый assert падает.
    await _pumpShell(
      tester,
      category: BlockCategory.control,
      menuScope: 'цикл',
      body: const Text('Дети'),
      endLabel: 'Конец цикла',
    );

    expect(find.text('Дети'), findsOneWidget);
    expect(
      find.descendant(of: _cardFinder(tester), matching: find.text('Дети')),
      findsNothing,
      reason: 'вложенные блоки снова тонут внутри цветного корпуса контейнера',
    );
    // И лежат НИЖЕ карточки, а не за ней.
    expect(
      tester.getRect(find.text('Дети')).top,
      greaterThanOrEqualTo(tester.getRect(_cardFinder(tester)).bottom - 0.01),
      reason: 'дети контейнера не под его карточкой',
    );
    // Область кончается планкой в цвет контейнера: без отступа и шахты это
    // единственный сигнал, где цикл заканчивается.
    final fill = blockAccent(Brightness.dark, BlockCategory.control);
    expect(
      find.descendant(
        of: _shellFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.color == fill,
        ),
      ),
      findsNWidgets(2),
      reason: 'планка «Конец цикла» не в цвет контейнера или пропала',
    );

    // Листовой блок не притворяется контейнером: у него нет планки.
    await _pumpShell(tester, category: BlockCategory.control, child: const Text('Дети'));
    expect(
      find.descendant(
        of: _shellFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.color == fill,
        ),
      ),
      findsOneWidget,
      reason: 'листовой блок дорисовал себе границу области',
    );
  });

  testWidgets('свёрнутый контейнер не показывает детей', (tester) async {
    await _pumpShell(
      tester,
      category: BlockCategory.control,
      menuScope: 'цикл',
      collapsible: true,
      collapsed: true,
      body: const Text('Дети'),
    );
    expect(
      find.text('Дети'),
      findsNothing,
      reason: 'свёрнутый цикл всё равно рисует своё тело',
    );
  });

  testWidgets('шляпа есть только у события', (tester) async {
    await _pumpShell(tester, category: BlockCategory.event);
    expect(
      _cardShape(tester).hatRise,
      blockHatRise,
      reason: 'событие потеряло поднятую кромку — начало скрипта не видно',
    );

    for (final category in BlockCategory.values) {
      if (category == BlockCategory.event) continue;
      await _pumpShell(tester, category: category);
      expect(
        _cardShape(tester).hatRise,
        0,
        reason: '${category.name}: обычный блок надел шляпу события',
      );
    }
  });

  testWidgets('пустое обязательное поле — рамка, заполненное — черта снизу', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      category: BlockCategory.variable,
      child: const ScriptFieldsGroup(
        children: [
          ScriptFieldTile(label: 'Путь', value: 'Глава 1/Сцена'),
          ScriptFieldTile(label: 'Таблица', value: 'лавка', onTap: null),
        ],
      ),
    );

    // Заполненное поле: без рамки, с белой чертой под значением — у обоих
    // полей группы, поэтому 2.
    final filled = _chipOf(tester, 'Глава 1/Сцена');
    expect((filled.shape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(
      _underlineFinder(blockFg.withValues(alpha: 0.55)),
      findsNWidgets(2),
      reason: 'у заполненных полей пропало подчёркивание',
    );

    await _pumpShell(
      tester,
      category: BlockCategory.variable,
      child: const ScriptFieldTile(label: 'Переменная', value: ''),
    );
    // Нести некому (onTap == null) — тревогу не рисуем.
    expect(
      (_chipOf(tester, 'Переменная').shape! as RoundedRectangleBorder).side,
      BorderSide.none,
    );

    await _pumpShell(
      tester,
      category: BlockCategory.variable,
      child: ScriptFieldTile(label: 'Переменная', value: '', onTap: () {}),
    );
    final alert =
        _chipOf(tester, 'Переменная').shape! as RoundedRectangleBorder;
    expect(alert.side.color, blockFieldAlert);
    expect(alert.side.width, 1.4);
    expect(
      _underlineFinder(blockFg.withValues(alpha: 0.55)),
      findsNothing,
      reason: 'рамка и черта должны исключать друг друга',
    );
  });

  testWidgets('радиусы: корпус 16, плашка 8', (tester) async {
    await _pumpShell(
      tester,
      child: const ScriptFieldTile(label: 'Текст', value: 'Привет'),
    );
    expect(_cardShape(tester).radius, 16);
    final chip = _chipOf(tester, 'Привет').shape! as RoundedRectangleBorder;
    expect(chip.borderRadius, BorderRadius.circular(8));
  });

  test('акценты категорий различимы между собой и между яркостями', () {
    for (final brightness in Brightness.values) {
      final seen = <BlockCategory, Color>{};
      for (final category in BlockCategory.values) {
        final color = blockAccent(brightness, category);
        for (final other in seen.entries) {
          expect(
            color,
            isNot(other.value),
            reason: '${other.key.name} и ${category.name} одного цвета',
          );
        }
        seen[category] = color;
      }
    }
    for (final category in BlockCategory.values) {
      expect(
        blockAccent(Brightness.dark, category),
        isNot(blockAccent(Brightness.light, category)),
        reason: '${category.name} одинаков в светлой и тёмной теме',
      );
    }
    final icons = BlockCategory.values.map(iconForCategory).toSet();
    expect(icons.length, BlockCategory.values.length);
  });

  test('палитра блоков красит та же рампа, что и сами блоки', () {
    // Список блоков и холст обязаны совпадать по цвету: отдельная палитра —
    // это место, где рампа разъезжается первой.
    final source = File(
      '$_editorDir/action_picker_screen.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('blockAccent('),
      reason: 'палитра перестала брать цвета из общей рампы',
    );
  });

  test(
    'у каждой категории есть акцент — новая категория не останется бесцветной',
    () {
      // Switch в blockAccent закрытый: компилятор поймает промах сам, но здесь
      // проверяем, что «Комментарий» не притворяется «Управлением».
      final source = File(
        '$_editorDir/widgets/comment_block_widget.dart',
      ).readAsStringSync();
      expect(source, contains('category: BlockCategory.comment'));
    },
  );

  test('мёртвые параметры Shell вычищены из всех блоков', () {
    // Эти аргументы ничего не рисовали, но были в 24 вызовах; возврат
    // любого из них — регрессия, её ловим здесь. `accent:` добавился сейчас:
    // корпус уже цвет категории, отдельный акцент плашкам не нужен.
    // `transparentBody:` — прежний способ отдать детей контейнера внутрь
    // цветного корпуса (#326); теперь они идут в `body:` под карточкой.
    final dir = Directory('$_editorDir/widgets');
    expect(dir.existsSync(), isTrue, reason: 'запуск не из корня приложения');
    final offenders = <String>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final dead in [
        'dragHandle:',
        'categoryLabel:',
        'tone:',
        'accent:',
        'transparentBody:',
        'ScriptBlockTone',
        'ScriptCategoryTone',
      ]) {
        if (source.contains(dead)) offenders.add('${file.path} → $dead');
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('слайдер и сегменты белые, а не акцент категории', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      category: BlockCategory.event,
      child: const ScriptFieldsGroup(
        children: [
          ScriptFieldSlider(label: 'Громкость', value: 0.5),
          ScriptFieldSegmented<String>(
            label: 'Режим',
            value: 'a',
            options: [
              (value: 'a', label: 'А', icon: null),
              (value: 'b', label: 'Б', icon: null),
            ],
          ),
        ],
      ),
    );

    final sliderTheme = SliderTheme.of(tester.element(find.byType(Slider)));
    expect(sliderTheme.activeTrackColor, blockFg);
    expect(sliderTheme.thumbColor, blockFg);
    expect(sliderTheme.inactiveTrackColor, blockFg.withValues(alpha: 0.3));

    final style = tester
        .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
        .style!;
    expect(style.foregroundColor!.resolve({}), blockFg);
    expect(
      style.backgroundColor!.resolve({WidgetState.selected}),
      blockFg.withValues(alpha: 0.24),
    );
    expect(style.backgroundColor!.resolve({}), Colors.transparent);
    // Провал по той же причине, что и у слайдера: акцент категории на залитом
    // корпусе не отличим от самого корпуса.
    expect(
      style.foregroundColor!.resolve({}),
      isNot(blockAccent(Brightness.dark, BlockCategory.event)),
    );
  });

  // Сверка с эталонным блочным редактором (#333): блок читается фразой.
  // Подпись над значением удваивала высоту каждого поля, и скрипт из десяти
  // блоков превращался в колонку плашек, а не в список действий.

  Rect _chipRect(WidgetTester tester, String text) => tester.getRect(
    find
        .ancestor(
          of: find.text(text),
          matching: find.byType(Material),
        )
        .first,
  );

  testWidgets('поле — одна строка: подпись и значение бок о бок', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      child: const ScriptFieldTile(
        label: 'Переменная',
        value: 'flag_door_open',
      ),
    );

    final label = tester.getRect(find.text('Переменная'));
    final value = tester.getRect(find.text('flag_door_open'));
    expect(
      value.left,
      greaterThan(label.right),
      reason: 'значение ушло под подпись — поле снова в две строки',
    );
    // Пересечение по вертикали = та же строка.
    expect(value.top, lessThan(label.bottom));
    expect(value.bottom, greaterThan(label.top));
  });

  testWidgets('короткие поля становятся в один ряд, а не в колонку', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      child: const ScriptFieldsGroup(
        children: [
          ScriptFieldTile(label: 'X', value: '100'),
          ScriptFieldTile(label: 'Y', value: '200'),
        ],
      ),
    );

    final x = tester.getRect(find.text('100'));
    final y = tester.getRect(find.text('200'));
    expect(y.left, greaterThan(x.right));
    expect(y.top, x.top, reason: 'поля разъехались по строкам');
  });

  testWidgets('плашка обнимает короткое значение, а не тянется на карточку', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      child: const ScriptFieldsGroup(
        children: [ScriptFieldTile(label: 'X', value: '1')],
      ),
    );

    final chip = _chipRect(tester, '1');
    final card = tester.getRect(_shellFinder);
    expect(
      chip.width,
      lessThan(card.width / 3),
      reason: 'короткое поле растянуто на всю ширину',
    );
  });

  testWidgets('слайдеру остаётся ряд целиком', (tester) async {
    await _pumpShell(
      tester,
      child: const ScriptFieldsGroup(
        children: [
          ScriptFieldTile(label: 'Темп', value: '120'),
          ScriptFieldSlider(label: 'Громкость', value: 0.5),
        ],
      ),
    );

    final chip = _chipRect(tester, '120');
    final track = tester.getRect(find.byType(Slider));
    expect(chip.width, lessThan(track.width / 2));
    // Слайдер под чипом, а не рядом с ним: ему нужна полная ширина.
    expect(track.top, greaterThan(chip.bottom));
  });

  testWidgets('крестика в шапке по умолчанию нет — он за флагом', (
    tester,
  ) async {
    await _pumpShell(tester, onDelete: () {});
    expect(
      find.byIcon(Icons.close_rounded),
      findsNothing,
      reason: 'удаление и так в меню блока, крестик на каждой карточке — шум',
    );

    // Негативный контроль: крестик не вырезан из вёрстки, им правит флаг.
    ScriptBlockFieldStyle.showHeaderDelete = true;
    addTearDown(() => ScriptBlockFieldStyle.showHeaderDelete = false);
    await _pumpShell(tester, onDelete: () {});
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });
}
