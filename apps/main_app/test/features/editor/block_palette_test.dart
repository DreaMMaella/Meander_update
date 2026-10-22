// Палитра блоков — место, где автор выбирает, что добавить в скрипт. Раньше
// это был полноэкранный список без поиска, а выбранный блок нужно было ещё и
// перетащить в нужное место. Здесь контракт нового поведения: поиск по подписи
// и по слову из подсказки, фильтр по категориям, тап сразу возвращает блок, а
// «недавние» не дублируются и не растут бесконечно.

import 'package:canvas_app/features/editor/screens/visual_script_editor/action_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<BlockPaletteEntry> _entries = [
  BlockPaletteEntry(
    name: 'assign_variable',
    displayName: 'Присвоить переменную',
    category: 'variable',
  ),
  BlockPaletteEntry(
    name: 'table_operation',
    displayName: 'Работа с таблицей',
    category: 'data',
  ),
  BlockPaletteEntry(
    name: 'wait',
    displayName: 'Пауза',
    category: 'flow',
  ),
  BlockPaletteEntry(
    name: 'play_sound',
    displayName: 'Звук',
    category: 'audio',
  ),
];

/// Телефон в горизонтальном сечении: 420x1200. Именно `view`, а не
/// `setSurfaceSize` — палитра берёт высоту из `MediaQuery.sizeOf`, а тот
/// читается с вью, и с surface-размером остался бы экран 800x600.
Future<void> _usePhoneSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpPalette(
  WidgetTester tester, {
  List<BlockPaletteEntry>? entries,
}) async {
  await _usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: BlockPalette(entries: entries ?? _entries))),
  );
  await tester.pump();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('block-palette-search')), query);
  await tester.pump();
}

/// Чип фильтра категории ищем внутри FilterChip: под заголовком секции живёт
/// такой же текст, и `find.text` нашёл бы сразу два виджета.
Finder _chip(String label) =>
    find.descendant(of: find.byType(FilterChip), matching: find.text(label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('фильтр палитры', () {
    test('нужны все слова запроса, регистр не важен', () {
      expect(
        filterPalette(_entries, query: 'ПРИСВОИТ ПЕРЕМЕННУЮ').map((e) => e.name),
        ['assign_variable'],
      );
      // Два слова — И, а не ИЛИ: иначе поиск по «пауза звук» выдавал бы всё
      // подряд и человек решал бы, что палитра сломалась.
      expect(filterPalette(_entries, query: 'пауза звук'), isEmpty);
    });

    test('«ё» в запросе находится там, где в тексте «е»', () {
      expect(
        filterPalette(_entries, query: 'сетк').map((e) => e.name),
        contains('table_operation'),
      );
      expect(
        filterPalette(_entries, query: 'сётк').map((e) => e.name),
        contains('table_operation'),
      );
    });

    test('поиск доходит до слов из подсказки, не только до подписи', () {
      // «лавка» есть только в тексте подсказки категории «Данные» — автор
      // набирает то, что уже читал под блоком.
      expect(
        filterPalette(_entries, query: 'лавка').map((e) => e.name),
        ['table_operation'],
      );
    });

    test('категория ограничивает список, пустой запрос ничего не скрывает', () {
      expect(filterPalette(_entries, category: 'audio').map((e) => e.name), [
        'play_sound',
      ]);
      expect(filterPalette(_entries), _entries);
      expect(filterPalette(_entries, query: 'перемен', category: 'audio'), isEmpty);
    });
  });

  test('недавние: повтор уходит в начало, хвост за лимитом отрезается', () async {
    SharedPreferences.setMockInitialValues({});

    var recent = await recordRecentBlockType('wait');
    recent = await recordRecentBlockType('play_sound');
    recent = await recordRecentBlockType('wait');
    expect(recent, ['wait', 'play_sound']);

    for (final name in ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
      recent = await recordRecentBlockType(name);
    }

    expect(recent.length, kRecentBlockTypesLimit);
    expect(recent.first, 'g');
    expect(recent, isNot(contains('wait')));
    expect(await loadRecentBlockTypes(), recent);
  });

  group('палитра на экране', () {
    testWidgets('блоки лежат под своими категориями', (tester) async {
      await _pumpPalette(tester);

      expect(find.text('Присвоить переменную'), findsOneWidget);
      expect(find.text('Работа с таблицей'), findsOneWidget);
      expect(find.text('Управление'), findsWidgets);
      expect(find.text('Аудио'), findsWidgets);
    });

    testWidgets('поиск скрывает лишние плитки', (tester) async {
      await _pumpPalette(tester);
      await _search(tester, 'лавка');

      expect(find.text('Работа с таблицей'), findsOneWidget);
      expect(find.text('Пауза'), findsNothing);
      expect(find.text('Звук'), findsNothing);
    });

    testWidgets('чип категории фильтрует, «Все» снимает фильтр',
        (tester) async {
      await _pumpPalette(tester);

      // Чип «Данные», а не «Аудио»: ряд чипов — горизонтальный ListView, он
      // строится лениво и шестой чип на узком экране просто не существует.
      await tester.tap(_chip('Данные'));
      await tester.pump();

      expect(find.text('Работа с таблицей'), findsOneWidget);
      expect(find.text('Присвоить переменную'), findsNothing);
      expect(find.text('Пауза'), findsNothing);

      await tester.tap(_chip('Все'));
      await tester.pump();

      expect(find.text('Пауза'), findsOneWidget);
      expect(find.text('Присвоить переменную'), findsOneWidget);
    });

    testWidgets('пустой результат можно сбросить одним тапом', (tester) async {
      await _pumpPalette(tester);
      await _search(tester, 'квартальный отчёт');

      expect(find.text('Ничего не нашлось'), findsOneWidget);

      await tester.tap(find.text('Сбросить'));
      await tester.pump();

      expect(find.text('Ничего не нашлось'), findsNothing);
      expect(find.text('Пауза'), findsOneWidget);
    });

    testWidgets('свой список не читается из хранилища: «Недавних» нет',
        (tester) async {
      await _pumpPalette(tester);

      expect(find.text('Недавние'), findsNothing);
    });

    testWidgets('тап по плитке возвращает выбранный блок', (tester) async {
      await _usePhoneSurface(tester);

      BuildContext? rootContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                rootContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final route = Navigator.of(rootContext!).push<BlockPaletteEntry>(
        // Scaffold как в реальной жизни: и шит (showModalBottomSheet), и
        // диалог дают Material-обёртку, без неё TextField бунтует.
        MaterialPageRoute(
          builder: (_) => Scaffold(body: const BlockPalette(entries: _entries)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Работа с таблицей'));
      await tester.pumpAndSettle();

      final picked = await route;
      expect(picked?.name, 'table_operation');
    });
  });
}
