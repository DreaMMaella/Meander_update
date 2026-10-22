import 'dart:ui' show Size;

import 'package:canvas_app/features/editor/widgets/stack_help_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

/// Примеры рамок из справки стека: они обещают не трогать вёрстку слоёв и
/// поставить рамку ровно туда, где сказано.
void main() {
  const viewport = Size(400, 800);

  ContentItem stack() => ContentItem.fromJson({
    'type': 'stack',
    'id': 's1',
    'stackHeight': 220.0,
    'children': [
      {
        'type': 'text',
        'id': 'c1',
        'text': 'Привет',
        'pinAnchorLeft': 0.0,
        'pinOffsetLeft': 16.0,
        'pinAnchorTop': 0.0,
        'pinOffsetTop': 12.0,
      },
      {
        'type': 'image',
        'id': 'c2',
        'resourcePath': 'res/images/a.png',
        'pinAnchorLeft': 1.0,
        'pinOffsetLeft': -88.0,
        'pinAnchorTop': 1.0,
        'pinOffsetTop': -88.0,
      },
    ],
  });

  StackFrameExample byName(String name) =>
      StackHelpPanel.examples.firstWhere((e) => e.name == name);

  group('Примеры рамок', () {
    test('полоса внизу: вся ширина, нижний край, вёрстка слоёв цела', () {
      final base = stack();
      final next = byName('Плашка внизу экрана').apply(base, viewport);
      final rect = next.stackPinRect(viewport);

      expect(rect.width, closeTo(viewport.width, 0.01));
      expect(rect.bottom, closeTo(viewport.height, 0.01));
      // Схлопнутая по высоте ось keeps холст: высота следует за масштабом.
      expect(
        rect.height,
        closeTo(
          base.stackCanvasHeight * viewport.width / base.stackCanvasWidth,
          0.01,
        ),
      );
      expect(next.stackPinStretchesWidth, isTrue);
      expect(next.stackPinStretchesHeight, isFalse);
      expect(
        next.children!.map((c) => c.toJson()).toList(),
        base.children!.map((c) => c.toJson()).toList(),
      );
    });

    test('шапка-шторка: прижата к верхнему краю', () {
      final next = byName('Шапка-шторка сверху').apply(stack(), viewport);
      final rect = next.stackPinRect(viewport);

      expect(rect.top, closeTo(0, 0.01));
      expect(rect.width, closeTo(viewport.width, 0.01));
    });

    test('окно по центру: центрировано и стало модалкой', () {
      final next = byName('Окно по центру').apply(stack(), viewport);
      final rect = next.stackPinRect(viewport);

      expect(rect.center, const Offset(200, 400));
      expect(next.isModalStack, isTrue);
      expect(next.stackDismissesOnTapOutside, isTrue);
    });

    test('угол: схлопнутая рамка у правого нижнего края', () {
      final next = byName('Слой в правом нижнем углу').apply(stack(), viewport);
      final rect = next.stackPinRect(viewport);

      expect(rect.right, closeTo(viewport.width, 0.01));
      expect(rect.bottom, closeTo(viewport.height, 0.01));
      expect(next.isModalStack, isFalse);
    });
  });

  group('Правила', () {
    // #196: «Рамка» и «Центр» выглядят двумя названиями одного и того же,
    // хотя пресет позиции перезаписывает рамку, а «Рамка» — нет.
    test('справка объясняет, чем «Рамка» отличается от готовых позиций', () {
      final pinRule = StackHelpPanel.rules.firstWhere(
        (r) => r.contains('Рамка') && r.contains('Центр'),
      );

      expect(pinRule, contains('сбрасывает'));
      expect(pinRule, contains('320×200'));
    });
  });
}
