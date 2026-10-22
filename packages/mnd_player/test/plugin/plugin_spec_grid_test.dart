// Адаптивность сетки UI-спека и привязка ячейки к данным.
//
// Проверить тут нечего было бы, если бы плагин мог спрашивать у клиента
// ширину экрана: он не может. Поэтому сетка строится так, чтобы адаптировался
// рендерер (`cellWidth`), а ячейка получала идентичность из данных
// (`args = '{key}'`) — без этого кнопка в сетке не различала бы предметы.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/widgets/plugin_spec_view.dart';

const List<Map<String, dynamic>> _items = [
  {'key': 'a', 'name': 'Фонарь', 'icon': 'bulb'},
  {'key': 'b', 'name': 'Карта', 'icon': 'map'},
  {'key': 'c', 'name': 'Верёвка', 'icon': 'drop'},
  {'key': 'd', 'name': 'Ключ', 'icon': 'key'},
];

Map<String, dynamic> _grid({Object? cellWidth}) => {
  'type': 'grid',
  'items': '{bag}',
  'columns': 5,
  'gap': 8,
  if (cellWidth != null) 'cellWidth': cellWidth,
  'row': {
    'type': 'button',
    'label': '{name}',
    'icon': '{icon}',
    'args': '{key}',
    'onPress': 'pick',
  },
};

/// Отрисовать сетку на заданной ширине; вернуть список вызовов обработчиков.
Future<List<String>> _pumpGrid(
  WidgetTester tester,
  double width,
  Map<String, dynamic> spec,
) async {
  final called = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PluginSpecView(
              spec: spec,
              vars: const {'bag': _items},
              questId: 'q.test',
              onHandler: (handler, argument) =>
                  called.add('$handler:$argument'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return called;
}

int _columns(WidgetTester tester) =>
    (tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;

/// Панель как у эталонного инвентаря: колонка с `expand` внутри — именно она
/// и падала в списке контента.
Map<String, dynamic> _panel() => {
  'type': 'card',
  'children': [
    {
      'type': 'column',
      'expand': true,
      'children': [
        {'type': 'text', 'text': 'шапка'},
        {'type': 'text', 'text': 'тело'},
      ],
    },
    {'type': 'caption', 'text': 'подпись'},
  ],
};

void main() {
  testWidgets('expand в неограниченной высоте не роняет раскладку', (
    tester,
  ) async {
    // Список контента даёт айтему неограниченную высоту. `Expanded` в такой
    // колонке — «RenderFlex children have non-zero flex…», а следом каскад
    // assert'ов в semantics: плагин не должен уметь уронить экран.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 379,
            child: ListView(
              children: [
                PluginSpecView(
                  spec: _panel(),
                  vars: const {},
                  questId: 'q.test',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('шапка'), findsOneWidget);
    expect(find.byType(Expanded), findsNothing);
  });

  testWidgets('в ограниченной высоте expand работает', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 379,
            height: 400,
            child: PluginSpecView(
              spec: _panel(),
              vars: const {},
              questId: 'q.test',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(Expanded), findsWidgets);
  });

  testWidgets('без cellWidth сетка берёт колонки из спека', (tester) async {
    await _pumpGrid(tester, 320, _grid());
    expect(_columns(tester), 5, reason: 'сколько попросили, столько и будет');
  });

  testWidgets('cellWidth считает колонки по ширине, но не больше columns', (
    tester,
  ) async {
    await _pumpGrid(tester, 320, _grid(cellWidth: 104));
    expect(_columns(tester), 2, reason: 'в 320 px влезает две ячейки по 104');

    await _pumpGrid(tester, 480, _grid(cellWidth: 104));
    expect(_columns(tester), 4);

    await _pumpGrid(tester, 720, _grid(cellWidth: 104));
    expect(_columns(tester), 5, reason: 'потолок — запрошенные пять колонок');
  });

  testWidgets('ячейка сетки знает, к какому элементу она относится', (
    tester,
  ) async {
    final called = await _pumpGrid(tester, 720, _grid(cellWidth: 104));
    expect(called, isEmpty);

    await tester.tap(find.text('Ключ'));
    expect(called, [
      'pick:d',
    ], reason: 'args подставляется значением из элемента');
  });

  testWidgets('иконка ячейки приходит из элемента, а не зашита в спек', (
    tester,
  ) async {
    await _pumpGrid(tester, 720, _grid(cellWidth: 104));
    expect(
      find.byIcon(Icons.vpn_key),
      findsOneWidget,
      reason: 'Ключ → icon: key',
    );
    expect(find.byIcon(Icons.map), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb), findsOneWidget);
  });

  testWidgets('неизвестное имя иконки не роняет рендерер', (tester) async {
    await _pumpGrid(
      tester,
      720,
      _grid(cellWidth: 104)
        ..['row'] = {
          'type': 'button',
          'label': '{name}',
          'icon': '{нетТакой}',
          'onPress': 'pick',
        },
    );
    // Кнопка молча остаётся без значка: надпись — смысл, иконка — украшение.
    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.text('Ключ'), findsOneWidget);

    // А листовой `icon` рисует заглушку, чтобы автор увидел незакрытое имя.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginSpecView(
            spec: {
              'type': 'row',
              'children': [
                {'type': 'icon', 'icon': 'key'},
                {'type': 'icon', 'icon': 'нетТакой'},
              ],
            },
            vars: const {},
            questId: 'q.test',
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.vpn_key), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('кнопка в узкой ячейке теряет значок, а не переполняется', (
    tester,
  ) async {
    // Пять колонок в 320 px: ячейка уже, чем иконка с надписью. До LayoutBuilder
    // такой спек ронял RenderFlex overflow.
    await _pumpGrid(tester, 320, _grid());
    expect(find.text('Фонарь'), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb), findsNothing);

    // Та же кнопка в широкой ячейке значок показывает.
    await _pumpGrid(tester, 720, _grid());
    expect(find.byIcon(Icons.lightbulb), findsOneWidget);
  });
}
