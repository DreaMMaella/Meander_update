/// Регрессионные интеграционные тесты через реальный Rust-мост.
///
/// Требуют собранного `target/release/libmnd_ffi.so`:
///   cargo build -p mnd-ffi --release
/// Путь берётся из env `MND_FFI_SO` либо из репозитория по умолчанию.
/// Если библиотеки нет — тесты пропускаются.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_core/contracts/script_runtime.dart' show EventType;
import 'package:mnd_core/runtime/in_memory_script_runtime_state.dart';
import 'package:mnd_core/src/gen/frb_generated.dart' as gen;

String? _soPath() {
  final env = Platform.environment['MND_FFI_SO'];
  if (env != null && File(env).existsSync()) return env;
  final candidates = [
    '../../target/release/libmnd_ffi.so',
    '../target/release/libmnd_ffi.so',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return File(c).absolute.path;
  }
  return null;
}

final String? soPath = _soPath();

final String skipReason = soPath == null
    ? 'libmnd_ffi.so не найден. Соберите: cargo build -p mnd-ffi --release (или задайте MND_FFI_SO)'
    : '';

final Object? skipIfNoSo = soPath == null ? skipReason : false;

Map<String, dynamic> _battleNodeItem(String scriptRef) => {
      'type': 'button',
      'id': 'b1',
      'scriptTriggers': {'onPress': scriptRef},
    };

Future<MeanderGameEngine> _engine({
  Map<String, dynamic>? config,
  Map<String, dynamic>? nodes,
  Map<String, String> embeddedScripts = const {},
}) async {
  return MeanderGameEngine.create(
    questId: 'q1',
    config: config ??
        {'id': 'q1', 'title': 'Q', 'version': '1.0.0', 'startNodeId': 'n1'},
    nodesJson: nodes ??
        {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'content': {'items': [
                {'type': 'text', 'id': 'a', 'text': 'hello'}
              ]},
            }
          ]
        },
    embeddedScripts: embeddedScripts,
    platformOs: 'linux',
  );
}

