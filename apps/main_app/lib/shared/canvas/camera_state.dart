import 'dart:ui';

/// Неизменяемое состояние камеры бесконечного канваса.
///
/// Хранит offset (пан) и scale (зум), даёт методы конвертации
/// координат и вычисления видимой области.
class CameraState {
  final Offset offset;
  final double scale;

  const CameraState({
    this.offset = Offset.zero,
    this.scale = 1.0,
  });

  CameraState copyWith({Offset? offset, double? scale}) {
    return CameraState(
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
    );
  }

  // ── Конвертация координат ────────────────────────────────────────

  /// Экранная точка → мировые координаты.
  Offset screenToWorld(Offset screenPoint) {
    return (screenPoint - offset) / scale;
  }

  /// Мировые координаты → экранная точка.
  Offset worldToScreen(Offset worldPoint) {
    return worldPoint * scale + offset;
  }

  // ── Пан камеры ───────────────────────────────────────────────────

  /// Сдвинуть камеру на [delta] экранных пикселей.
  CameraState panBy(Offset delta) {
    return copyWith(offset: offset + delta);
  }

  // ── Зум камеры ───────────────────────────────────────────────────

  /// Зум в точке [focalPoint] (экранной).
  /// Точка под курсором остаётся на месте.
  CameraState zoomAt(double newScale, Offset focalPoint, {
    double minScale = 0.1,
    double maxScale = 5.0,
  }) {
    final clampedScale = newScale.clamp(minScale, maxScale);
    final scaleDelta = clampedScale / scale;
    final newOffset = focalPoint - (focalPoint - offset) * scaleDelta;
    return copyWith(scale: clampedScale, offset: newOffset);
  }

  /// Зум в центре экрана (для кнопок +/-).
  CameraState zoomAtCenter(double newScale, Size screenSize, {
    double minScale = 0.1,
    double maxScale = 5.0,
  }) {
    return zoomAt(newScale, screenSize.center(Offset.zero),
        minScale: minScale, maxScale: maxScale);
  }

  // ── Видимая область ──────────────────────────────────────────────

  /// Прямоугольник видимой области в мировых координатах.
  Rect visibleWorldRect(Size screenSize) {
    final topLeft = screenToWorld(Offset.zero);
    final bottomRight = screenToWorld(screenSize.bottomRight(Offset.zero));
    return Rect.fromPoints(topLeft, bottomRight);
  }

  /// Прямоугольник видимой области с запасом (inflate px).
  Rect visibleWorldRectInflated(Size screenSize, double inflate) {
    return visibleWorldRect(screenSize).inflate(inflate);
  }

  // ── Навигация ────────────────────────────────────────────────────

  /// Центрировать камеру на точке [worldPoint].
  CameraState centerOn(Offset worldPoint, Size screenSize) {
    final newOffset = -worldPoint * scale + screenSize.center(Offset.zero);
    return copyWith(offset: newOffset);
  }

  /// Сбросить камеру к начальному виду.
  CameraState reset() {
    return const CameraState();
  }

  /// Вписать rect [target] в screenSize с padding'ом.
  ///
  /// Масштаб берётся минимальный из двух осей (иначе rect вылез бы за край),
  /// и всегда в пределах зума мыши — иначе тонкий высокий rect просил бы
  /// clamp с lowerLimit > upperLimit.
  CameraState fitToRect(
    Rect target,
    Size screenSize, {
    double padding = 60,
    double minScale = 0.1,
    double maxScale = 5.0,
  }) {
    final availW = screenSize.width - padding * 2;
    final availH = screenSize.height - padding * 2;
    if (availW <= 0 || availH <= 0) return reset();
    if (target.width <= 0 || target.height <= 0) return this;

    final scaleX = availW / target.width;
    final scaleY = availH / target.height;
    final newScale = (scaleX < scaleY ? scaleX : scaleY).clamp(
      minScale,
      maxScale,
    );

    final newOffset = -target.center * newScale + screenSize.center(Offset.zero);
    return CameraState(offset: newOffset, scale: newScale);
  }
}
