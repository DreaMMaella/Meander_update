import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'node_flip_transition.dart';

/// Все поддерживаемые режимы перехода между нодами.
const List<String> kNodeTransitionModes = [
  'none',
  'fade',
  'page',
  'dark',
  'slide',
  'slideUp',
  'zoom',
  'blur',
  'wipe',
  'flip',
];

/// Человекочитаемые названия режимов (для редактора/превью).
String nodeTransitionModeLabel(String mode) {
  switch (mode) {
    case 'fade':
      return 'Затухание';
    case 'page':
      return 'Перелистывание';
    case 'dark':
      return 'Затемнение';
    case 'slide':
      return 'Сдвиг';
    case 'slideUp':
      return 'Подъём';
    case 'zoom':
      return 'Масштаб';
    case 'blur':
      return 'Размытие';
    case 'wipe':
      return 'Шторка';
    case 'flip':
      return 'Переворот';
    default:
      return 'Без анимации';
  }
}

/// Резолвит сырое значение из конфига квеста/ноды в канонический режим
/// (с псевдонимами). Неизвестные значения → `none`.
String resolveNodeTransitionMode(String? rawMode) {
  final mode = (rawMode ?? '').trim().toLowerCase();
  if (mode == 'fade' || mode == 'default') return 'fade';
  if (mode == 'page') return 'page';
  if (mode == 'dark' || mode == 'black' || mode == 'fadetoblack') {
    return 'dark';
  }
  if (mode == 'slide') return 'slide';
  if (mode == 'slideup' || mode == 'slide_up' || mode == 'up') {
    return 'slideUp';
  }
  if (mode == 'zoom' || mode == 'scale') return 'zoom';
  if (mode == 'blur' || mode == 'blurout' || mode == 'blur_in') return 'blur';
  if (mode == 'wipe' || mode == 'reveal' || mode == 'curtain') return 'wipe';
  if (mode == 'flip' || mode == 'curl' || mode == 'fold' || mode == 'book') {
    return 'flip';
  }
  return 'none';
}

/// Единая точка для всех эффектов смены ноды. Используется и в игре
/// (GameScreen), и в редакторе (живая превью), поэтому превью показывает
/// ровно то, что будет в игре.
///
/// При смене [presentationId] запускается эффект [mode] между уходящей и
/// входящей нодами. [background] нужен flip-эффекту (захват сцены с фоном).
class NodeTransitionSwitcher extends StatelessWidget {
  const NodeTransitionSwitcher({
    super.key,
    required this.mode,
    required this.presentationId,
    required this.child,
    this.background,
  });

  final String mode;
  final String presentationId;
  final Widget child;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final keyedChild = KeyedSubtree(
      key: ValueKey('node_$presentationId'),
      child: child,
    );

    switch (mode) {
      case 'fade':
        return _fadeSwitcher(keyedChild);
      case 'page':
        return _pageSwitcher(keyedChild);
      case 'dark':
        return _NodeDarkenTransition(
          presentationId: presentationId,
          child: keyedChild,
        );
      case 'flip':
        return NodeFlipTransition(
          presentationId: presentationId,
          child: keyedChild,
          background: background,
        );
      case 'slide':
      case 'slideUp':
      case 'zoom':
      case 'blur':
      case 'wipe':
        return _NodeMoveTransition(
          mode: mode,
          presentationId: presentationId,
          child: keyedChild,
        );
      case 'none':
      default:
        return keyedChild;
    }
  }

  Widget _fadeSwitcher(Widget child) {
    // Истинный cross-fade: обе ноды одновременно в дереве (дефолтный
    // layoutBuilder AnimatedSwitcher держит их в Stack) — старая растворяется,
    // новая проявляется.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
      child: child,
    );
  }

  Widget _pageSwitcher(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 820),
      reverseDuration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
          reverseCurve: Curves.easeInOutCubic,
        );
        final rotate = Tween<double>(begin: 0.28, end: 0.0).animate(curved);
        final slide = Tween<Offset>(
          begin: const Offset(0.16, 0.0),
          end: Offset.zero,
        ).animate(curved);
        final shadowOpacity = Tween<double>(
          begin: 0.25,
          end: 0.0,
        ).animate(curved);

        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.9, curve: Curves.easeOut),
          reverseCurve: const Interval(0.1, 1.0, curve: Curves.easeIn),
        );

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: AnimatedBuilder(
              animation: rotate,
              child: child,
              builder: (context, child) {
                final transform = Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(rotate.value);
                return Transform(
                  transform: transform,
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(shadowOpacity.value),
                          blurRadius: 24,
                          offset: const Offset(-12, 0),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                );
              },
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Переход «затемнение»: уходящая нода уходит в чёрный, затем новая
/// проявляется из чёрного. Смена ноды — в момент полного затемнения
/// (t = 0.5), в один кадр: две ноды никогда не живут в дереве вместе.
class _NodeDarkenTransition extends StatefulWidget {
  const _NodeDarkenTransition({
    required this.presentationId,
    required this.child,
  });

  final String presentationId;
  final Widget child;

  @override
  State<_NodeDarkenTransition> createState() => _NodeDarkenTransitionState();
}

class _NodeDarkenTransitionState extends State<_NodeDarkenTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Widget? _previous;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _previous = null);
          }
        });
  }

  @override
  void didUpdateWidget(covariant _NodeDarkenTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentationId != widget.presentationId) {
      setState(() => _previous = oldWidget.child);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previous;
    if (previous == null) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final showNew = t >= 0.5;
        final phaseT = showNew ? (t - 0.5) * 2 : t * 2;
        final blackOpacity = Curves.easeInOut.transform(
          showNew ? 1.0 - phaseT : phaseT,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            showNew ? widget.child : previous,
            IgnorePointer(
              child: ColoredBox(color: Colors.black.withOpacity(blackOpacity)),
            ),
          ],
        );
      },
    );
  }
}

