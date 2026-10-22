import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_app/plugin_host/canvas/display_object.dart';
import 'package:flutter/material.dart';

class DisplayObjectPainter extends CustomPainter {
  final DisplayScene scene;

  DisplayObjectPainter(this.scene);

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.backgroundColor != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = scene.backgroundColor!,
      );
    }

    for (final obj in scene.objects) {
      if (!obj.isVisible) continue;
      _drawObject(canvas, obj);
    }
  }

  void _drawObject(Canvas canvas, DisplayObject obj) {
    canvas.save();
    canvas.translate(obj.x, obj.y);
    canvas.rotate(obj.rotation * 3.1415926535897932 / 180);
    canvas.scale(obj.scaleX, obj.scaleY);

    final paint = Paint()
      ..color = (obj.fillColor ?? Colors.white).withOpacity(obj.alpha)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = (obj.strokeColor ?? Colors.transparent).withOpacity(obj.alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = obj.strokeWidth;

    switch (obj.type) {
      case DisplayObjectType.rect:
        _drawRect(canvas, obj, paint, strokePaint);
        break;
      case DisplayObjectType.circle:
        _drawCircle(canvas, obj, paint, strokePaint);
        break;
      case DisplayObjectType.line:
        _drawLine(canvas, obj, strokePaint);
        break;
      case DisplayObjectType.polygon:
        _drawPolygon(canvas, obj, paint, strokePaint);
        break;
      case DisplayObjectType.text:
        _drawText(canvas, obj);
        break;
      case DisplayObjectType.image:
        _drawImage(canvas, obj);
        break;
      case DisplayObjectType.group:
        break;
      case DisplayObjectType.custom:
        _drawCustom(canvas, obj);
        break;
    }

    canvas.restore();
  }

  void _drawRect(Canvas canvas, DisplayObject obj, Paint paint, Paint strokePaint) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: obj.width,
      height: obj.height,
    );
    canvas.drawRect(rect, paint);
    if (obj.strokeWidth > 0) {
      canvas.drawRect(rect, strokePaint);
    }
  }

  void _drawCircle(Canvas canvas, DisplayObject obj, Paint paint, Paint strokePaint) {
    canvas.drawCircle(Offset.zero, obj.radius, paint);
    if (obj.strokeWidth > 0) {
      canvas.drawCircle(Offset.zero, obj.radius, strokePaint);
    }
  }

  void _drawLine(Canvas canvas, DisplayObject obj, Paint strokePaint) {
    if (obj.points.length < 2) return;
    for (int i = 0; i < obj.points.length - 1; i++) {
      canvas.drawLine(obj.points[i], obj.points[i + 1], strokePaint);
    }
  }

  void _drawPolygon(Canvas canvas, DisplayObject obj, Paint paint, Paint strokePaint) {
    if (obj.polygonPoints.length < 3) return;
    final path = Path()..moveTo(obj.polygonPoints[0].dx, obj.polygonPoints[0].dy);
    for (int i = 1; i < obj.polygonPoints.length; i++) {
      path.lineTo(obj.polygonPoints[i].dx, obj.polygonPoints[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
    if (obj.strokeWidth > 0) {
      canvas.drawPath(path, strokePaint);
    }
  }

  void _drawText(Canvas canvas, DisplayObject obj) {
    if (obj.text == null || obj.text!.isEmpty) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: obj.text,
        style: TextStyle(
          color: (obj.textColor ?? Colors.white).withOpacity(obj.alpha),
          fontSize: obj.fontSize,
          fontFamily: obj.fontFamily,
        ),
      ),
      textAlign: obj.textAlign,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final offset = switch (obj.textAlign) {
      TextAlign.left => Offset(-textPainter.width / 2, -textPainter.height / 2),
      TextAlign.center => Offset(-textPainter.width / 2, -textPainter.height / 2),
      TextAlign.right => Offset(-textPainter.width / 2, -textPainter.height / 2),
      _ => Offset(-textPainter.width / 2, -textPainter.height / 2),
    };

    textPainter.paint(canvas, offset);
  }

  void _drawImage(Canvas canvas, DisplayObject obj) {
    if (obj.imageDataBase64 != null) {
      final bytes = _decodeBase64(obj.imageDataBase64!);
      if (bytes != null) {
        ui.decodeImageFromPixels(
          bytes,
          obj.width.toInt(),
          obj.height.toInt(),
          ui.PixelFormat.rgba8888,
          (image) {
            final rect = Rect.fromCenter(
              center: Offset.zero,
              width: obj.width,
              height: obj.height,
            );
            canvas.drawImageRect(
              image,
              Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
              rect,
              Paint()..filterQuality = FilterQuality.medium,
            );
          },
        );
      }
    }
  }

  void _drawCustom(Canvas canvas, DisplayObject obj) {
    final customPaint = obj.userData['customPaint'] as void Function(Canvas, Size)?;
    if (customPaint != null) {
      customPaint(canvas, Size(obj.width, obj.height));
    }
  }

  Uint8List? _decodeBase64(String base64) {
    try {
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      final clean = base64.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      final bytes = <int>[];
      for (int i = 0; i < clean.length; i += 4) {
        int chunk = 0;
        int padding = 0;
        for (int j = 0; j < 4; j++) {
          final char = (i + j < clean.length) ? clean[i + j] : '=';
          if (char == '=') {
            padding++;
            continue;
          }
          chunk = (chunk << 6) | alphabet.indexOf(char);
        }
        bytes.add((chunk >> 16) & 0xFF);
        if (padding < 2) bytes.add((chunk >> 8) & 0xFF);
        if (padding < 1) bytes.add(chunk & 0xFF);
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  bool shouldRepaint(DisplayObjectPainter oldDelegate) => true;
}
