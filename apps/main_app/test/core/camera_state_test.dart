// Камера канваса: конвертации координат и вписывание rect'а в вьюпорт.
// Тест нужен прежде всего для fitToRect — там когда-то был clamp с
// lowerLimit > upperLimit, что на высоком узком rect падало с AssertionError.

import 'dart:ui';

import 'package:canvas_app/shared/canvas/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewport = Size(800, 600);

  group('CameraState.fitToRect', () {
    test('центр rect’а приезжает в центр вьюпорта', () {
      final camera = const CameraState().fitToRect(
        const Rect.fromLTWH(100, 100, 200, 100),
        viewport,
      );
      expect(
        camera.worldToScreen(const Offset(200, 150)),
        viewport.center(Offset.zero),
      );
    });

    test('масштаб берётся по узкой оси, rect целиком влезает в вид', () {
      final camera = const CameraState().fitToRect(
        const Rect.fromLTWH(0, 0, 4000, 40),
        viewport,
      );
      final fitted = Rect.fromPoints(
        camera.worldToScreen(const Offset(0, 0)),
        camera.worldToScreen(const Offset(4000, 40)),
      );
      expect(fitted.width, closeTo(viewport.width - 120, 0.01));
      expect(fitted.height, lessThan(viewport.height));
    });

    test(
      'высокий узкий rect не роняет расчёт и не выходит за потолок зума',
      () {
        final camera = const CameraState().fitToRect(
          const Rect.fromLTWH(0, 0, 20, 4000),
          viewport,
        );
        expect(camera.scale, greaterThan(0));
        expect(camera.scale, lessThanOrEqualTo(5));
        expect(camera.scale.isFinite, isTrue);
      },
    );

    test('нулевой rect оставляет камеру как была', () {
      const camera = CameraState(offset: Offset(12, 8), scale: 2);
      expect(
        camera.fitToRect(const Rect.fromLTWH(5, 5, 0, 0), viewport),
        same(camera),
      );
    });

    test('слишком узкий вьюпорт сбрасывает камеру', () {
      final camera = const CameraState(
        offset: Offset(9, 9),
      ).fitToRect(const Rect.fromLTWH(0, 0, 100, 100), const Size(100, 80));
      expect(camera.scale, 1);
      expect(camera.offset, Offset.zero);
    });
  });
}