/// Простые движущиеся эффекты: slide, slideUp, zoom, blur, wipe.
/// Обе ноды живут в одном Stack под одним контроллером.
class _NodeMoveTransition extends StatefulWidget {
  const _NodeMoveTransition({
    required this.mode,
    required this.presentationId,
    required this.child,
  });

  final String mode;
  final String presentationId;
  final Widget child;

  @override
  State<_NodeMoveTransition> createState() => _NodeMoveTransitionState();
}

class _NodeMoveTransitionState extends State<_NodeMoveTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Widget? _previous;

  Duration get _duration {
    switch (widget.mode) {
      case 'zoom':
        return const Duration(milliseconds: 450);
      case 'blur':
        return const Duration(milliseconds: 650);
      default:
        return const Duration(milliseconds: 520);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _previous = null);
        }
      });
  }

  @override
  void didUpdateWidget(covariant _NodeMoveTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentationId != widget.presentationId) {
      setState(() => _previous = oldWidget.child);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previous;
    if (previous == null) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final raw = _controller.value;
            final t = Curves.easeInOutCubic.transform(raw);
            return Stack(
              fit: StackFit.expand,
              children: _layers(previous, t, raw, w, h),
            );
          },
        );
      },
    );
  }

  List<Widget> _layers(
    Widget previous,
    double t,
    double raw,
    double w,
    double h,
  ) {
    switch (widget.mode) {
      case 'slide':
        // Новая въезжает справа, старая уезжает влево.
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Transform.translate(
                  offset: Offset(-t * w * 0.45, 0),
                  child: previous,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Transform.translate(
              offset: Offset((1 - t) * w, 0),
              child: widget.child,
            ),
          ),
        ];
      case 'slideUp':
        // Новая поднимается снизу, старая уходит вверх.
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Transform.translate(
                  offset: Offset(0, -t * h * 0.45),
                  child: previous,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(0, (1 - t) * h),
              child: widget.child,
            ),
          ),
        ];
      case 'zoom':
        // Новая вырастает из мелкого масштаба, проявляясь из старой.
        return [
          Positioned.fill(child: previous),
          Positioned.fill(
            child: Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.72 + 0.28 * t,
                child: widget.child,
              ),
            ),
          ),
        ];
      case 'blur':
        // Старая уходит в размытие, новая проявляется резкой из-под неё.
        final outT = (raw / 0.55).clamp(0.0, 1.0).toDouble();
        final inT = ((raw - 0.45) / 0.55).clamp(0.0, 1.0).toDouble();
        return [
          Positioned.fill(
            child: Opacity(opacity: inT, child: widget.child),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 1.0 - outT,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 6 * outT,
                      sigmaY: 6 * outT,
                    ),
                    child: previous,
                  ),
                ),
              ),
            ),
          ),
        ];
      case 'wipe':
      default:
        // Шторка: новая нода открывается вертикальной границей слева направо.
        return [
          Positioned.fill(child: previous),
          Positioned.fill(
            child: ClipRect(clipper: _WipeClipper(t * w), child: widget.child),
          ),
        ];
    }
  }
}

/// Клип по полосе [0, right] — для «шторки».
class _WipeClipper extends CustomClipper<Rect> {
  const _WipeClipper(this.right);

  final double right;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, right, size.height);

  @override
  bool shouldReclip(_WipeClipper oldClipper) => oldClipper.right != right;
}

/// Живая превью эффекта перехода для редактора. Проигрывает выбранный
/// [mode] между двумя мини-сценами; при смене режима эффект воспроизводится
/// автоматически, кнопкой ▶ можно повторить. Использует тот же
/// [NodeTransitionSwitcher], что и игра.
class NodeTransitionPreview extends StatefulWidget {
  const NodeTransitionPreview({
    super.key,
    required this.mode,
    this.height = 190,
  });

  final String mode;
  final double height;

  @override
  State<NodeTransitionPreview> createState() => _NodeTransitionPreviewState();
}

class _NodeTransitionPreviewState extends State<NodeTransitionPreview> {
  int _generation = 0;

  bool get _isB => _generation.isOdd;

  @override
  void didUpdateWidget(covariant NodeTransitionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      setState(() => _generation = 0);
      // Внутренний виджет эффекта пересоздался — проигрываем переход один раз
      // со следующего кадра, чтобы было видно новый эффект сразу.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _generation = 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final modeName = nodeTransitionModeLabel(widget.mode);
    return Container(
      height: widget.height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0a0a0f), Color(0xFF1a1a2e)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NodeTransitionSwitcher(
            mode: widget.mode,
            presentationId: 'preview_$_generation',
            child: _PreviewScene(isB: _isB),
          ),
          Positioned(
            left: 12,
            top: 10,
            child: Text(
              modeName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Material(
              color: Colors.white.withOpacity(0.16),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _generation++),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewScene extends StatelessWidget {
  const _PreviewScene({required this.isB});

  final bool isB;

  @override
  Widget build(BuildContext context) {
    final color = isB ? const Color(0xFF1b5e8a) : const Color(0xFF8a2a2a);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isB ? Icons.flag_rounded : Icons.location_on_rounded,
              color: Colors.white,
              size: 30,
            ),
            const SizedBox(height: 6),
            Text(
              isB ? 'Нода Б' : 'Нода А',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isB ? 'Содержимое ноды Б' : 'Содержимое ноды А',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
