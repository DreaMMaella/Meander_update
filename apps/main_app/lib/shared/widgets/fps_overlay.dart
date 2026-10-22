import 'dart:async';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Оверлей для отображения FPS в реальном времени
class FPSOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const FPSOverlay({super.key, required this.child, this.enabled = true});

  @override
  State<FPSOverlay> createState() => _FPSOverlayState();
}

class _FPSOverlayState extends State<FPSOverlay> {
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastTime = DateTime.now();
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _startMonitoring();
    }
  }

  void _startMonitoring() {
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onFrame(Duration timestamp) {
    if (!mounted || !widget.enabled) return;

    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastTime).inMilliseconds;

    if (elapsed >= 1000) {
      _fps = (_frameCount * 1000) / elapsed;
      _frameCount = 0;
      _lastTime = now;
    }

    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Color _getFPSColor() {
    if (_fps >= 55) return Colors.green;
    if (_fps >= 30) return Colors.orange;
    return Colors.red;
  }

  String _getPerformanceLabel() {
    if (_fps >= 55) return tr('Отлично');
    if (_fps >= 45) return tr('Хорошо');
    if (_fps >= 30) return tr('Средне');
    return tr('Плохо');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.enabled)
          Positioned(
            top: 50,
            right: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _getFPSColor(), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_fps.toStringAsFixed(1)} FPS',
                      style: TextStyle(
                        color: _getFPSColor(),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getPerformanceLabel(),
                      style: TextStyle(
                        color: _getFPSColor().withOpacity(0.8),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Провайдер для глобального включения/выключения FPS счетчика
class FPSMonitor {
  static final FPSMonitor _instance = FPSMonitor._();
  static FPSMonitor get instance => _instance;
  FPSMonitor._();

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  void toggle() {
    enabled.value = !enabled.value;
  }

  void enable() {
    enabled.value = true;
  }

  void disable() {
    enabled.value = false;
  }
}
