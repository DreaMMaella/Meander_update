import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

/// Переход между нодами «переворот страницы» (screen-space fold с захватом
/// уходящей сцены в картинку).
///
/// Уходящая сцена (фон + контент, переданные как [child] и [background])
/// живёт один-два кадра в RepaintBoundary, захватывается в [ui.Image], после
/// чего лист делится линией сгиба:
///  * слева от сгиба — ещё неперевёрнутая часть уходящей страницы;
///  * правая часть зеркалится относительно линии сгиба в тёмную «изнанку»
///    (отражённый контент читается как оборот листа);
///  * под сгибом проступает новая страница.
///
/// Линия сгиба бежит справа налево (как листание книги вперёд). Захват
/// вместо живых виджетов: страница непрозрачна (с фоном), уходящая нода
/// выгружается из дерева (один ScrollController на одну ноду), и картинка
/// — фундамент для честного curl (уровень 2). Если захват не удался —
/// переход пропускается (новая нода показывается сразу).
class NodeFlipTransition extends StatefulWidget {
  const NodeFlipTransition({
    super.key,
    required this.presentationId,
    required this.child,
    this.background,
    this.duration = const Duration(milliseconds: 900),
  });

  /// Идентификатор текущей ноды. При смене значения — запускается переворот.
  final String presentationId;

  /// Контент текущей ноды (новой).
  final Widget child;

  /// Фон игровой сцены (рисуется под контентом). В уходящей странице
  /// захватывается вместе с контентом, чтобы лист не был прозрачным.
  final Widget? background;

  final Duration duration;

  @override
  State<NodeFlipTransition> createState() => _NodeFlipTransitionState();
}

class _NodeFlipTransitionState extends State<NodeFlipTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _captureKey = GlobalKey();

  /// Уходящая сцена (виджеты предыдущей ноды), живёт до захвата.
  Widget? _previous;
  Widget? _background;

  /// Захваченное изображение уходящей сцены; пока не готово — фолд не идёт.
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _disposeImage();
          setState(() {
            _previous = null;
            _background = null;
          });
        }
      });
  }

  @override
  void didUpdateWidget(covariant NodeFlipTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentationId != widget.presentationId) {
      _disposeImage();
      _controller.stop();
      _controller.value = 0;
      setState(() {
        _previous = oldWidget.child;
        _background = oldWidget.background;
      });
      // Захват со следующего кадра: RepaintBoundary должен быть отрисован.
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    }
  }

  Future<void> _capture() async {
    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      _abort();
      return;
    }
    try {
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image = image;
        _previous = null;
        _background = null;
      });
      _controller.forward(from: 0);
    } catch (_) {
      if (mounted) _abort();
    }
  }

  void _abort() {
    _disposeImage();
    setState(() {
      _previous = null;
      _background = null;
    });
  }

  void _disposeImage() {
    _image?.dispose();
    _image = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _disposeImage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Пока нет ни уходящей сцены, ни захваченной картинки — просто контент.
    if (_previous == null && _image == null) return widget.child;

    // Предзахват: уходящая сцена целиком (фон + контент, непрозрачная)
    // поверх входящей. Через кадр она захватывается в _image.
    if (_image == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                key: _captureKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [if (_background != null) _background!, _previous!],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final image = _image!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) return widget.child;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(_controller.value);
            // Линия сгиба: справа (t=0) → влево (t=1).
            final foldX = width * (1.0 - t);
            // Левая граница зеркальной «изнанки» (до 0 обрезается экраном).
            final stripLeft = (2 * foldX - width).clamp(0.0, width);

            return Stack(
              fit: StackFit.expand,
              children: [
                // 1. Новая страница — раскрывается по мере ухода старой.
                widget.child,

                // 2. Тень от линии сгиба на новой странице (справа от сгиба).
                Positioned(
                  left: foldX,
                  top: 0,
                  bottom: 0,
                  width: _foldShadowWidth,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withOpacity(0.45),
                            Colors.black.withOpacity(0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 3. Уходящая страница — неперевёрнутая часть [0, foldX].
                _pagePiece(
                  image: image,
                  foldX: foldX,
                  clipLeft: 0,
                  clipRight: foldX,
                  height: height,
                  mirrored: false,
                ),

                // 4. Зеркальная «изнанка» отогнутой части [foldX, width],
                //    отражённая влево относительно линии сгиба.
                _pagePiece(
                  image: image,
                  foldX: foldX,
                  clipLeft: stripLeft,
                  clipRight: foldX,
                  height: height,
                  mirrored: true,
                ),

                // 5. Затемнение «изнанки» + тень у самого сгиба (темнее
                //    у линии сгиба, прозрачно у свободного края).
                Positioned(
                  left: stripLeft,
                  top: 0,
                  bottom: 0,
                  width: (foldX - stripLeft),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            Colors.black.withOpacity(0.55),
                            Colors.black.withOpacity(0.28),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _pagePiece({
    required ui.Image image,
    required double foldX,
    required double clipLeft,
    required double clipRight,
    required double height,
    required bool mirrored,
  }) {
    Widget img = RawImage(image: image, fit: BoxFit.fill);
    if (mirrored) {
      img = ColorFiltered(
        colorFilter: ColorFilter.mode(
          Colors.black.withOpacity(0.4),
          BlendMode.srcATop,
        ),
        child: img,
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ClipRect(
            clipper: _RectClipper(clipLeft, clipRight),
            child: mirrored
                ? Transform(
                    transform:
                        Matrix4.translationValues(2 * foldX, 0, 0) *
                        Matrix4.diagonal3Values(-1, 1, 1),
                    alignment: Alignment.topLeft,
                    child: img,
                  )
                : img,
          ),
        ),
      ),
    );
  }
}

const double _foldShadowWidth = 48;

/// Клип по вертикальной полосе [left, right] без пере-раскладки контента.
class _RectClipper extends CustomClipper<Rect> {
  const _RectClipper(this.left, this.right);

  final double left;
  final double right;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(left, 0, right, size.height);

  @override
  bool shouldReclip(_RectClipper oldClipper) =>
      oldClipper.left != left || oldClipper.right != right;
}
