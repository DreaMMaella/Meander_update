import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';

// ============================================================================
//  Холст косметики: всё рисуется кодом, без ассетов.
//
//  Ассеты (Lottie/mp4) означали бы качающий файл на каждый просмотр чужого
//  профиля и вешали бы widget-тесты. Процедурная графика даёт то же зрелище,
//  весит 0 байт и остаётся управляемой: [t] — секунды с момента появления,
//  поэтому картинка детерминирована и её можно снять снапшотом в тесте.
// ============================================================================

/// Одна частица слоя. Позиции и фазы считает [ParticleFieldPainter] из seed,
/// так что пересборка виджета не «пересыпает» снег заново.
class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.speed,
    required this.sway,
    required this.colorIndex,
  });

  final double x;
  final double y;

  /// Доля высоты холста.
  final double size;
  final double phase;

  /// Множитель скорости падения/всплытия.
  final double speed;
  final double sway;
  final int colorIndex;
}

@immutable
class CosmeticBannerPainter extends CustomPainter {
  const CosmeticBannerPainter({required this.spec, required this.t, this.borderRadius = 24});

  final BannerSpec spec;
  final double t;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    canvas.clipRRect(clip);

    switch (spec.motion) {
      case BannerMotion.still:
        _fillLinear(canvas, size, spec.colors, Alignment.topLeft, Alignment.bottomRight);
      case BannerMotion.drift:
        _paintDrift(canvas, size);
      case BannerMotion.waves:
        _paintDrift(canvas, size);
        _paintBlobs(canvas, size);
      case BannerMotion.ribbons:
        _paintDrift(canvas, size);
        _paintRibbons(canvas, size);
      case BannerMotion.grid:
        _paintGrid(canvas, size);
      case BannerMotion.starfield:
        _paintStarfield(canvas, size);
    }
  }

  /// Концы задаются недирекциональными [Alignment]: внутри `paint()` нет
  /// `Directionality`, и `AlignmentDirectional` там падает в debug-сборке.
  void _fillLinear(
    Canvas canvas,
    Size size,
    List<Color> colors,
    Alignment a,
    Alignment b,
  ) {
    final rect = Offset.zero & size;
    if (colors.length == 1) {
      canvas.drawRect(rect, Paint()..color = colors.first);
      return;
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: colors,
          begin: a,
          end: b,
        ).createShader(rect),
    );
  }

  /// Градиент, у которого концы медленно ходят по кругу: плоская картинка
  /// перестаёт выглядеть статичной без единого лишнего объекта на дереве.
  void _paintDrift(Canvas canvas, Size size) {
    final w = spec.speed;
    final angle = t * 0.24 * w;
    final begin = Alignment(math.cos(angle) * 1.1, math.sin(angle * 0.8) * 1.1);
    final end = Alignment(-begin.x, -begin.y);
    _fillLinear(canvas, size, spec.colors, begin, end);
  }

  /// Мягкие световые пятна поверх градиента — то, что читается как «живое»
  /// сияние, а не как смена обоев.
  void _paintBlobs(Canvas canvas, Size size) {
    final w = spec.speed;
    final accent = spec.colors.length > 2 ? spec.colors[2] : spec.colors.first;
    for (var i = 0; i < 3; i++) {
      final p = _blobPosition(i, t * w);
      final center = Offset(p.dx * size.width, p.dy * size.height);
      final radius = size.shortestSide * (0.55 + 0.12 * i);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withValues(alpha: 0.42 - 0.09 * i),
              accent.withValues(alpha: 0),
            ],
            stops: const [0, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  static Offset _blobPosition(int i, double t) {
    // Разные частоты на ось — траектория не выглядит повторяющейся.
    final fx = 0.11 + 0.037 * i;
    final fy = 0.083 + 0.029 * i;
    return Offset(
      0.5 + 0.42 * math.sin(t * 2 * math.pi * fx + i * 2.1),
      0.5 + 0.36 * math.cos(t * 2 * math.pi * fy + i * 1.3),
    );
  }

  /// Занавес сияния: несколько висящих лент, каждая со своей фазой — они
  /// сжимаются и расходятся, перекрываясь складками. От «волн» отличается тем,
  /// что свет идёт сверху вниз и складки двигаются независимо.
  void _paintRibbons(Canvas canvas, Size size) {
    final w = spec.speed;
    final accent = spec.colors.length > 2 ? spec.colors[2] : spec.colors.last;
    final secondary = spec.colors.length > 1 ? spec.colors[1] : accent;
    const bands = 5;
    for (var i = 0; i < bands; i++) {
      final phase = t * w * 0.5 + i * 1.9;
      // Шаг по золотому сечению: равные отступы читаются как жалюзи, а такие
      // ленты перекрываются в разных местах каждый кадр.
      final cx = size.width * (0.08 + 0.84 * ((i * 0.618034) % 1.0)) + size.width * 0.09 * math.sin(phase);
      // Лента расширяется книзу и заваливается в сторону: вертикальные полосы
      // выглядели бы как жалюзи.
      final halfTop = size.width * (0.022 + 0.014 * math.sin(phase * 1.7));
      final halfBottom = halfTop * 3.4;
      final lean = size.width * 0.09 * math.sin(phase * 0.55 + i);
      final color = i.isEven ? accent : secondary;
      final band = Path()
        ..moveTo(cx - halfTop, -size.height * 0.1)
        ..lineTo(cx + halfTop, -size.height * 0.1)
        ..lineTo(cx + halfBottom + lean, size.height)
        ..lineTo(cx - halfBottom + lean, size.height)
        ..close();
      canvas.drawPath(
        band,
        Paint()
          // Плюс, а не обычное смешивание: на наложении лент появляется та
          // самая яркая складка, ради которой эффект и берётся.
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.02),
              color.withValues(alpha: 0.34 + 0.1 * math.sin(phase * 2).abs()),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.4, 1],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
  }

  /// Неоновая перспективная сетка: горизонт светится, линии бегут на зрителя.
  void _paintGrid(Canvas canvas, Size size) {
    final base = spec.colors.first;
    final neon = spec.colors.length > 2 ? spec.colors[2] : spec.colors.last;
    final deep = spec.colors.length > 1 ? spec.colors[1] : neon;
    _fillLinear(canvas, size, [base, deep.withValues(alpha: 0.75), base], Alignment.topCenter, Alignment.bottomCenter);

    final horizon = size.height * 0.46;
    final glow = Paint()
      ..shader = RadialGradient(
        center: Alignment(0, -0.12),
        radius: 0.75,
        colors: [deep.withValues(alpha: 0.55), deep.withValues(alpha: 0)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);

    final line = Paint()
      ..color = neon.withValues(alpha: 0.5)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    const columns = 13;
    for (var i = 0; i <= columns; i++) {
      final f = i / columns;
      // Луч из точки схода: вертикальные расходятся книзу.
      final topX = size.width * 0.5 + (f - 0.5) * size.width * 0.08;
      final bottomX = size.width * 0.5 + (f - 0.5) * size.width * 2.4;
      canvas.drawLine(
        Offset(topX, horizon),
        Offset(bottomX, size.height),
        line,
      );
    }

    // Бегущие горизонтальные: квадратичная прогрессия даёт перспективу.
    const rows = 11;
    final scroll = (t * 0.22 * spec.speed) % 1;
    for (var i = 0; i < rows; i++) {
      final k = (i + scroll) / rows;
      final y = horizon + (size.height - horizon) * (k * k);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(Offset(0, horizon), Offset(size.width, horizon), Paint()
      ..color = neon.withValues(alpha: 0.85)
      ..strokeWidth = 1.6);
  }

  /// Три слоя звёзд с разной скоростью — параллакс читается даже на 160 px.
  void _paintStarfield(Canvas canvas, Size size) {
    final deep = spec.colors.length > 1 ? spec.colors[1] : spec.colors.first;
    _fillLinear(canvas, size, [spec.colors.first, deep], Alignment.topCenter, Alignment.bottomCenter);

    final rnd = math.Random(7);
    final starPaint = Paint();
    for (var i = 0; i < 90; i++) {
      final layer = 1 + (i % 3);
      final seedX = rnd.nextDouble();
      final y = rnd.nextDouble();
      final r = 0.4 + rnd.nextDouble() * (layer * 0.5);
      final twinkle = 0.45 + 0.55 * math.sin(t * (1.1 + layer * 0.4) + i).abs();
      final x = (seedX + t * 0.006 * layer * spec.speed) % 1.0;
      starPaint.color = spec.colors.last.withValues(
        alpha: math.min(1.0, twinkle * (0.3 + 0.24 * layer)),
      );
      canvas.drawCircle(Offset(x * size.width, y * size.height), r * 1.6, starPaint);
    }

    final comet = (t * 0.12 * spec.speed) % 1.0;
    if (comet > 0.02) {
      final head = Offset(size.width * (1.05 - comet * 0.9), size.height * 0.3);
      final tail = head - const Offset(58, 22);
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..shader = ui.Gradient.linear(tail, head, [
            spec.colors.last.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.75),
          ])
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(CosmeticBannerPainter old) =>
      old.spec != spec || old.t != t || old.borderRadius != borderRadius;
}

/// Кольцо вокруг аватара. Рисуется по внешней границе, чтобы сам аватар
/// оставался обычным `CircleAvatar` и не требовал перестройки вызова.
@immutable
class AvatarFramePainter extends CustomPainter {
  const AvatarFramePainter({
    required this.spec,
    required this.t,
    required this.outerRadius,
  });

  final FrameSpec spec;
  final double t;
  final double outerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final w = spec.speed;
    final ring = outerRadius - spec.width / 2;

    if (spec.glow > 0) {
      canvas.drawCircle(
        center,
        outerRadius + spec.width,
        Paint()
          ..shader = RadialGradient(
            colors: [
              spec.colors.first.withValues(alpha: 0.5 * spec.glow),
              spec.colors.first.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: outerRadius + spec.width),
          ),
      );
    }

    switch (spec.motion) {
      case FrameMotion.conic:
      case FrameMotion.shine:
        // Кольцо с sweep-градиентом крутится поворотом холста: тот же результат,
        // что и GradientTransformation, но без зависимости от тонкостей API.
        _spinningRing(
          canvas,
          center,
          ring,
          SweepGradient(colors: spec.colors),
          rotation: t * (spec.motion == FrameMotion.shine ? 1.6 : 0.7) * w,
        );
      case FrameMotion.pulse:
        final pulse = 0.55 + 0.45 * math.sin(t * 2.2 * w);
        canvas.drawCircle(
          center,
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = spec.width
            ..color = Color.lerp(spec.colors.first, spec.colors.last, pulse)!,
        );
      case FrameMotion.orbit:
        _spinningRing(
          canvas,
          center,
          ring,
          SweepGradient(colors: [
            spec.colors.first.withValues(alpha: 0.25),
            ...spec.colors,
            spec.colors.first.withValues(alpha: 0.25),
          ]),
          rotation: t * 1.9 * w,
        );
        _orbitingSparks(canvas, center, ring + spec.width * 0.4, w);
      case FrameMotion.glitch:
        // Два смещённых кольца вместо «смены кадра»: дёргается только угол.
        final jitter = (t * 6 * w) % 1;
        final double kick = jitter > 0.86 ? 2.2 : 0.0;
        _ring(
          canvas,
          center,
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = spec.width
            ..color = spec.colors.first,
        );
        if (kick > 0) {
          _ring(
            canvas,
            center + Offset(kick, -kick * 0.6),
            ring,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = spec.width
              ..color = spec.colors.last.withValues(alpha: 0.75),
          );
        }
      case FrameMotion.dashed:
        _dashedRing(canvas, center, ring, w);
    }
  }

  /// Гранёное кольцо: короткие дуги по кругу, каждая своим цветом, и всё это
  /// медленно крутится. В отличие от sweep-градиента грани читаются как
  /// отдельные, поэтому рамка не превращается в размытый ободок.
  void _dashedRing(Canvas canvas, Offset center, double radius, double w) {
    const segments = 14;
    final arc = 2 * math.pi / segments;
    final rotation = t * 0.5 * w;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    // Подложка держит форму кольца в щелях: без неё аватар выглядит обрезанным
    // кусками, а не обведённым.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.width * 0.45
        ..color = spec.colors.first.withValues(alpha: 0.22),
    );
    final facet = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spec.width
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < segments; i++) {
      facet.color = spec.colors[i % spec.colors.length];
      canvas.drawArc(bounds, rotation + i * arc, arc * 0.66, false, facet);
    }
  }

  void _ring(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawCircle(center, radius, paint);
  }

  void _spinningRing(
    Canvas canvas,
    Offset center,
    double radius,
    SweepGradient gradient, {
    required double rotation,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.width
        ..shader = gradient.createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );
    canvas.restore();
  }

  void _orbitingSparks(Canvas canvas, Offset center, double radius, double w) {
    for (var i = 0; i < 3; i++) {
      final a = t * 1.5 * w + i * 2.09;
      final p = center + Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.95),
              spec.colors.last.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: p, radius: 4.5)),
      );
    }
  }

  @override
  bool shouldRepaint(AvatarFramePainter old) =>
      old.spec != spec || old.t != t || old.outerRadius != outerRadius;
}

