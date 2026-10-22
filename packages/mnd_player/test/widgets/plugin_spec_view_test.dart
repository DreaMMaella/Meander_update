// Рендерер декларативного UI-спека плагина: плагин присылает JSON из
// фиксированного набора типов, а рисует его этот виджет. Проверяем то, за чем
// охотятся авторы плагинов: подстановку переменных квеста, шаблоны строк у
// list/grid, колбэки-имена функций (не код), безопасные заглушки.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/widgets/plugin_spec_view.dart';

Widget _wrap(
  Map<String, dynamic> spec, {
  Map<String, dynamic> vars = const {},
  PluginHandlerCallback? onHandler,
}) => MaterialApp(
  home: Scaffold(
    body: PluginSpecView(
      spec: spec,
      vars: vars,
      onHandler: onHandler ?? (_, __) {},
    ),
  ),
);

void main() {
  testWidgets('text binds to quest variables', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const {'type': 'column', 'children': [
          {'type': 'text', 'text': 'HP {hp}/{hpMax}'},
          {'type': 'caption', 'text': 'режим: {hard}'},
          {'type': 'text', 'text': 'неизвестное: {missing}'},
        ]},
        vars: const {'hp': 7, 'hpMax': 10, 'hard': true},
      ),
    );

    expect(find.text('HP 7/10'), findsOneWidget);
    expect(find.text('режим: да'), findsOneWidget);
    // Пропавшая переменная остаётся видимой — автор видит опечатку.
    expect(find.text('неизвестное: {missing}'), findsOneWidget);
  });

  testWidgets('list renders a row template over an array variable', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const {
          'type': 'list',
          'items': '{inv}',
          'gap': 4,
          'row': {'type': 'text', 'text': '{name} × {count}'},
        },
        vars: const {
          'inv': [
            {'name': 'факел', 'count': 3},
            {'name': 'ключ', 'count': 1},
          ],
        },
      ),
    );

    expect(find.text('факел × 3'), findsOneWidget);
    expect(find.text('ключ × 1'), findsOneWidget);
  });

  testWidgets('grid walks a literal list of scalars', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const {
          'type': 'grid',
          'columns': 2,
          'items': ['дверь', 'замок', 'ключ'],
          'row': {'type': 'badge', 'label': '{value}'},
        },
      ),
    );

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('дверь'), findsOneWidget);
    expect(find.text('ключ'), findsOneWidget);
  });

  testWidgets('nested path and index resolve from variables', (tester) async {
    expect(
      resolvePluginVariables(
        '{hero.items[1].name}',
        const {
          'hero': {
            'items': [
              {'name': 'меч'},
              {'name': 'щит'},
            ],
          },
        },
        null,
      ),
      'щит',
    );
  });

  testWidgets('button press calls the plugin function by name', (tester) async {
    final calls = <List<Object?>>[];
    await tester.pumpWidget(
      _wrap(
        const {'type': 'button', 'label': 'Открыть', 'onPress': 'open_bag'},
        onHandler: (handler, argument) => calls.add([handler, argument]),
      ),
    );

    await tester.tap(find.text('Открыть'));
    expect(calls, [
      ['open_bag', null],
    ]);
  });

  testWidgets('switch and slider report their value through onChange', (tester) async {
    final calls = <List<Object?>>[];
    await tester.pumpWidget(
      _wrap(
        const {'type': 'column', 'children': [
          {'type': 'switch', 'label': 'Музыка', 'checked': true, 'onChange': 'toggle_music'},
          {'type': 'slider', 'value': 0.4, 'onChange': 'set_volume'},
        ]},
        onHandler: (handler, argument) => calls.add([handler, argument]),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.drag(find.byType(Slider), const Offset(40, 0));
    expect(calls.first.first, 'toggle_music');
    expect(calls.first[1], {'value': false});
    expect(calls.last.first, 'set_volume');
    expect((calls.last[1] as Map)['value'], isA<double>());
  });

  testWidgets('layout props build the expected widgets', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const {'type': 'column', 'gap': 8, 'padding': 12, 'children': [
          {'type': 'heading', 'text': 'Инвентарь', 'bold': true, 'color': 'gold'},
          {'type': 'row', 'justify': 'space', 'children': [
            {'type': 'icon', 'icon': 'key'},
            {'type': 'divider'},
            {'type': 'progress', 'value': 25, 'max': 100},
          ]},
          {'type': 'card', 'background': '#202428', 'radius': 10, 'children': [
            {'type': 'text', 'text': 'внутри карточки'},
          ]},
        ]},
      ),
    );

    expect(find.byType(Column), findsWidgets);
    expect(find.byType(Row), findsWidgets);
    expect(find.byIcon(Icons.vpn_key), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.25);
    final heading = tester.widget<Text>(find.text('Инвентарь'));
    expect(heading.style?.fontWeight, FontWeight.bold);
    expect(heading.style?.color, const Color(0xFFD4AF37));
    expect(find.text('внутри карточки'), findsOneWidget);
  });

  testWidgets('unknown widget type degrades to a placeholder', (tester) async {
    await tester.pumpWidget(_wrap(const {'type': 'webview', 'url': 'https://evil'}));
    expect(find.textContaining('Неизвестный виджет: webview'), findsOneWidget);
  });

  testWidgets('stack positions children absolutely by x/y', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const {'type': 'stack', 'height': 200, 'children': [
          {'type': 'text', 'text': 'метка', 'x': 40, 'y': 60},
          {'type': 'icon', 'icon': 'star'},
        ]},
      ),
    );

    final stack = tester.widget<Stack>(find.byType(Stack).first);
    expect(find.byType(Positioned), findsOneWidget);
    expect(stack.children.length, 2);
  });
}
