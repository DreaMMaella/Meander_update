import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:canvas_app/shared/canvas/canvas_grid_painter.dart';
import 'package:canvas_app/shared/canvas/canvas_item.dart';
import 'package:canvas_app/shared/canvas/camera_state.dart';

// ================================================================
// Бесконечный канвас — переиспользуемый виджет.
//
// Управляет камерой (pan/zoom), рисует сетку, предоставляет
// SpatialHash для hit-testing. Содержимое ( элементы) рендерит
// через [itemBuilder] — вызывающий код решает как.
//
// Тип [T] — любой подкласс [CanvasItem] (Node, ContentItem и т.д.).
// ================================================================

/// Тип функции для построения виджета элемента на канвасе.
typedef CanvasItemBuilder<T extends CanvasItem> = Widget Function(
  BuildContext context,
  T item,
  bool isSelected,
  bool isHovered,
);

/// Тип функции для отрисовки дополнительного контента поверх элементов
/// (связи, группы, оверлеи) — через CustomPainter.
typedef CanvasOverlayPainter = CustomPainter Function(
  CameraState camera,
  Set<String> selectedIds,
  String? hoveredId,
);

/// Неизменяемый параметр для InfiniteCanvas.
class InfiniteCanvasConfig<T extends CanvasItem> {
  /// Элементы на канвасе.
  final List<T> items;

  /// ID выбранных элементов.
  final Set<String> selectedIds;

  /// ID наведённого элемента.
  final String? hoveredId;

  /// Текущее состояние камеры.
  final CameraState camera;

  /// Показывать ли сетку.
  final bool showGrid;

  /// Цвет сетки.
  final Color gridColor;

  /// Цвет фона канваса.
  final Color backgroundColor;

  /// Построитель виджета для элемента.
  final CanvasItemBuilder<T> itemBuilder;

  /// Дополнительный painter поверх элементов (связи, группы и т.д.).
  final CanvasOverlayPainter? overlayPainter;

  /// Минимальный масштаб камеры.
  final double minScale;

  /// Максимальный масштаб камеры.
  final double maxScale;

  const InfiniteCanvasConfig({
    required this.items,
    required this.itemBuilder,
    this.selectedIds = const {},
    this.hoveredId,
    this.camera = const CameraState(),
    this.showGrid = true,
    this.gridColor = const Color(0xFF2F2F2F),
    this.backgroundColor = const Color(0xFF1A1A1A),
    this.overlayPainter,
    this.minScale = 0.1,
    this.maxScale = 5.0,
  });
}

/// Бесконечный канвас.
///
/// Использование:
/// ```dart
/// InfiniteCanvas<CanvasItem>(
///   config: InfiniteCanvasConfig(
///     items: myItems,
///     camera: camera,
///     itemBuilder: (ctx, item, selected, hovered) => MyItemWidget(item),
///   ),
///   onCameraChanged: (cam) => setState(() => camera = cam),
///   onItemTapped: (item) => selectItem(item.id),
///   onDoubleTapped: (item) => openEditor(item),
/// )
/// ```
class InfiniteCanvas<T extends CanvasItem> extends StatefulWidget {
  final InfiniteCanvasConfig<T> config;

  /// Вызывается при изменении камеры (pan/zoom).
  final ValueChanged<CameraState> onCameraChanged;

  /// Вызывается при тапе по элементу (или null для фона).
  final ValueChanged<T?>? onItemTapped;

  /// Вызывается при двойном тапе по элементу.
  final ValueChanged<T?>? onItemDoubleTapped;

  /// Вызывается при long-press по элементу.
  final ValueChanged<T?>? onItemLongPressed;

  /// Вызывается при начале drag элемента.
  final void Function(T item, Offset worldDelta)? onItemDragStart;

  /// Вызывается при обновлении drag элемента.
  final void Function(T item, Offset worldDelta)? onItemDragUpdate;

  /// Вызывается при завершении drag элемента.
  final void Function(T item)? onItemDragEnd;

  /// Вызывается при наведении на элемент (или null для фона).
  final ValueChanged<T?>? onHoverChanged;

  const InfiniteCanvas({
    super.key,
    required this.config,
    required this.onCameraChanged,
    this.onItemTapped,
    this.onItemDoubleTapped,
    this.onItemLongPressed,
    this.onItemDragStart,
    this.onItemDragUpdate,
    this.onItemDragEnd,
    this.onHoverChanged,
  });

  @override
  State<InfiniteCanvas<T>> createState() => _InfiniteCanvasState<T>();
}

class _InfiniteCanvasState<T extends CanvasItem> extends State<InfiniteCanvas<T>> {
  // ── Гесты ────────────────────────────────────────────────────────
  Offset? _lastFocalPoint;
  double _baseScale = 1.0;

  // ── Drag элемента ────────────────────────────────────────────────
  T? _draggedItem;
  Offset? _dragStartWorld;
  bool _backgroundTapped = false;

  // ── SpatialHash ──────────────────────────────────────────────────
  late CanvasSpatialHash<T> _spatialHash;

  // ── Hover ────────────────────────────────────────────────────────
  T? _hoveredItem;

