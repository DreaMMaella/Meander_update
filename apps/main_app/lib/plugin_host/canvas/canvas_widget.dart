import 'package:canvas_app/plugin_host/canvas/display_object.dart';
import 'package:canvas_app/plugin_host/canvas/display_renderer.dart';
import 'package:canvas_app/plugin_host/canvas/main_thread_canvas_engine.dart';
import 'package:flutter/material.dart';

class CanvasWidget extends StatefulWidget {
  final String scriptText;
  final String pluginId;
  final String contentId;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final VoidCallback? onClose;

  const CanvasWidget({
    super.key,
    required this.scriptText,
    required this.pluginId,
    required this.contentId,
    this.width,
    this.height,
    this.backgroundColor,
    this.onClose,
  });

  @override
  State<CanvasWidget> createState() => _CanvasWidgetState();
}

class _CanvasWidgetState extends State<CanvasWidget> {
  late MainThreadCanvasEngine _engine;
  late DisplayScene _scene;

  @override
  void initState() {
    super.initState();
    _scene = DisplayScene(
      id: 'canvas_${widget.contentId}',
      pluginId: widget.pluginId,
    )..width = widget.width ?? 800
      ..height = widget.height ?? 400
      ..backgroundColor = widget.backgroundColor ?? const Color(0xFF1A1A2E);

    _engine = MainThreadCanvasEngine(
      scene: _scene,
      log: (msg) => debugPrint('[CanvasWidget] $msg'),
      onMarkNeedsBuild: () {
        if (mounted) setState(() {});
      },
    );

    _engine.init();
    _engine.executeScript(widget.scriptText);
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  void _handleTap(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    _engine.handleTap(local.dx, local.dy);
  }

  void _handlePanStart(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    _engine.handleTouchStart(local.dx, local.dy);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    _engine.handleTouchMove(local.dx, local.dy, details.delta.dx, details.delta.dy);
  }

  void _handlePanEnd(DragEndDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    _engine.handleTouchEnd(local.dx, local.dy);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTap,
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: Container(
        width: double.infinity,
        height: widget.height ?? 400,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: DisplayObjectPainter(_scene),
          size: Size(widget.width ?? 800, widget.height ?? 400),
        ),
      ),
    );
  }
}
