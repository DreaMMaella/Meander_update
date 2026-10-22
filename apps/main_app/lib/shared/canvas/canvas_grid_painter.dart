import 'dart:ui';

import 'package:flutter/material.dart';

/// Адаптивная сетка для бесконечного канваса.
///
/// При малом масштабе (zoom out) сетка автоматически переключается
/// на более крупный шаг (LOD), чтобы избежать визуального шума.
class CanvasGridPainter {
  /// Рисует адаптивную сетку на [canvas].
  ///
  /// [offset] — пан камеры (экранные координаты начала мира).
  /// [scale] — текущий масштаб.
  /// [screenSize] — размер экрана.
  /// [color] — цвет линий сетки.
  static void paint(
    Canvas canvas, {
    required Offset offset,
    required double scale,
    required Size screenSize,
    required Color color,
  }) {
    const baseGridSize = 50.0;
    int lodLevel = 1;
    double currentGridSize = baseGridSize * scale;

    // LOD: пока сетка слишком мелкая, увеличиваем шаг.
    while (currentGridSize < 20 && lodLevel < 100) {
      lodLevel *= 5;
      currentGridSize = baseGridSize * lodLevel * scale;
    }

    if (currentGridSize < 5) return;

    final gridPaint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final offsetX = offset.dx % currentGridSize;
    final offsetY = offset.dy % currentGridSize;

    for (double x = offsetX; x < screenSize.width; x += currentGridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, screenSize.height), gridPaint);
    }
    for (double y = offsetY; y < screenSize.height; y += currentGridSize) {
      canvas.drawLine(Offset(0, y), Offset(screenSize.width, y), gridPaint);
    }
  }
}