  @override
  void didUpdateWidget(InfiniteCanvas<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.items != widget.config.items) {
      _spatialHash.rebuild(widget.config.items);
    }
  }

  @override
  void initState() {
    super.initState();
    _spatialHash = CanvasSpatialHash<T>();
    _spatialHash.rebuild(widget.config.items);
  }

  CameraState get _camera => widget.config.camera;

  T? _itemAtPoint(Offset screenPoint) {
    final worldPos = _camera.screenToWorld(screenPoint);
    return _spatialHash.queryPoint(worldPos);
  }

  void _updateHover(Offset screenPoint) {
    final item = _itemAtPoint(screenPoint);
    if (item?.id != _hoveredItem?.id) {
      _hoveredItem = item;
      widget.onHoverChanged?.call(item);
    }
  }

  // ── Гесты ────────────────────────────────────────────────────────

  void _onTapDown(TapDownDetails details) {
    // Сброс hover при тапе на фон.
  }

  void _onTapUp(TapUpDetails details) {
    if (_draggedItem != null || !_backgroundTapped) {
      _backgroundTapped = false;
      return;
    }
    final item = _itemAtPoint(details.localPosition);
    widget.onItemTapped?.call(item);
    _backgroundTapped = false;
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final item = _itemAtPoint(details.localPosition);
    widget.onItemDoubleTapped?.call(item);
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount == 1) {
      final item = _itemAtPoint(details.localFocalPoint);
      if (item != null) {
        _draggedItem = item;
        _dragStartWorld = _camera.screenToWorld(details.localFocalPoint);
        _backgroundTapped = false;
        return;
      }
      _backgroundTapped = true;
    }
    _baseScale = _camera.scale;
    _lastFocalPoint = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // ── Drag элемента ──
    if (_draggedItem != null && details.pointerCount == 1) {
      final worldPos = _camera.screenToWorld(details.localFocalPoint);
      final delta = worldPos - _dragStartWorld!;
      _dragStartWorld = worldPos;
      widget.onItemDragUpdate?.call(_draggedItem!, delta);
      return;
    }

    // ── Много пальцев / зум ──
    if (details.pointerCount > 1) {
      final newScale = _baseScale * details.scale;
      widget.onCameraChanged.call(
        _camera.zoomAt(newScale, details.focalPoint,
            minScale: widget.config.minScale,
            maxScale: widget.config.maxScale),
      );
    } else {
      // ── Пан одной рукой ──
      final delta = details.focalPoint - _lastFocalPoint!;
      widget.onCameraChanged.call(_camera.panBy(delta));
    }
    _lastFocalPoint = details.focalPoint;

    // ── Hover ──
    _updateHover(details.localFocalPoint);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_draggedItem != null) {
      widget.onItemDragEnd?.call(_draggedItem!);
      _draggedItem = null;
      _dragStartWorld = null;
    }
    _lastFocalPoint = null;
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final speed = 0.05;
          final newScale = event.scrollDelta.dy < 0
              ? _camera.scale * (1 + speed)
              : _camera.scale / (1 + speed);
          widget.onCameraChanged.call(
            _camera.zoomAt(newScale, event.localPosition,
                minScale: config.minScale, maxScale: config.maxScale),
          );
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onDoubleTapDown: _onDoubleTapDown,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onLongPressStart: (details) {
          final item = _itemAtPoint(details.localPosition);
          widget.onItemLongPressed?.call(item);
        },
        child: Stack(
          children: [
            // 1. Фон + сетка (CustomPaint)
            RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _CanvasBackgroundPainter(
                  camera: config.camera,
                  showGrid: config.showGrid,
                  gridColor: config.gridColor,
                  backgroundColor: config.backgroundColor,
                ),
              ),
            ),

            // 2. Мир: трансформированный контейнер для элементов
            Positioned.fill(
              child: Transform(
                transform: Matrix4.identity()
                  ..translate(config.camera.offset.dx, config.camera.offset.dy)
                  ..scale(config.camera.scale),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Оверлей-парсер (связи, группы и т.д.)
                    if (config.overlayPainter != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: config.overlayPainter!(
                              config.camera,
                              config.selectedIds,
                              config.hoveredId,
                            ),
                          ),
                        ),
                      ),

                    // Элементы
                    for (final item in config.items)
                      Positioned(
                        left: item.position.dx - item.size.width / 2,
                        top: item.position.dy - item.size.height / 2,
                        width: item.size.width,
                        height: item.size.height,
                        child: config.itemBuilder(
                          context,
                          item,
                          config.selectedIds.contains(item.id),
                          item.id == _hoveredItem?.id,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Background painter ─────────────────────────────────────────────

class _CanvasBackgroundPainter extends CustomPainter {
  final CameraState camera;
  final bool showGrid;
  final Color gridColor;
  final Color backgroundColor;

  _CanvasBackgroundPainter({
    required this.camera,
    required this.showGrid,
    required this.gridColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Фон
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // Сетка
    if (showGrid) {
      CanvasGridPainter.paint(
        canvas,
        offset: camera.offset,
        scale: camera.scale,
        screenSize: size,
        color: gridColor,
      );
    }
  }

  @override
  bool shouldRepaint(_CanvasBackgroundPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