/// Слой частиц поверх обложки.
@immutable
class ParticleFieldPainter extends CustomPainter {
  ParticleFieldPainter({required this.spec, required this.t});

  final EffectSpec spec;
  final double t;

  static const _seed = 424242;

  /// Частиц на один залп салюта. Меньше — россыпь читается редкой, больше —
  /// на узкой обложке превращается в кашу.
  static const _shellSize = 16;

  /// Интервал между залпами и время жизни искры, в секундах «до умножения на
  /// скорость эффекта».
  static const _burstGap = 0.9;
  static const _burstLife = 1.5;

  late final List<_Particle> _particles = _build();

  List<_Particle> _build() {
    final rnd = math.Random(_seed);
    return List.generate(spec.count, (i) {
      return _Particle(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        size: 0.35 + rnd.nextDouble() * 0.65,
        phase: rnd.nextDouble() * math.pi * 2,
        speed: 0.55 + rnd.nextDouble() * 0.9,
        sway: 0.4 + rnd.nextDouble() * 1.5,
        // У салюта цвет держит весь залп: разноцветные искры внутри одной
        // сферы выглядят как конфетти, а не как вспышка.
        colorIndex: spec.kind == ParticleKind.burst
            ? (i ~/ _shellSize) % spec.colors.length
            : i % spec.colors.length,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final w = spec.speed;
    for (var i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      switch (spec.kind) {
        case ParticleKind.snow:
        case ParticleKind.petal:
        case ParticleKind.confetti:
        case ParticleKind.coin:
          _falling(canvas, size, p, w);
        case ParticleKind.ember:
        case ParticleKind.heart:
          _rising(canvas, size, p, w);
        case ParticleKind.burst:
          _burst(canvas, size, p, w, i);
        case ParticleKind.stardust:
          _dust(canvas, size, p, w);
        case ParticleKind.firefly:
          _firefly(canvas, size, p, w);
        case ParticleKind.rain:
          _rain(canvas, size, p, w);
      }
    }
  }

  /// Нисходящие: снег, лепестки, конфетти, монеты. Различаются формой и тем,
  /// крутится частица или нет.
  void _falling(Canvas canvas, Size size, _Particle p, double w) {
    final travel = (p.y + t * 0.07 * w * p.speed) % 1.0;
    final x = (p.x + math.sin(t * 0.7 * w * p.sway + p.phase) * 0.035) % 1.0;
    final pos = Offset(x * size.width, travel * (size.height + 24) - 12);
    final color = spec.colors[p.colorIndex];
    final base = 2.2 + p.size * 4.4;

    switch (spec.kind) {
      case ParticleKind.snow:
        _flake(canvas, pos, base * 0.85, color);
      case ParticleKind.petal:
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(math.sin(t * 0.9 * w + p.phase) * 0.9);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: base * 1.6, height: base),
          Paint()..color = color.withValues(alpha: 0.85),
        );
        canvas.restore();
      case ParticleKind.confetti:
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(t * 2.4 * w * p.speed + p.phase);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: base, height: base * 0.55),
          Paint()..color = color.withValues(alpha: 0.9),
        );
        canvas.restore();
      case ParticleKind.coin:
        // Косинус по X даёт «подмигивание» монеты без 3D.
        final flip = math.cos(t * 3.2 * w * p.speed + p.phase);
        canvas.drawOval(
          Rect.fromCenter(
            center: pos,
            width: base * 1.5 * flip.abs().clamp(0.12, 1.0),
            height: base * 1.5,
          ),
          Paint()..color = color.withValues(alpha: 0.92),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: pos,
            width: base * 0.75 * flip.abs().clamp(0.12, 1.0),
            height: base * 0.75,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.55),
        );
      default:
        break;
    }
  }

  void _rising(Canvas canvas, Size size, _Particle p, double w) {
    final travel = (p.y - t * 0.09 * w * p.speed) % 1.0;
    final y = travel < 0 ? travel + 1 : travel;
    final x = (p.x + math.sin(t * 1.3 * w * p.sway + p.phase) * 0.03) % 1.0;
    final pos = Offset(x * size.width, y * size.height);
    final color = spec.colors[p.colorIndex];
    final fade = (0.25 + 0.75 * (1 - y));
    final base = spec.kind == ParticleKind.heart ? 3.2 + p.size * 3.6 : 1.2 + p.size * 2.2;

    if (spec.kind == ParticleKind.heart) {
      _heart(canvas, pos, base, color.withValues(alpha: 0.85 * fade));
      return;
    }
    canvas.drawCircle(
      pos,
      base,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: fade), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: pos, radius: base * 2.6)),
    );
  }

  /// Салют: залп разлетается из точки, тормозит и гаснет под «гравитацией»,
  /// затем очередь уходит в следующий. Пауза между залпами обязательна: без неё
  /// эффект читается как сплошная россыпь точек, а не как небо с фейерверком.
  void _burst(Canvas canvas, Size size, _Particle p, double w, int i) {
    final shell = i ~/ _shellSize;
    // Центр и размах залпа наследуются от его первой частицы: позиции берутся
    // из того же seeded-набора, поэтому пересыпать кадр нечему.
    final head = _particles[shell * _shellSize];
    final period = _burstGap * ((spec.count - 1) ~/ _shellSize + 1);
    final age = ((t * w - shell * _burstGap) % period) / _burstLife;
    if (age > 1) return;

    // Центр прижат к середине по горизонтали: залп у края обрезался бы наполовину
    // и выглядел как надкушенная сфера.
    final center = Offset(
      (0.14 + head.x * 0.72) * size.width,
      (0.12 + head.y * 0.46) * size.height,
    );
    final reach = size.shortestSide * (0.26 + head.size * 0.2);
    final angle = (i % _shellSize) / _shellSize * math.pi * 2 + p.phase * 0.25;
    // easeOutCubic по разлёту + квадратичное падение: искра тормозит и
    // осыпается, как настоящая.
    final spread = 1 - (1 - age) * (1 - age) * (1 - age);
    final fly = Offset(math.cos(angle), math.sin(angle) * 0.8) * reach * spread +
        Offset(0, age * age * reach * 0.7);
    final pos = center + fly;
    final color = spec.colors[p.colorIndex];
    final fade = 1 - age;
    final r = (0.9 + p.size * 1.5) * (0.5 + 0.5 * fade);

    if (i % _shellSize == 0 && age < 0.14) {
      final flash = 1 - age / 0.14;
      canvas.drawCircle(
        center,
        reach * 0.18 * flash,
        Paint()..color = Colors.white.withValues(alpha: 0.5 * flash),
      );
    }

    // Хвост тянется назад по траектории: без него искра — просто точка.
    canvas.drawLine(
      pos - fly * 0.3,
      pos,
      Paint()
        ..color = color.withValues(alpha: 0.45 * fade)
        ..strokeWidth = r * 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      pos,
      r * 2.4,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.5 * fade), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: pos, radius: r * 2.4)),
    );
    canvas.drawCircle(
      pos,
      r,
      Paint()..color = Color.lerp(color, Colors.white, 0.55)!.withValues(alpha: fade),
    );
  }

  void _dust(Canvas canvas, Size size, _Particle p, double w) {
    final x = (p.x + t * 0.012 * w) % 1.0;
    final pos = Offset(x * size.width, p.y * size.height);
    final tw = 0.3 + 0.7 * math.sin(t * 1.8 * w + p.phase).abs();
    final r = (1.2 + p.size * 2.4) * tw;
    _spark(canvas, pos, r * 2.6, spec.colors[p.colorIndex].withValues(alpha: 0.85 * tw));
  }

  void _firefly(Canvas canvas, Size size, _Particle p, double w) {
    final x = (p.x + math.sin(t * 0.22 * w * p.sway + p.phase) * 0.08) % 1.0;
    final y = (p.y + math.cos(t * 0.17 * w * p.speed + p.phase) * 0.07) % 1.0;
    final pos = Offset(x * size.width, y * size.height);
    final glow = 0.35 + 0.65 * math.sin(t * 2.1 * w + p.phase * 2).abs();
    final color = spec.colors[p.colorIndex];
    final radius = 1.6 + p.size * 2.2;
    canvas.drawCircle(
      pos,
      radius * 3.4,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.45 * glow), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: pos, radius: radius * 3.4)),
    );
    canvas.drawCircle(pos, radius, Paint()..color = Colors.white.withValues(alpha: glow));
  }

  void _rain(Canvas canvas, Size size, _Particle p, double w) {
    final travel = (p.y + t * 0.55 * w * p.speed) % 1.0;
    final x = p.x * size.width;
    final top = travel * (size.height + 30) - 20;
    canvas.drawLine(
      Offset(x, top),
      Offset(x - 2.4, top + 10 + p.size * 12),
      Paint()
        ..color = spec.colors[p.colorIndex].withValues(alpha: 0.5)
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round,
    );
  }

  void _flake(Canvas canvas, Offset pos, double r, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = r < 3 ? 0.8 : 1.1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final a = i * math.pi / 3 + t * 0.4;
      final d = Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawLine(pos - d, pos + d, paint);
    }
  }

  void _spark(Canvas canvas, Offset pos, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(pos.dx - r, pos.dy), Offset(pos.dx + r, pos.dy), paint);
    canvas.drawLine(Offset(pos.dx, pos.dy - r), Offset(pos.dx, pos.dy + r), paint);
  }

  void _heart(Canvas canvas, Offset pos, double s, Color color) {
    final path = Path()
      ..moveTo(pos.dx, pos.dy + s * 0.75)
      ..cubicTo(pos.dx - s * 1.5, pos.dy - s * 0.25, pos.dx - s * 0.5, pos.dy - s * 1.15, pos.dx, pos.dy - s * 0.4)
      ..cubicTo(pos.dx + s * 0.5, pos.dy - s * 1.15, pos.dx + s * 1.5, pos.dy - s * 0.25, pos.dx, pos.dy + s * 0.75)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(ParticleFieldPainter old) => old.t != t || old.spec != spec;
}
