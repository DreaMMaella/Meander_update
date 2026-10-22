// Воспроизведение бага владельца: «если создать вот такой стек, он начнёт
// вечно расширяться».
//
// Документ — реальный стек из квеста (type stack, stackPin custom, якоря
// 0..1 по обеим осям, три картинки-слоя). Тест делает три вещи:
//   1) печатает геометрию, которую выводит модель (рамка + холст);
//   2) гоняет реальный layout ровно так, как это делает `game_screen`
//      (`Positioned.fill → SafeArea → LayoutBuilder → PinnedStackLayer`),
//      несколько кадров подряд и смотрит, растёт ли высота;
//   3) прогоняет редакторную запись рамки (`stackPinWithRect` /
//      `stackPinWithAnchors`) по кругу — это тот путь, которым шит «Стек ·
//      холст и фон» пишет документ.
//
// Ничего не чиним: задача — зафиксировать цифрами, где именно появляется рост.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/widgets/items/game_stack_widget.dart';
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

const Map<String, Object?> _stackJson = {
  'type': 'stack',
  'id': '9de15891-db1f-4d94-bfb1-f088395c556b',
  'borderRadius': 0.0,
  'stackHeight': 220.0,
  'stackPin': 'custom',
  'pinAnchorLeft': 0.0,
  'pinAnchorTop': 0.0,
  'pinAnchorRight': 1.0,
  'pinAnchorBottom': 1.0,
  'pinOffsetLeft': 0.0,
  'pinOffsetTop': 0.0,
  'pinOffsetRight': 0.0,
  'pinOffsetBottom': 0.0,
  'flex': 1,
  'crossAxisAlignment': 'center',
  'rowTextAlignment': 'center',
  'textFit': 'auto',
  'wrapText': true,
  'animateIn': true,
  'children': [
    {
      'type': 'image',
      'id': 'c1',
      'resourcePath': 'res/images/18f5630e-4052-43d0-829b-2be328219a4a.png',
      'flex': 1,
      'anchorLeft': 0.0,
      'anchorTop': 0.0,
      'anchorRight': 0.0,
      'anchorBottom': 0.0,
      'offsetLeft': 163.26,
      'offsetRight': 208.94,
      'offsetTop': 88.0,
      'offsetBottom': 132.0,
    },
    {
      'type': 'image',
      'id': 'c2',
      'resourcePath': 'res/images/18f5630e-4052-43d0-829b-2be328219a4a.png',
      'flex': 1,
      'anchorLeft': 0.0,
      'anchorTop': 0.0,
      'anchorRight': 0.0,
      'anchorBottom': 0.0,
      'offsetLeft': 208.94,
      'offsetRight': 254.63,
      'offsetTop': 88.0,
      'offsetBottom': 132.0,
    },
    {
      'type': 'image',
      'id': 'c3',
      'resourcePath': 'res/images/18f5630e-4052-43d0-829b-2be328219a4a.png',
      'flex': 1,
      'anchorLeft': 0.0,
      'anchorTop': 0.0,
      'anchorRight': 0.0,
      'anchorBottom': 0.0,
      'offsetLeft': 254.63,
      'offsetRight': 300.31,
      'offsetTop': 88.0,
      'offsetBottom': 132.0,
    },
  ],
};

/// Вьюпорт как в шите владельца: рамка показывает 720×761.
const Size _viewport = Size(720, 761);

ContentItem buildStack() => ContentItem.fromJson(
  Map<String, dynamic>.from(_stackJson),
);

