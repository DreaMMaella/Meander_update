import 'package:canvas_app/plugin_host/canvas/display_object.dart';
import 'package:canvas_app/plugin_host/canvas/display_renderer.dart';
import 'package:canvas_app/plugin_host/canvas/main_thread_canvas_engine.dart';
import 'package:flutter/material.dart';

class CanvasOverlay {
  OverlayEntry? _entry;
  MainThreadCanvasEngine? _engine;
  DisplayScene? _scene;

  void show({
    required BuildContext context,
    required String scriptText,
    required String pluginId,
    required String contentId,
    Color? backgroundColor,
    VoidCallback? onClose,
  }) {
    hide();

    _scene = DisplayScene(
      id: 'overlay_${contentId}',
      pluginId: pluginId,
    )..width = MediaQuery.of(context).size.width
      ..height = MediaQuery.of(context).size.height
      ..backgroundColor = backgroundColor ?? const Color(0xFF1A1A2E);

    _engine = MainThreadCanvasEngine(
      scene: _scene!,
      log: (msg) => debugPrint('[CanvasOverlay] $msg'),
      onMarkNeedsBuild: () {
        _entry?.markNeedsBuild();
      },
    );

    _engine!.init();
    _engine!.onClose = onClose;
    _engine!.executeScript(scriptText);

    _entry = OverlayEntry(
      builder: (context) => _CanvasOverlayWidget(
        engine: _engine!,
        scene: _scene!,
        onClose: () => hide(),
      ),
    );

    Overlay.of(context).insert(_entry!);
  }

  void hide() {
    _entry?.remove();
    _entry = null;
    _engine?.dispose();
    _engine = null;
    _scene = null;
  }
}

class _CanvasOverlayWidget extends StatefulWidget {
  final MainThreadCanvasEngine engine;
  final DisplayScene scene;
  final VoidCallback onClose;

  const _CanvasOverlayWidget({
    required this.engine,
    required this.scene,
    required this.onClose,
  });

  @override
  State<_CanvasOverlayWidget> createState() => _CanvasOverlayWidgetState();
}

class _CanvasOverlayWidgetState extends State<_CanvasOverlayWidget> {
  void _handleTap(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    widget.engine.handleTap(local.dx, local.dy);
  }

  void _handlePanStart(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    widget.engine.handleTouchStart(local.dx, local.dy);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    widget.engine.handleTouchMove(local.dx, local.dy, details.delta.dx, details.delta.dy);
  }

  void _handlePanEnd(DragEndDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    widget.engine.handleTouchEnd(local.dx, local.dy);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTapDown: _handleTap,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: Stack(
          children: [
            CustomPaint(
              painter: DisplayObjectPainter(widget.scene),
              size: Size(widget.scene.width, widget.scene.height),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
