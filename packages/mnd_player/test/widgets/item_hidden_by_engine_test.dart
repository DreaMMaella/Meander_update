// Рантайм: блок `set_visible` меняет видимость любого айтема по команде скрипта.
//
// Ядро пишет переопределение в служебную переменную `_internal_item_hidden`,
// клиент читает её при сборке айтема — модель квеста остаётся нетронутой.
// Здесь проверяется именно клиентская сторона: «скрыть» гасит айтем, но место
// в раскладке держит, «убрать» выводит его из ряда, а очередь раскрытия не
// встаёт на невидимом элементе и не шагает дважды.
//
// Нужен собранный `.so` (как в `image_resource_expr_test.dart`): движок
// настоящий, без заглушек.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';

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

const Key _markerKey = ValueKey('marker');

void main() {
  late MeanderGameEngine engine;

  setUpAll(() async {
    if (_soPath == null) return;
    await initRustCore(externalLibrary: ExternalLibrary.open(_soPath!));
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
                {'type': 'text', 'id': 'note', 'text': 'привет'},
              ],
            },
          },
        ],
      },
      platformOs: 'linux',
    );
  });

  tearDownAll(() {
    if (_soPath != null) engine.dispose();
  });

  ContentItem noteItem() =>
      ContentItem(id: 'note', type: 'text', text: 'привет');

  /// Считает, сколько раз айтем отдал шаг очереди раскрытия.
  int completions = 0;

  /// Айтем в столбце с меткой под ним: по высоте строки метки видно, занял ли
  /// айтем своё место или схлопнул ряд.
  Future<ProviderContainer> render(
    WidgetTester tester, {
    Map<String, dynamic>? hiddenOverrides,
  }) async {
    final container = ProviderContainer()
      ..listen(gameStateProvider, (_, __) {});
    addTearDown(container.dispose);
    if (hiddenOverrides != null) {
      container
          .read(gameStateProvider.notifier)
          .setVariable(kItemHiddenVar, hiddenOverrides);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ContentDisplayFactory.build(
                  item: noteItem(),
                  questId: 'q1',
                  onInteract: (_) {},
                  onInputSubmitted: (_, __) {},
                  onComplete: () => completions++,
                  onTransition: (_) {},
                  onNavigateToNode: (_) {},
                  engine: engine,
                ),
                const SizedBox(key: _markerKey, height: 40),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  void setVisibility(ProviderContainer container, Object value) {
    container.read(gameStateProvider.notifier).setVariable(kItemHiddenVar, {
      'note': value,
    });
  }

  /// Верх метки: 0 — значит айтем не занял места в столбце.
  double markerTop(WidgetTester tester) =>
      tester.getRect(find.byKey(_markerKey)).top;

  // Обёртка невидимости — внешняя: у самого текста внутри тоже бывают
  // Opacity/IgnorePointer, а `find.ancestor` отдаёт совпадения от корня вниз.
  double noteOpacity(WidgetTester tester) => tester
      .widgetList<Opacity>(
        find.ancestor(of: find.text('привет'), matching: find.byType(Opacity)),
      )
      .first
      .opacity;

  bool noteIgnoresTouches(WidgetTester tester) => tester
      .widgetList<IgnorePointer>(
        find.ancestor(
          of: find.text('привет'),
          matching: find.byType(IgnorePointer),
        ),
      )
      .first
      .ignoring;

  group('блок set_visible в рантайме', skip: skipIfNoSo, () {
    testWidgets('айтем виден, пока скрипт его не спрятал', (tester) async {
      completions = 0;
      await render(tester);
      expect(find.text('привет'), findsOneWidget);
      expect(noteOpacity(tester), 1.0);
      expect(noteIgnoresTouches(tester), isFalse);
      expect(markerTop(tester), greaterThan(0));
    });

    testWidgets('«скрыть» гасит айтем, но место в раскладке остаётся', (
      tester,
    ) async {
      final container = await render(tester);
      final topWhileShown = markerTop(tester);

      setVisibility(container, 'hidden');
      await tester.pumpAndSettle();

      // Текст живёт в дереве — столбец продолжает держать его строку, соседи
      // не уезжают, нажать нельзя.
      expect(find.text('привет'), findsOneWidget);
      expect(noteOpacity(tester), 0.0);
      expect(noteIgnoresTouches(tester), isTrue);
      expect(markerTop(tester), topWhileShown);
    });

    testWidgets('«убрать» выводит айтем из раскладки', (tester) async {
      final container = await render(tester);
      expect(markerTop(tester), greaterThan(0));

      setVisibility(container, 'gone');
      await tester.pumpAndSettle();

      expect(find.text('привет'), findsNothing);
      expect(markerTop(tester), 0);
    });

    testWidgets('показ возвращает айтем в прежнее состояние', (tester) async {
      final container = await render(tester);
      final topWhileShown = markerTop(tester);

      setVisibility(container, 'hidden');
      await tester.pumpAndSettle();
      setVisibility(container, 'visible');
      await tester.pumpAndSettle();

      expect(find.text('привет'), findsOneWidget);
      expect(noteOpacity(tester), 1.0);
      expect(noteIgnoresTouches(tester), isFalse);
      expect(markerTop(tester), topWhileShown);
    });

    testWidgets('сейв со старым true ведёт себя как «убрать»', (tester) async {
      final container = await render(tester);
      // Старые сейвы писали bool: true означало «нет айтема», false — «есть».
      setVisibility(container, true);
      await tester.pumpAndSettle();
      expect(find.text('привет'), findsNothing);
      expect(markerTop(tester), 0);

      setVisibility(container, false);
      await tester.pumpAndSettle();
      expect(find.text('привет'), findsOneWidget);
    });

    testWidgets('убранный с самого начала айтем не останавливает очередь', (
      tester,
    ) async {
      completions = 0;
      await render(tester, hiddenOverrides: {'note': 'gone'});

      expect(find.text('привет'), findsNothing);
      // Ребёнок не собирался, значит шаг очереди отдаёт сама обёртка — иначе
      // квест ждал бы продолжения от пустого места.
      expect(completions, 1);
    });

    testWidgets('скрытый с самого начала айтем отдаёт шаг один раз', (
      tester,
    ) async {
      completions = 0;
      await render(tester, hiddenOverrides: {'note': 'hidden'});

      expect(find.text('привет'), findsOneWidget);
      expect(noteOpacity(tester), 0.0);
      // Айтем собран, и шаг отдаёт ребёнок — обёртка не должна добавлять свой.
      expect(completions, 1);
    });

    testWidgets('смена скрытия на убор не шагает по очереди второй раз', (
      tester,
    ) async {
      completions = 0;
      final container = await render(tester);
      expect(completions, 1);

      setVisibility(container, 'hidden');
      await tester.pumpAndSettle();
      setVisibility(container, 'gone');
      await tester.pumpAndSettle();

      expect(find.text('привет'), findsNothing);
      expect(completions, 1);
    });
  });
}