void main() {
  test('модель: что рамка и холст выводят из этого документа', () {
    final s = buildStack();
    // ignore: avoid_print
    print(
      'stackWidth=${s.stackWidth} stackHeight=${s.stackHeight} '
      'canvas=${s.stackCanvasWidth}×${s.stackCanvasHeight} '
      'stretchW=${s.stackPinStretchesWidth} '
      'stretchH=${s.stackPinStretchesHeight}',
    );
    // ignore: avoid_print
    print('pinRect=${s.stackPinRect(_viewport)}');
    for (final c in s.children ?? const <ContentItem>[]) {
      // ignore: avoid_print
      print('child ${c.id} rect=${c.stackChildRect(
        s.stackCanvasWidth,
        s.stackCanvasHeight,
      )}');
    }
  });

  /// Ровно та же обвязка, что в `game_screen._buildPinnedStacks`.
  Widget pinnedTree(ContentItem item) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: _viewport.width,
              height: _viewport.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final vw = constraints.maxWidth;
                          final vh = constraints.maxHeight;
                          const columnCap = 720.0;
                          final columnWidth = vw < columnCap ? vw : columnCap;
                          final viewport = Size(columnWidth, vh);
                          final dx = (vw - columnWidth) / 2;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              PinnedStackLayer(
                                key: const ValueKey('pinned'),
                                item: item,
                                viewport: viewport,
                                offset: Offset(dx, 0),
                                child: GameStackWidget(
                                  item: item,
                                  questId: 'q1',
                                  onInteract: (_) {},
                                  onInputSubmitted: (_, __) {},
                                  onComplete: () {},
                                  onTransition: (_) {},
                                  onNavigateToNode: (_) {},
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// Как рисует поток ноды: стек лежит в прокрутке (`Column` в
  /// `SingleChildScrollView`), рамка закрепления при этом та же.
  Widget flowTree(ContentItem item) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: _viewport.width,
          height: _viewport.height,
          child: SingleChildScrollView(
            child: Column(
              children: [
                GameStackWidget(
                  item: item,
                  questId: 'q1',
                  onInteract: (_) {},
                  onInputSubmitted: (_, __) {},
                  onComplete: () {},
                  onTransition: (_) {},
                  onNavigateToNode: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void dump(WidgetTester tester, String tag) {
    final size = tester.getSize(find.byType(GameStackWidget));
    final layers = find.byType(PinnedStackLayer).evaluate().length;
    // ignore: avoid_print
    print(
      '$tag: canvas=${size.width.toStringAsFixed(2)}×'
      '${size.height.toStringAsFixed(2)} layers=$layers '
      'exceptions=${tester.takeException()}',
    );
  }

  testWidgets('плеер: закреплённый стек на 720×761 — рост по кадрам', (
    tester,
  ) async {
    // Тестовое окно по умолчанию 800×600 и резало наш вьюпорт до 600 —
    // выставляем ровно те 720×761, что показывает шит владельца.
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final item = buildStack();
    await tester.pumpWidget(pinnedTree(item));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      dump(tester, 'pinned frame $i');
    }
    // Пересборка с той же моделью (то, что делает ре-ривил / смена состояния).
    for (var i = 0; i < 4; i++) {
      await tester.pumpWidget(pinnedTree(item));
      await tester.pump(const Duration(milliseconds: 100));
      dump(tester, 'pinned rebuild $i');
    }
  });

  testWidgets('плеер: узкий телефон 360×761 — тот же документ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 761);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final item = buildStack();
    await tester.pumpWidget(pinnedTree(item));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      dump(tester, 'phone frame $i');
    }
  });

  testWidgets('поток ноды: тот же стек в прокрутке — рост по кадрам', (
    tester,
  ) async {
    final item = buildStack();
    await tester.pumpWidget(flowTree(item));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      // ignore: avoid_print
      print(
        'flow frame $i: '
        '${tester.getSize(find.byType(GameStackWidget)).toString()}',
      );
    }
    for (var i = 0; i < 4; i++) {
      await tester.pumpWidget(flowTree(item));
      await tester.pump(const Duration(milliseconds: 100));
      // ignore: avoid_print
      print(
        'flow rebuild $i: '
        '${tester.getSize(find.byType(GameStackWidget)).toString()}',
      );
    }
  });

  test('редактор: запись рамки по кругу (то, что делает шит)', () {
    var s = buildStack();
    for (var i = 0; i < 12; i++) {
      final rect = s.stackPinRect(_viewport);
      s = s.stackPinWithRect(rect, _viewport);
      // ignore: avoid_print
      print(
        'iter $i: stackWidth=${s.stackWidth} stackHeight=${s.stackHeight} '
        'off=${s.pinOffsetLeft}/${s.pinOffsetTop}/'
        '${s.pinOffsetRight}/${s.pinOffsetBottom} '
        'rect=${s.stackPinRect(_viewport)}',
      );
    }
    var a = buildStack();
    for (var i = 0; i < 12; i++) {
      a = a.stackPinWithAnchors(a.stackPinAnchors, _viewport);
      // ignore: avoid_print
      print(
        'anchors iter $i: stackWidth=${a.stackWidth} '
        'stackHeight=${a.stackHeight} rect=${a.stackPinRect(_viewport)}',
      );
    }
  });

  test('движок: очередь раскрытия не переиздаёт закреплённый стек', () async {
    if (skipIfNoSo != false) return;
    await initRustCore(externalLibrary: ExternalLibrary.open(_soPath!));
    final engine = await MeanderGameEngine.create(
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
              'items': [_stackJson],
            },
          },
        ],
      },
      platformOs: 'linux',
    );
    await engine.loadNode('n1');
    for (var i = 0; i < 10; i++) {
      final step = await engine.nextItem();
      // ignore: avoid_print
      print(
        'reveal $i: kind=${step.kind} id=${step.item?['id'] ?? '-'}',
      );
    }
    engine.dispose();
  });
}