void main() {
  if (soPath != null) {
    setUpAll(() async {
      await gen.RustLib.init(
        externalLibrary: ExternalLibrary.open(soPath!),
      );
    });
  }

  group('Интеграция Rust-ядра (реальный .so)', skip: skipIfNoSo, () {
    // ─── Баг 4: числа без .0 ────────────────────────────────────────────────
    test('Баг 4: evaluateExpression("12.0") → 12 (не 12.0)', () {
      final state = InMemoryScriptRuntimeState();
      expect(ScriptExecutor.evaluateExpression('12.0', state), 12);
      expect(ScriptExecutor.evaluateExpression('2 + 3 * 4', state), 14);
      expect(ScriptExecutor.evaluateExpression('10 / 4', state), 2.5);
      state.setVariable('hp', 90);
      expect(ScriptExecutor.evaluateExpression('hp', state), 90);
    });

    // ─── Баги 1/2/3: очередь задержек в дельте движка ──────────────────────
    test('Баг 1/2/3: wait в скрипте → _internal_delay_queue [500, 250]', () async {
      final engine = await _engine(
        nodes: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'content': {'items': [
                {
                  'type': 'script',
                  'id': 's1',
                  'resourcePath': 'scripts/battle.json'
                },
                {'type': 'text', 'id': 't1', 'text': 'go'},
              ]},
            }
          ]
        },
        embeddedScripts: {
          'scripts/battle.json': jsonEncode({
            'name': 'battle',
            'blocks': [
              {'type': 'event', 'eventType': 'onContentAppear', 'children': [
                {'type': 'assign_variable', 'variable': 'stance', 'value': '1'},
                {'type': 'wait', 'expression': '500'},
                {'type': 'assign_variable', 'variable': 'stance', 'value': '0'},
                {'type': 'wait', 'expression': '250'},
              ]},
            ],
          }),
        },
      );
      final view = await engine.startNew();
      expect(view?['nodeId'], 'n1');
      final step = await engine.nextItem();
      expect(step.kind, 'item');
      expect(step.item?['id'], 't1');
      expect(await engine.evaluate('stance'), 0);

      final queueRaw = await engine.evaluate('_internal_delay_queue');
      final queue = queueRaw is String ? jsonDecode(queueRaw) as List<dynamic> : queueRaw as List<dynamic>;
      // Каждый шаг — checkpoint: снапшот переменных (JSON-строки значений),
      // изменённых с прошлого wait'а.
      expect(
        queue,
        [
          {
            'type': 'delay',
            'ms': 500,
            'variables': {'stance': '1'},
            'tables': <String, dynamic>{},
            'audio': <dynamic>[],
          },
          {
            'type': 'delay',
            'ms': 250,
            'variables': {'stance': '0'},
            'tables': <String, dynamic>{},
            'audio': <dynamic>[],
          },
        ],
      );
    });

    test('Баг 1/2/3: wait "500ms" (юнит-суффикс) не должен давать 500 мс',
        () async {
      // Старый Dart-движок: evaluateExpression("500ms") → null → ms=0.
      // Rust-движок: парсит как 500 → в очереди лишняя задержка.
      final engine = await _engine(
        nodes: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'content': {'items': [
                {
                  'type': 'script',
                  'id': 's1',
                  'resourcePath': 'scripts/s.json'
                },
                {'type': 'text', 'id': 't1', 'text': 'go'},
              ]},
            }
          ]
        },
        embeddedScripts: {
          'scripts/s.json': jsonEncode({
            'name': 's',
            'blocks': [
              {'type': 'event', 'eventType': 'onContentAppear', 'children': [
                {'type': 'wait', 'expression': '500ms'},
              ]},
            ],
          }),
        },
      );
      await engine.startNew();
      await engine.nextItem();
      final queueRaw = await engine.evaluate('_internal_delay_queue');
      // Переменная может отсутствовать (evaluate вернёт имя строкой) — в
      // любом случае задержки быть не должно.
      final queue = queueRaw is List<dynamic> ? queueRaw : const <dynamic>[];
      expect(queue, isEmpty, reason: '500ms — не число, задержки быть не должно');
    });

    // ─── wait → go_to_node: transition сразу, пауза через drainDelayQueue ───
    test('wait → go_to_node: transition + очередь [1000], drain очищает',
        () async {
      final engine = await _engine(
        nodes: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'scriptAssetId': 'scripts/go.json',
              'content': {'items': <dynamic>[]},
            },
            {
              'id': 'n2',
              'title': 'Next',
              'content': {'items': [
                {'type': 'text', 'id': 't2', 'text': 'arrived'}
              ]},
            },
          ]
        },
        embeddedScripts: {
          'scripts/go.json': jsonEncode({
            'name': 'go',
            'blocks': [
              {'type': 'event', 'eventType': 'onNodeEnter', 'children': [
                {'type': 'wait', 'expression': '1000'},
                {'type': 'go_to_node', 'node_id': 'n2'},
              ]},
            ],
          }),
        },
      );
      final view = await engine.startNew();
      expect(view?['transition'], 'n2');

      // Клиент должен прождать 1000 мс перед переходом.
      final delays = await engine.drainDelayQueue();
      expect(delays, [1000]);

      // Повторный drain — пусто.
      expect(await engine.drainDelayQueue(), isEmpty);

      // Переход по-прежнему работает.
      final view2 = await engine.loadNode('n2');
      expect(view2?['nodeId'], 'n2');
      expect(await engine.drainDelayQueue(), isEmpty);
    });

    test('wait в onPress-триггере: очередь видна до перехода', () async {
      final engine = await _engine(
        embeddedScripts: {
          'scripts/btn.json': jsonEncode({
            'name': 'btn',
            'blocks': [
              {'type': 'event', 'eventType': 'onPress', 'children': [
                {'type': 'wait', 'expression': '300'},
                {'type': 'go_to_node', 'node_id': 'n2'},
              ]},
            ],
          }),
        },
        nodes: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'content': {'items': [
                {
                  'type': 'button',
                  'id': 'b1',
                  'scriptTriggers': {'onPress': 'scripts/btn.json'},
                }
              ]},
            },
            {
              'id': 'n2',
              'title': 'Next',
              'content': {'items': [
                {'type': 'text', 'id': 't2', 'text': 'done'}
              ]},
            },
          ]
        },
      );
      await engine.startNew();
      final next = await engine.handleInteraction(
        {'type': 'button', 'id': 'b1', 'scriptTriggers': {'onPress': 'scripts/btn.json'}},
        'scripts/btn.json',
      );
      expect(next, 'n2');
      expect(await engine.drainDelayQueue(), [300]);
      expect(await engine.drainDelayQueue(), isEmpty);
    });

    // ─── Баг 6: повторные нажатия ретриггерят звук ─────────────────────────
    test('Баг 6: два нажатия → playSound в drainAudio дважды', () async {
      final engine = await _engine(
        nodes: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'content': {'items': [_battleNodeItem('scripts/btn.json')]},
            }
          ]
        },
        embeddedScripts: {
          'scripts/btn.json': jsonEncode({
            'name': 'btn',
            'blocks': [
              {'type': 'event', 'eventType': 'onPress', 'children': [
                {'type': 'play_sound', 'audio_id': 'sfx/click.wav', 'volume': '0.9'},
              ]},
            ],
          }),
        },
      );
      final view = await engine.startNew();
      expect(view?['nodeId'], 'n1');
      final button = _battleNodeItem('scripts/btn.json');

      await engine.handleInteraction(button, 'scripts/btn.json');
      var audio = await engine.drainAudio();
      expect((audio['commands'] as List).first['id'], 'sfx/click.wav');

      // Повторный drain пуст — не зацикливается.
      audio = await engine.drainAudio();
      expect(audio['commands'] as List, isEmpty);

      // Второе нажатие — звук снова.
      await engine.handleInteraction(button, 'scripts/btn.json');
      audio = await engine.drainAudio();
      expect((audio['commands'] as List).first['id'], 'sfx/click.wav');
    });

    // ─── Баг 7: музыка главы в NodeView, без команд рестарта ───────────────
    test('Баг 7: BGM главы в NodeView; соседняя нода — без команд', () async {
      final engine = await _engine(
        config: {
          'id': 'q1',
          'title': 'Q',
          'version': '1.0.0',
          'startNodeId': 'n1',
          'tags': [
            {'id': 'ch1', 'name': 'Глава 1', 'backgroundAudioId': 'chapter.mp3'},
          ],
        },
        nodes: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'chapterId': 'ch1',
              'content': {'items': [
                {'type': 'text', 'id': 'a', 'text': 'one'},
              ]},
            },
            {
              'id': 'n2',
              'title': 'Next',
              'chapterId': 'ch1',
              'content': {'items': [
                {'type': 'text', 'id': 'b', 'text': 'two'},
              ]},
            },
          ]
        },
      );
      final view1 = await engine.startNew();
      expect((view1?['backgroundAudio'] as Map)['audioId'], 'chapter.mp3');
      var audio = await engine.drainAudio();
      expect(audio['commands'] as List, isEmpty);

      final view2 = await engine.loadNode('n2');
      expect((view2?['backgroundAudio'] as Map)['audioId'], 'chapter.mp3');
      audio = await engine.drainAudio();
      expect(audio['commands'] as List, isEmpty);
    });

    // ─── Баг 8: crossfade ───────────────────────────────────────────────────
    test('Баг 8: crossfade → drainAudio.commands = [fadeOut, fadeIn]', () async {
      final engine = await _engine(
        nodes: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'content': {'items': [
                {
                  'type': 'script',
                  'id': 's1',
                  'resourcePath': 'scripts/cf.json'
                },
                {'type': 'text', 'id': 't1', 'text': 'go'},
              ]},
            }
          ]
        },
        embeddedScripts: {
          'scripts/cf.json': jsonEncode({
            'name': 'cf',
            'blocks': [
              {'type': 'event', 'eventType': 'onContentAppear', 'children': [
                {'type': 'crossfade', 'duration': '1.5', 'children': [
                  {'type': 'assign_variable', 'variable': 'mid', 'value': '1'},
                ]},
              ]},
            ],
          }),
        },
      );
      await engine.startNew();
      await engine.nextItem();
      final audio = await engine.drainAudio();
      final commands = (audio['commands'] as List).cast<Map<String, dynamic>>();
      expect(commands.map((c) => c['type']).toList(), ['fadeOut', 'fadeIn'],
          reason: 'клиент ждёт команды fade-out/fade-in (Bug 8)');
      expect(commands[0]['ms'], 1500);
      expect(commands[1]['ms'], 1500);
    });

    test('Баг 8: первый drain не должен эмитить pauseResume toggle', () async {
      // Начальное состояние движка: _internal_pause_resume_target="all",
      // action="toggle" → первый drainAudio() отдаёт команду, и клиент
      // ставит музыку на паузу сразу после старта.
      final engine = await _engine();
      await engine.startNew();
      final audio = await engine.drainAudio();
      expect(audio['commands'] as List, isEmpty,
          reason: 'на свежем движке команд pause/resume быть не должно');
    });

    // ─── Баг 9: мутация onContentAppear ровно один раз ─────────────────────
    test('Баг 9: мутация onContentAppear ровно один раз (200 → 40)', () async {
      final engine = await _engine(
        config: {
          'id': 'q1',
          'title': 'Q',
          'version': '1.0.0',
          'startNodeId': 'n1',
          'variables': [
            {'name': 'Примогемы', 'defaultValue': 200},
          ],
        },
        nodes: {
          'nodes': [
            {
              'id': 'n1',
              'title': 'Start',
              'content': {'items': [
                {
                  'type': 'script',
                  'id': 's1',
                  'resourcePath': 'scripts/gacha.json'
                },
                {'type': 'text', 'id': 't1', 'text': 'Результат'},
              ]},
            }
          ]
        },
        embeddedScripts: {
          'scripts/gacha.json': jsonEncode({
            'name': 'gacha',
            'blocks': [
              {'type': 'event', 'eventType': 'onContentAppear', 'children': [
                {'type': 'assign_variable', 'variable': 'Примогемы', 'value': 'Примогемы - 160'},
              ]},
            ],
          }),
        },
      );
      await engine.startNew();
      expect(await engine.evaluate('Примогемы'), 200);

      final step = await engine.nextItem();
      expect(step.kind, 'item');
      expect(step.item?['id'], 't1');
      expect(await engine.evaluate('Примогемы'), 40);

      // Повторное раскрытие не мутирует повторно.
      final step2 = await engine.nextItem();
      expect(step2.kind, 'done');
      expect(await engine.evaluate('Примогемы'), 40);

      final delta = await engine.drainStateDelta();
      expect(delta['variables']['Примогемы'], '40');
      final delta2 = await engine.drainStateDelta();
      expect(delta2['variables'].containsKey('Примогемы'), isFalse);
    });

    // ─── Баг 9: evaluateCondition с allowStateMutation: false ──────────────
    test('Баг 9: evaluateCondition(allowStateMutation: false) не мутирует',
        () {
      final state = InMemoryScriptRuntimeState(variables: {
        'Примогемы': 200,
      });
      final script = {
        'name': 'gacha',
        'blocks': [
          {
            'type': 'assign_variable',
            'variable': 'Примогемы',
            'value': 'Примогемы - 160'
          },
          {
            'type': 'condition',
            'expression': '{Примогемы} > 160',
            'then_blocks': [],
          },
        ],
      };
      expect(
        ScriptExecutor.evaluateCondition(script, state,
            allowStateMutation: false),
        isTrue,
      );
      expect(state.getVariable('Примогемы'), 200,
          reason: 'условие не должно менять состояние');
    });

    // ─── Триггеры видимости (onAppear): пин контракта ─────────────────────
    // Эталоном эти тесты закрывают: (1) коэрцию строка↔bool в условиях
    // видимости, (2) поведение флага allowStateMutation в evaluateCondition,
    // который использует ConditionalContentWrapper из mnd_player. Если что-то
    // из этого вырезать/сломать, Dart-обёртка видимости тихо перестанет
    // работать («триггеры видимости не работают вообще», регрессия a86a2c5).
    test(
        'Видимость: строка "false"/"true" из config коэрсит в условии onAppear',
        () {
      // Переменная из config приходит строкой, скрипт сравнивает с литералами.
      final state = InMemoryScriptRuntimeState(variables: {
        'первый вход': 'false',
        'куплено.кирка': 'false',
      });
      final script = {
        'name': 'vis',
        'blocks': [
          {
            'type': 'event',
            'eventType': 'onContentAppear',
            'children': [
              {
                'type': 'condition',
                'expression': '{первый вход}==false',
                'then_blocks': [],
              },
            ],
          },
        ],
      };
      expect(
        ScriptExecutor.evaluateCondition(script, state,
            eventType: EventType.onContentAppear,
            allowTargetMismatchFallback: true,
            allowStateMutation: true),
        isTrue,
        reason: 'строка "false" должна быть эквивалентна литералу false',
      );
      expect(
        ScriptExecutor.evaluateCondition(script, state,
            eventType: EventType.onContentAppear,
            allowTargetMismatchFallback: true,
            allowStateMutation: false),
        isTrue,
        reason: 'повторная переоценка (без мутаций) даёт тот же результат',
      );

      // Флаг переключили — условие больше не срабатывает.
      state.setVariable('первый вход', 'true');
      expect(
        ScriptExecutor.evaluateCondition(script, state,
            eventType: EventType.onContentAppear,
            allowTargetMismatchFallback: true,
            allowStateMutation: true),
        isFalse,
      );
    });

    test('Видимость: allowStateMutation=true выполняет прелюдию', () {
      // Паритет: первая оценка видимости в ConditionalContentWrapper идёт с
      // мутациями (табличная прелюдия/assign), повторная — без.
      final state = InMemoryScriptRuntimeState(variables: {'показ': 0});
      final script = {
        'name': 'vis',
        'blocks': [
          {
            'type': 'event',
            'eventType': 'onContentAppear',
            'children': [
              {
                'type': 'assign_variable',
                'variable': 'показ',
                'value': '{показ}+1',
              },
              {
                'type': 'condition',
                'expression': '2 > 1',
                'then_blocks': [],
              },
            ],
          },
        ],
      };
      expect(
        ScriptExecutor.evaluateCondition(script, state,
            eventType: EventType.onContentAppear,
            allowTargetMismatchFallback: true,
            allowStateMutation: true),
        isTrue,
      );
      expect(state.getVariable('показ'), 1,
          reason: 'первая оценка с allowStateMutation:true мутирует');

      final before = state.getVariable('показ');
      expect(
        ScriptExecutor.evaluateCondition(script, state,
            eventType: EventType.onContentAppear,
            allowTargetMismatchFallback: true,
            allowStateMutation: false),
        isTrue,
      );
      expect(state.getVariable('показ'), before,
          reason: 'повторная переоценка без мутаций (watch-путь)');
    });
  });
}