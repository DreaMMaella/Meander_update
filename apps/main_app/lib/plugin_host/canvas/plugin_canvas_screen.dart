import 'package:canvas_app/plugin_host/canvas/display_object.dart';
import 'package:canvas_app/plugin_host/canvas/display_renderer.dart';
import 'package:canvas_app/plugin_host/canvas/physics_engine.dart';
import 'package:canvas_app/plugin_host/canvas/timer_manager.dart';
import 'package:canvas_app/plugin_host/canvas/transition_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class PluginCanvasScreen extends StatefulWidget {
  final DisplayScene scene;
  final String pluginId;
  final VoidCallback? onClose;

  const PluginCanvasScreen({
    super.key,
    required this.scene,
    required this.pluginId,
    this.onClose,
  });

  @override
  State<PluginCanvasScreen> createState() => _PluginCanvasScreenState();
}

class _PluginCanvasScreenState extends State<PluginCanvasScreen>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late TransitionManager _transitions;
  late TimerManager _timers;
  late PhysicsEngine _physics;
  DateTime? _lastFrame;
  bool _isRunning = false;

  final Map<String, Function(Map<String, dynamic>)> _touchListeners = {};
  final Map<String, Function(Map<String, dynamic>)> _tapListeners = {};

  @override
  void initState() {
    super.initState();
    _transitions = TransitionManager();
    _timers = TimerManager();
    _physics = PhysicsEngine();

    _physics.onCollision((idA, idB) {
      _dispatchEvent(idA, 'collision', {'with': idB});
      _dispatchEvent(idB, 'collision', {'with': idA});
    });

    _ticker = createTicker(_onTick);
    _isRunning = true;
    _ticker.start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dispatchGlobalEvent('sceneReady', {
        'sceneId': widget.scene.id,
        'width': widget.scene.width,
        'height': widget.scene.height,
      });
    });
  }

  @override
  void dispose() {
    _isRunning = false;
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_isRunning) return;

    final now = DateTime.now();
    final delta = _lastFrame == null
        ? const Duration(milliseconds: 16)
        : now.difference(_lastFrame!);
    _lastFrame = now;

    _transitions.update(delta);
    _timers.update(delta);
    _physics.update(delta, widget.scene);

    if (mounted) {
      setState(() {});
    }
  }

  void _dispatchEvent(String objectId, String eventType, Map<String, dynamic> data) {
    final obj = widget.scene.objectMap[objectId];
    if (obj == null) return;

    final listener = _touchListeners[objectId];
    if (listener != null) {
      listener({'type': eventType, 'target': objectId, ...data});
    }
  }

  void _dispatchGlobalEvent(String eventType, Map<String, dynamic> data) {
    final listener = _touchListeners['__global__'];
    listener?.call({'type': eventType, ...data});
  }

  void _handleTap(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localOffset = box.globalToLocal(details.globalPosition);
    final x = localOffset.dx;
    final y = localOffset.dy;

    final hit = widget.scene.hitTest(x, y);
    if (hit != null) {
      _dispatchEvent(hit.id, 'tap', {'x': x, 'y': y});
    }
  }

  void _handlePanStart(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localOffset = box.globalToLocal(details.globalPosition);
    final x = localOffset.dx;
    final y = localOffset.dy;

    final hit = widget.scene.hitTest(x, y);
    if (hit != null) {
      _dispatchEvent(hit.id, 'touchStart', {'x': x, 'y': y});
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localOffset = box.globalToLocal(details.globalPosition);
    final x = localOffset.dx;
    final y = localOffset.dy;

    final hit = widget.scene.hitTest(x, y);
    if (hit != null) {
      _dispatchEvent(hit.id, 'touchMove', {'x': x, 'y': y, 'dx': details.delta.dx, 'dy': details.delta.dy});
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localOffset = box.globalToLocal(details.globalPosition);
    final x = localOffset.dx;
    final y = localOffset.dy;

    final hit = widget.scene.hitTest(x, y);
    if (hit != null) {
      _dispatchEvent(hit.id, 'touchEnd', {'x': x, 'y': y});
    }
  }

  void registerTouchHandler(String objectId, Function(Map<String, dynamic>) handler) {
    _touchListeners[objectId] = handler;
  }

  void registerTapHandler(String objectId, Function(Map<String, dynamic>) handler) {
    _tapListeners[objectId] = handler;
  }

  TransitionManager get transitions => _transitions;
  TimerManager get timers => _timers;
  PhysicsEngine get physics => _physics;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: _handleTap,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: CustomPaint(
          painter: DisplayObjectPainter(widget.scene),
          size: Size(widget.scene.width, widget.scene.height),
        ),
      ),
    );
  }
}
