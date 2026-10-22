// Плеер: затемнение модального окна живёт ровно столько, сколько само окно.
//
// Баг автора: у стека-модалки стоит триггер видимости «показать, когда счётчик
// дойдёт до N». Стекло рисовалось только по `stackModal`, поэтому игрок
// получал потемневшую ноду без окна: тапы заглушены, смотреть не на что.
// Здесь проверяется инвариант «нет стекла без окна» для всех способов скрытия —
// флаг редактора, `set_visible` и условие `onAppear`.
//
// Нужен собранный `.so` (как в `item_hidden_by_engine_test.dart`): движок
// настоящий, условие окна считает ядро, без заглушек. Движок создаётся в
// `setUp`: внутри `testWidgets` царит fake-async, и асинхронный FFI там виснет.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';
import 'package:mnd_player/widgets/pinned_stack_layer.dart';

final String? _soPath = () {
  final env = Platform.environment['MND_FFI_SO'];
  if (env != null && File(env).existsSync()) return env;
  for (final candidate in [
    '../../target/release/libmnd_ffi.so',
    '../../crates/mnd-ffi/target/release/libmnd_ffi.so',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}();

final Object? skipIfNoSo = _soPath == null
    ? 'libmnd_ffi.so не найден: cargo build --release -p mnd-ffi (или MND_FFI_SO)'
    : false;

/// Скрипт-условие видимости: событие onContentAppear с одним condition-блоком.
String _visScript(String expression) => jsonEncode({
  'name': 'vis',
  'blocks': [
    {
      'type': 'event',
      'eventType': 'onContentAppear',
      'children': [
        {
          'type': 'condition',
          'expression': expression,
          'then_blocks': <Object>[],
          'else_blocks': <Object>[],
        },
      ],
    },
  ],
});

const String _never = 'scripts/never.json';
const String _always = 'scripts/always.json';
const String _counter = 'scripts/counter.json';

ContentItem _modalWindow({String? trigger, bool isHidden = false}) =>
    ContentItem(
      id: 'win',
      type: 'stack',
      stackPin: 'center',
      stackModal: true,
      stackWidth: 183,
      stackHeight: 220,
      isHidden: isHidden,
      scriptTriggers: trigger == null ? null : {'onAppear': trigger},
      children: [
        ContentItem(
          id: 'txt',
          type: 'text',
          text: 'МОЛОДЕЦ!!!',
          offsetLeft: 18,
          offsetTop: 20,
          offsetRight: 178,
          offsetBottom: 92,
        ),
      ],
    );

void main() {
  late MeanderGameEngine engine;
  var engineAlive = false;

  group('затемнение модалки и видимость окна', skip: skipIfNoSo, () {
    setUpAll(() async {
      await initRustCore(externalLibrary: ExternalLibrary.open(_soPath!));
    });

    // Движок на каждый тест: условие окна читает состояние движка, и счётчик
    // из прошлого теста сделал бы результат враньём.
    setUp(() async {
      engine = await MeanderGameEngine.create(
        questId: 'q1',
        config: {
          'id': 'q1',
          'title': 'Q',
          'version': '1.0.0',
          'startNodeId': 'n1',
        },
        nodesJson: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'content': {
                'items': [
                  {'type': 'text', 'id': 'note', 'text': 'нода'},
                ],
              },
            },
          ],
        },
        embeddedScripts: {
          _never: _visScript('1==0'),
          _always: _visScript('1==1'),
          _counter: _visScript('{тыквы} >= 20'),
        },
        platformOs: 'linux',
      );
      await engine.startNew(startNodeId: 'n1');
      engineAlive = true;
    });

    tearDown(() {
      if (!engineAlive) return;
      engine.dispose();
      engineAlive = false;
    });

    /// Окно в слое — так его собирает `GameScreen._buildPinnedStacks`.
    /// Возвращает контейнер: им и переключают `set_visible` во время теста.
    Future<ProviderContainer> pumpWindow(
      WidgetTester tester,
      ContentItem item,
    ) async {
      final container = ProviderContainer()
        ..listen(gameStateProvider, (_, __) {});
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: PinnedStackLayer(
                  item: item,
                  viewport: const Size(400, 600),
                  engine: engine,
                  onDismiss: () {},
                  child: ContentDisplayFactory.build(
                    item: item,
                    questId: 'q1',
                    onInteract: (_) {},
                    onInputSubmitted: (_, __) {},
                    onComplete: () {},
                    onTransition: (_) {},
                    onNavigateToNode: (_) {},
                    engine: engine,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    void setVisibility(ProviderContainer container, Object mode) {
      container.read(gameStateProvider.notifier).setVariable(kItemHiddenVar, {
        'win': mode,
      });
    }

    Finder scrim() => find.byKey(kModalScrimKey);

    testWidgets('окно без триггера: стекло и содержимое вместе', (
      tester,
    ) async {
      await pumpWindow(tester, _modalWindow());

      expect(find.text('МОЛОДЕЦ!!!'), findsOneWidget);
      expect(scrim(), findsOneWidget);
    });

    testWidgets('окно, скрытое в редакторе, не затемняет ноду', (tester) async {
      await pumpWindow(tester, _modalWindow(isHidden: true));

      expect(find.text('МОЛОДЕЦ!!!'), findsNothing);
      expect(scrim(), findsNothing);
    });

    testWidgets('ложное условие onAppear: ни окна, ни стекла', (tester) async {
      await pumpWindow(tester, _modalWindow(trigger: _never));

      expect(find.text('МОЛОДЕЦ!!!'), findsNothing);
      expect(scrim(), findsNothing);
    });

    testWidgets('истинное условие onAppear: стекло на месте', (tester) async {
      await pumpWindow(tester, _modalWindow(trigger: _always));

      expect(find.text('МОЛОДЕЦ!!!'), findsOneWidget);
      expect(scrim(), findsOneWidget);
    });

    testWidgets('стекло приходит в тот же кадр, что и окно', (tester) async {
      // Ровно сценарий автора: окно на счётчике. До его срабатывания нода не
      // затемнена, после — затемнена.
      // Ноль кладём руками: неопределённая переменная в условии ядром
      // считается как «истина», а в квесте автора счётчик существует с самого
      // начала.
      engine.setStateVariable('тыквы', 0);
      final container = await pumpWindow(
        tester,
        _modalWindow(trigger: _counter),
      );
      expect(find.text('МОЛОДЕЦ!!!'), findsNothing);
      expect(scrim(), findsNothing);

      engine.setStateVariable('тыквы', 20);
      // Состояние движка слою не видно: переоценка идёт по подписке на
      // провайдер, как после хода скрипта в игре.
      container.read(gameStateProvider.notifier).setVariable('тыквы', 20);
      await tester.pumpAndSettle();

      expect(find.text('МОЛОДЕЦ!!!'), findsOneWidget);
      expect(scrim(), findsOneWidget);
    });

    testWidgets('set_visible гасит и окно, и стекло', (tester) async {
      final container = await pumpWindow(tester, _modalWindow());
      expect(scrim(), findsOneWidget);

      for (final mode in ['hidden', 'gone']) {
        setVisibility(container, mode);
        await tester.pumpAndSettle();
        expect(scrim(), findsNothing, reason: '«$mode» — окна нет на экране');
      }

      setVisibility(container, 'visible');
      await tester.pumpAndSettle();
      expect(scrim(), findsOneWidget);
    });
  });
}
