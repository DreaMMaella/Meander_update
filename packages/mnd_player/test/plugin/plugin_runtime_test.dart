// Прокладка плагин→экран: команды из ядра должны превращаться в surface'ы,
// тосты, записи переменных, переходы и снимки хранилищ — и ничего не дёргать
// в ядре, когда подписчиков у события нет.

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/engine/plugin_host.dart';
import 'package:mnd_player/plugin/plugin_runtime.dart';

class _FakeBackend implements PluginBackend {
  final List<String> events = [];
  final List<String> handlers = [];
  PluginDispatch next = const PluginDispatch.empty('');
  List<Map<String, dynamic>> slotList = const [];
  List<String> hookList = const [];

  @override
  Future<PluginDispatch> invokeEvent({
    required String event,
    Map<String, dynamic> payload = const {},
    PluginCallContext context = const PluginCallContext(),
  }) async {
    events.add(event);
    return next;
  }

  @override
  Future<PluginDispatch> call({
    required String pluginId,
    required String function,
    Object? args,
    PluginCallContext context = const PluginCallContext(),
  }) async {
    handlers.add('$pluginId#$function($args)');
    return next;
  }

  @override
  Future<List<Map<String, dynamic>>> slots() async => slotList;

  @override
  Future<List<String>> activeHooks() async => hookList;
}

PluginDispatch _dispatch(
  List<Map<String, dynamic>> commands, {
  Map<String, Object?> extra = const {},
}) => PluginDispatch.fromJson({
  'event': 'node_enter',
  'outcomes': [
    {
      'pluginId': 'mnd.demo.hud',
      'commands': commands,
      'varWrites': extra['varWrites'] ?? {},
      'logs': [],
      'emits': [],
      'cancel': extra['cancel'] ?? false,
      'error': extra['error'],
      'storageDirty': extra['storageDirty'] ?? false,
    },
  ],
  'storages': extra['storages'] ?? {},
  'notes': extra['notes'] ?? [],
});

void main() {
  late _FakeBackend backend;
  late List<PluginToast> toasts;
  late List<Map<String, dynamic>> writes;
  late List<String> navigations;
  late List<String> sounds;
  late List<MapEntry<String, Map<String, dynamic>>> storages;
  late PluginRuntime runtime;

  setUp(() {
    backend = _FakeBackend();
    toasts = [];
    writes = [];
    navigations = [];
    sounds = [];
    storages = [];
    runtime = PluginRuntime(
      backend: backend,
      questId: 'q1',
      readVars: () => const {'hp': 3},
      onToast: toasts.add,
      onVarWrites: writes.add,
      onNavigate: navigations.add,
      onPlaySound: (asset, volume) => sounds.add('$asset@$volume'),
      onStorage: (id, storage) => storages.add(MapEntry(id, storage)),
    );
  });

  test('мертвое событие не доходит до ядра', () async {
    backend.hookList = ['item_press'];
    await runtime.refresh();
    expect(runtime.listensTo('item_press'), isTrue);

    final canceled = await runtime.dispatchEvent('node_enter');
    expect(canceled, isFalse);
    expect(backend.events, isEmpty);
  });

  test('render в слот появляется в нужной области и снимается по close', () async {
    backend.slotList = const [
      {'pluginId': 'mnd.demo.hud', 'id': 'counter', 'area': 'hud', 'priority': 1},
    ];
    backend.hookList = ['node_enter'];
    await runtime.refresh();
    var notified = 0;
    runtime.addListener(() => notified++);

    backend.next = _dispatch([
      {
        'kind': 'render',
        'target': 'slot:counter',
        'spec': {'type': 'text', 'text': 'HP {hp}'},
      },
    ]);
    await runtime.dispatchEvent('node_enter', nodeId: 'n1');
    expect(runtime.surfacesIn('hud').single.spec, {
      'type': 'text',
      'text': 'HP {hp}',
    });
    expect(runtime.surfacesIn('overlay'), isEmpty);
    expect(notified, 1);

    backend.next = _dispatch([
      {'kind': 'close', 'target': 'slot:counter'},
    ]);
    await runtime.dispatchEvent('node_enter');
    expect(runtime.surfacesIn('hud'), isEmpty);
    expect(notified, 2);
  });

  test('toast/переменные/переход/звук/хранилище расходятся по колбэкам', () async {
    backend.hookList = ['node_enter'];
    await runtime.refresh();
    backend.next = _dispatch(
      [
        {'kind': 'toast', 'text': 'Достигнуто', 'durationMs': 1200},
        {'kind': 'goto_node', 'node': 'end'},
        {'kind': 'play_sound', 'asset': 'win.ogg', 'volume': 0.5},
      ],
      extra: {
        'varWrites': {'gold': 12},
        'storageDirty': true,
        'storages': {'mnd.demo.hud': {'best': 7}},
      },
    );

    expect(await runtime.dispatchEvent('node_enter'), isFalse);
    expect(toasts.single.text, 'Достигнуто');
    expect(toasts.single.duration, const Duration(milliseconds: 1200));
    expect(toasts.single.pluginId, 'mnd.demo.hud');
    expect(writes.single, {'gold': 12});
    expect(navigations, ['end']);
    expect(sounds, ['win.ogg@0.5']);
    expect(storages.single.key, 'mnd.demo.hud');
    expect(storages.single.value, {'best': 7});
  });

  test('cancel у node_enter возвращается экрану', () async {
    backend.hookList = ['node_enter'];
    await runtime.refresh();
    backend.next = _dispatch(const [], extra: {'cancel': true});
    expect(await runtime.dispatchEvent('node_enter'), isTrue);
  });

  test('нажатие в UI плагина зовёт его функцию по имени', () async {
    backend.next = _dispatch([
      {
        'kind': 'render',
        'target': 'screen',
        'spec': {'type': 'button', 'label': 'Ок', 'onPress': 'confirm'},
      },
    ]);
    await runtime.invokeHandler('mnd.demo.hud', 'confirm', argument: const {'value': 3});
    expect(backend.handlers, ['mnd.demo.hud#confirm({value: 3})']);
    expect(runtime.specFor('screen'), isNotNull);
  });

  test('ошибка Lua попадает в notices, но не роняет проход', () async {
    backend.next = _dispatch(
      const [],
      extra: {
        'error': 'вызов без разрешения ui',
        'notes': ['рассылка "custom.x" отклонена'],
      },
    );
    await runtime.invokeHandler('mnd.demo.hud', 'boom');
    expect(runtime.notices, hasLength(2));
    expect(runtime.notices.join('\n'), contains('разрешения'));
  });

  test('forgetPlugin убирает surface снятого плагина', () async {
    backend.slotList = const [
      {'pluginId': 'mnd.demo.hud', 'id': 'counter', 'area': 'hud', 'priority': 1},
    ];
    await runtime.refresh();
    backend.next = _dispatch([
      {
        'kind': 'render',
        'target': 'slot:counter',
        'spec': {'type': 'text', 'text': 'осталось'},
      },
    ]);
    await runtime.invokeHandler('mnd.demo.hud', 'tick');
    expect(runtime.surfacesIn('hud'), hasLength(1));

    runtime.forgetPlugin('mnd.demo.hud');
    expect(runtime.surfacesIn('hud'), isEmpty);
  });
}
