// Регрессия «если создать вот такой стек, он начнёт вечно расширяться».
//
// Документ — реальный стек из квеста владельца: type stack, stackPin custom,
// якоря 0..1 по обеим осям (обе оси растянуты), три картинки-слоя, холст
// 720×220. В плеере рост воспроизвестись не должен: закреплённый слой берёт
// размер из рамки экрана, а холст-в-потоке — из авторских px дизайна.
//
// Проверяются три уровня, где рост вообще мог бы родиться:
//   1) модель (`stackPinRect`, `stackPinWithRect`/`stackPinWithAnchors`);
//   2) layout плеера с той же обвязкой, что в `game_screen._buildPinnedStacks`;
//   3) запись рамки по кругу — путь, которым шит «Стек · холст и фон» пишет
//      документ (там же ловится потеря авторского размера холста).

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

Object? get _skipIfNoSo => _soPath == null
    ? 'libmnd_ffi.so не найден: cargo build --release -p mnd-ffi (или MND_FFI_SO)'
    : false;

final Map<String, Object?> _stackJson = {
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
    _childJson('c1', 163.26, 208.94),
    _childJson('c2', 208.94, 254.63),
    _childJson('c3', 254.63, 300.31),
  ],
};

Map<String, Object?> _childJson(String id, double left, double right) => {
  'type': 'image',
  'id': id,
  'resourcePath': 'res/images/18f5630e-4052-43d0-829b-2be328219a4a.png',
  'flex': 1,
  'anchorLeft': 0.0,
  'anchorTop': 0.0,
  'anchorRight': 0.0,
  'anchorBottom': 0.0,
  'offsetLeft': left,
  'offsetRight': right,
  'offsetTop': 88.0,
  'offsetBottom': 132.0,
};

/// Вьюпорт как в окне владельца: шит при такой рамке показывает «В 761».
const Size _viewport = Size(720, 761);

ContentItem buildStack() =>
    ContentItem.fromJson(Map<String, dynamic>.from(_stackJson));

void main() {
  group('модель закреплённого стека', () {
    test('рамка растянутой панели = экран, холст остаётся авторским', () {
      final s = buildStack();
      expect(s.stackPinStretchesWidth, isTrue);
      expect(s.stackPinStretchesHeight, isTrue);
      expect(s.stackCanvasWidth, 720);
      expect(s.stackCanvasHeight, 220);
      expect(s.stackPinRect(_viewport), const Rect.fromLTRB(0, 0, 720, 761));
      // Слои считаются от холста дизайна, а не от рамки экрана.
      expect(
        s.children![0].stackChildRect(s.stackCanvasWidth, s.stackCanvasHeight),
        const Rect.fromLTRB(163.26, 88, 208.94, 132),
      );
    });

    test('запись рамки по кругу не двигает рамку и не съедает холст', () {
      var s = buildStack();
      for (var i = 0; i < 12; i++) {
        s = s.stackPinWithRect(s.stackPinRect(_viewport), _viewport);
        expect(
          s.stackPinRect(_viewport),
          const Rect.fromLTRB(0, 0, 720, 761),
          reason: 'итерация $i: рамка поехала сама от себя',
        );
        // Растянутая ось не имеет своего размера в документе — но и терять
        // авторский холст она не вправе: copyWith(null) означает «не трогаем».
        expect(s.stackHeight, 220, reason: 'итерация $i: холст съеден');
        expect(s.stackWidth, isNull);
        expect(s.pinOffsetLeft, 0, reason: 'итерация $i: отступы уползли');
      }
    });

    test('сетка позиции по кругу тоже идемпотентна', () {
      var a = buildStack();
      for (var i = 0; i < 12; i++) {
        a = a.stackPinWithAnchors(a.stackPinAnchors, _viewport);
        expect(
          a.stackPinRect(_viewport),
          const Rect.fromLTRB(0, 0, 720, 761),
          reason: 'итерация $i',
        );
        expect(a.stackCanvasHeight, 220);
      }
    });
  });

  /// Ровно та же обвязка, что в `game_screen._buildPinnedStacks`.
  Widget pinnedTree(ContentItem item, Size window) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: window.width,
          height: window.height,
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

  Future<void> pumpWindow(WidgetTester tester, Size window) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Равный масштаб по осям — то, ради чего холст в закреплённой панели
  /// добирается делением на масштаб: рамка задаёт ребёнку жёсткие ограничения,
  /// поэтому по размеру `GameStackWidget` подмену масштаба не увидеть, а по
  /// размерам внутреннего холста (px дизайна) — видно.
  void expectUniformScale(WidgetTester tester, {required double designWidth}) {
    final outer = tester.getSize(find.byType(GameStackWidget));
    final canvas = tester.getSize(
      find
          .descendant(
            of: find.byType(GameStackWidget),
            matching: find.byType(Stack),
          )
          .first,
    );
    final scale = outer.width / designWidth;
    expect(canvas.width * scale, closeTo(outer.width, 1), reason: 'ось X');
    expect(canvas.height * scale, closeTo(outer.height, 1), reason: 'ось Y');
  }

  testWidgets('плеер: закреплённый стек 720×761 стабилен по кадрам', (
    tester,
  ) async {
    await pumpWindow(tester, _viewport);
    final item = buildStack();
    await tester.pumpWidget(pinnedTree(item, _viewport));
    Size? first;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final size = tester.getSize(find.byType(GameStackWidget));
      first ??= size;
      expect(
        size,
        first,
        reason: 'кадр $i: холст вырос сам — было $first, стало $size',
      );
    }
    expect(first, const Size(720, 761));
    expectUniformScale(tester, designWidth: 720);
    // Пересборка дерева с той же моделью (то, что делает ре-ривил).
    for (var i = 0; i < 4; i++) {
      await tester.pumpWidget(pinnedTree(item, _viewport));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getSize(find.byType(GameStackWidget)),
        const Size(720, 761),
      );
      expect(find.byType(PinnedStackLayer), findsOneWidget);
    }
  });

  testWidgets(
    'плеер: узкий телефон 360×761 — тот же документ, тот же порядок',
    (tester) async {
      const window = Size(360, 761);
      await pumpWindow(tester, window);
      await tester.pumpWidget(pinnedTree(buildStack(), window));
      Size? first;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final size = tester.getSize(find.byType(GameStackWidget));
        first ??= size;
        expect(size, first, reason: 'кадр $i: $size vs $first');
      }
      expect(first, const Size(360, 761));
      expectUniformScale(tester, designWidth: 720);
    },
  );

  testWidgets('поток ноды: тот же стек в прокрутке остаётся 720×220', (
    tester,
  ) async {
    await pumpWindow(tester, _viewport);
    final item = buildStack();
    Widget tree() => ProviderScope(
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
    await tester.pumpWidget(tree());
    Size? first;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final size = tester.getSize(find.byType(GameStackWidget));
      first ??= size;
      expect(size, first, reason: 'кадр $i: холст в потоке вырос — $size');
    }
    expect(first, const Size(720, 220));
    expectUniformScale(tester, designWidth: 720);
  });

  test('движок: очередь раскрытия выдаёт закреплённый стек один раз', () async {
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
    final revealed = <String?>[];
    for (var i = 0; i < 10; i++) {
      final step = await engine.nextItem();
      if (step.isItem) revealed.add(step.item?['id'] as String?);
    }
    // Переиздания того же айтема быть не должно: второй «item» удвоил бы
    // закреплённый слой.
    expect(
      revealed.where((id) => id == _stackJson['id']).length,
      1,
      reason: '$revealed',
    );
    engine.dispose();
  }, skip: _skipIfNoSo);
}
