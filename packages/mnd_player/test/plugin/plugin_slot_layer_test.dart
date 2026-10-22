// Слой плагинного UI: surface'ы должны попадать только в свою область,
// нажатия — уходить автору surface'а, а не тому, кто объявил слот.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/engine/plugin_host.dart';
import 'package:mnd_player/plugin/plugin_runtime.dart';
import 'package:mnd_player/widgets/plugin_slot_layer.dart';

class _FakeBackend implements PluginBackend {
  final List<String> handlers = [];
  PluginDispatch next = const PluginDispatch.empty('');
  List<Map<String, dynamic>> slotList = const [];
  List<String> hookList = const [];

  @override
  Future<PluginDispatch> invokeEvent({
    required String event,
    Map<String, dynamic> payload = const {},
    PluginCallContext context = const PluginCallContext(),
  }) async => next;

  @override
  Future<PluginDispatch> call({
    required String pluginId,
    required String function,
    Object? args,
    PluginCallContext context = const PluginCallContext(),
  }) async {
    handlers.add('$pluginId#$function($args)');
    return const PluginDispatch.empty('');
  }

  @override
  Future<List<Map<String, dynamic>>> slots() async => slotList;

  @override
  Future<List<String>> activeHooks() async => hookList;
}

PluginDispatch _rendered(String target, Map<String, dynamic> spec) =>
    PluginDispatch.fromJson({
      'event': 'node_enter',
      'outcomes': [
        {
          'pluginId': 'mnd.demo.hud',
          'commands': [
            {'kind': 'render', 'target': target, 'spec': spec},
          ],
          'varWrites': {},
          'logs': [],
          'emits': [],
        },
      ],
      'storages': {},
      'notes': [],
    });

Map<String, dynamic> _button(String label, {Object? args}) => {
  'type': 'button',
  'label': label,
  'onPress': 'pressMe',
  if (args != null) 'args': args,
};

Future<PluginRuntime> _runtimeWith(
  _FakeBackend backend,
  String target,
  Map<String, dynamic> spec,
) async {
  final runtime = PluginRuntime(
    backend: backend,
    questId: 'q1',
    readVars: () => const {'hp': 7},
  );
  backend.slotList = [
    {'pluginId': 'mnd.other.slot', 'id': 'topRight', 'area': 'hud', 'priority': 1},
  ];
  backend.hookList = ['node_enter'];
  backend.next = _rendered(target, spec);
  await runtime.refresh();
  await runtime.dispatchEvent('node_enter');
  return runtime;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late _FakeBackend backend;
  setUp(() => backend = _FakeBackend());

  testWidgets('surface области рисуется и отправляет нажатие автору', (tester) async {
    final runtime = await _runtimeWith(
      backend,
      'slot:topRight',
      {
        'type': 'column',
        'children': [_button('Взять', args: 'sword')],
      },
    );

    await tester.pumpWidget(
      _host(
        PluginSlotLayer(
          runtime: runtime,
          area: 'hud',
          questId: 'q1',
          vars: const {'hp': 7},
          nodeId: 'n1',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Взять'), findsOneWidget);
    await tester.tap(find.text('Взять'));
    expect(backend.handlers, ['mnd.demo.hud#pressMe(sword)']);
  });

  testWidgets('слой области не рисует айтемы, а они живут ровно одну ноду', (tester) async {
    final runtime = await _runtimeWith(
      backend,
      'item:torch',
      {'type': 'column', 'children': [_button('Турникет')]},
    );

    await tester.pumpWidget(
      _host(
        PluginSlotLayer(
          runtime: runtime,
          area: 'hud',
          questId: 'q1',
          vars: const {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Турникет'), findsNothing, reason: 'слой слотов рисует только slot:');
    expect(runtime.freeSurfaces, hasLength(1), reason: 'айтем ждёт своего виджета');

    runtime.clearItemSurfaces();
    await tester.pump();
    expect(runtime.specFor('item:torch'), isNull);
    expect(runtime.freeSurfaces, isEmpty);
  });

  testWidgets('захват экрана перекрывает игру и закрывается крестиком', (tester) async {
    final runtime = await _runtimeWith(
      backend,
      'screen',
      {'type': 'column', 'children': [_button('Продолжить')]},
    );

    await tester.pumpWidget(
      _host(
        Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: Colors.white, child: Text('игра под слоем')),
            ),
            PluginScreenLayer(runtime: runtime, questId: 'q1', vars: const {}),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Продолжить'), findsOneWidget);
    await tester.tap(find.text('Продолжить'));
    expect(backend.handlers, ['mnd.demo.hud#pressMe(null)']);

    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pump();
    expect(runtime.specFor('screen'), isNull, reason: 'крестик обязан снимать surface');
    expect(find.text('Продолжить'), findsNothing);
    expect(find.text('игра под слоем'), findsOneWidget);
  });
}
