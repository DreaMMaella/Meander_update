import 'dart:math' as math;

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/date_format.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  ГРАФИКИ СТАТИСТИКИ
//
//  Рисуются вручную на CustomPaint: библиотека графиков стоила бы приложению
//  больше, чем вся аналитика, и не дал бы нужного — stacked-столбцы «лайки +
//  дизлайки» одним рядом и подписанные окна.
//
//  Общее правило для всех графиков: пустой день остаётся нулём на своей
//  позиции. Сжатый ряд «только те дни, где что-то было» выглядит красиво и
//  врёт про динамику.
// ============================================================================

class DailyBarChart extends StatelessWidget {
  const DailyBarChart({
    super.key,
    required this.values,
    required this.color,
    this.secondary,
    this.secondaryColor,
    this.dates,
    this.height = 132,
  });

  final List<int> values;

  /// Если задан — ложится тем же столбцом сверху: сумма двух рядов означает
  /// «всего голосов», и это единственный честный способ показать их вместе.
  final List<int>? secondary;
  final Color color;
  final Color? secondaryColor;
  final List<DateTime>? dates;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => CustomPaint(
                size: Size(box.maxWidth, box.maxHeight),
                painter: _BarPainter(
                  values: values,
                  secondary: secondary,
                  color: color,
                  secondaryColor: secondaryColor ?? color.withOpacity(0.45),
                  baseline: scheme.outlineVariant.withOpacity(0.5),
                  maxValueLabel: _topLabel(context),
                  labelColor: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _AxisLabels(dates: dates),
        ],
      ),
    );
  }

  String _topLabel(BuildContext context) {
    var max = 0;
    for (var i = 0; i < values.length; i++) {
      final total =
          values[i] +
          ((secondary != null && i < secondary!.length) ? secondary![i] : 0);
      if (total > max) max = total;
    }
    return max == 0
        ? tr('пусто')
        : trf('{p0} за день', {'p0': formatCompactCount(max)});
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.secondary,
    required this.color,
    required this.secondaryColor,
    required this.baseline,
    required this.maxValueLabel,
    required this.labelColor,
  });

  final List<int> values;
  final List<int>? secondary;
  final Color color;
  final Color secondaryColor;
  final Color baseline;
  final String maxValueLabel;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final caption = TextPainter(
      text: TextSpan(
        text: maxValueLabel,
        style: TextStyle(
          fontSize: 10,
          color: labelColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    caption.paint(canvas, Offset.zero);

    final chartTop = caption.height + 4;
    final chartHeight = math.max(1.0, size.height - chartTop);
    final baseY = chartTop + chartHeight;

    canvas.drawLine(
      Offset(0, baseY),
      Offset(size.width, baseY),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    var max = 0;
    for (var i = 0; i < values.length; i++) {
      final total =
          values[i] +
          ((secondary != null && i < secondary!.length) ? secondary![i] : 0);
      if (total > max) max = total;
    }
    if (max == 0) return;

    final n = values.isEmpty ? 1 : values.length;
    final slot = size.width / n;
    final barWidth = math.min(14.0, math.max(2.0, slot * 0.6));
    for (var i = 0; i < values.length; i++) {
      final first = values[i];
      final second = secondary == null || i >= secondary!.length
          ? 0
          : secondary![i];
      final total = first + second;
      if (total <= 0) continue;

      final cx = slot * i + slot / 2;
      final barHeight = math.max(2.0, chartHeight * (total / max));
      final bar = Rect.fromLTRB(
        cx - barWidth / 2,
        baseY - barHeight,
        cx + barWidth / 2,
        baseY,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          bar,
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = color,
      );
      if (second <= 0) continue;
      // Второй ряд — это верхняя доля того же столбца, а не отдельный столбец:
      // «всего голосов» остаётся высотой, и отношение видно глазами.
      final topPart = Rect.fromLTRB(
        bar.left,
        bar.top,
        bar.right,
        bar.top + barHeight * (second / total),
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          topPart,
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = secondaryColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.values != values ||
      old.secondary != secondary ||
      old.color != color ||
      old.secondaryColor != secondaryColor ||
      old.maxValueLabel != maxValueLabel;
}

/// Подписи оси X: начало, середина и конец окна. Больше подписей в ширину
/// карточки не влезает, а промежуточные даты читаются по позиции.
class _AxisLabels extends StatelessWidget {
  const _AxisLabels({this.dates});

  final List<DateTime>? dates;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = dates;
    if (list == null || list.isEmpty) return const SizedBox(height: 12);
    final style = TextStyle(fontSize: 10, color: scheme.onSurfaceVariant);
    return SizedBox(
      height: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(formatDayMonth(list.first), style: style),
          if (list.length > 2)
            Text(formatDayMonth(list[list.length ~/ 2]), style: style),
          Text(formatDayMonth(list.last), style: style),
        ],
      ),
    );
  }
}

/// Линия дня: для величин, которые не складываются (средняя оценка, часы).
class DailyLineChart extends StatelessWidget {
  const DailyLineChart({
    super.key,
    required this.values,
    required this.color,
    this.dates,
    this.height = 132,
    this.unitLabel,
  });

  final List<double> values;
  final Color color;
  final List<DateTime>? dates;
  final double height;

  /// Подпись масштаба, если число нельзя понять из значения («ч.», «★»).
  final String? unitLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a > b ? a : b);
    final label = maxValue <= 0
        ? tr('пусто')
        : trf('{p0} макс.', {
            'p0':
                '${maxValue.toStringAsFixed(maxValue >= 10 ? 0 : 1)}'
                '${unitLabel == null ? '' : ' $unitLabel'}',
          });
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => CustomPaint(
                size: Size(box.maxWidth, box.maxHeight),
                painter: _LinePainter(
                  values: values,
                  color: color,
                  baseline: scheme.outlineVariant.withOpacity(0.5),
                  label: label,
                  labelColor: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _AxisLabels(dates: dates),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.color,
    required this.baseline,
    required this.label,
    required this.labelColor,
  });

  final List<double> values;
  final Color color;
  final Color baseline;
  final String label;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final caption = _text(label, labelColor);
    caption.paint(canvas, Offset.zero);
    final top = caption.height + 4;
    final h = math.max(1.0, size.height - top);
    final baseY = top + h;

    canvas.drawLine(
      Offset(0, baseY),
      Offset(size.width, baseY),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    var max = 0.0;
    for (final v in values) {
      if (v > max) max = v;
    }
    if (max <= 0 || values.length < 2) return;

    Offset point(int i) => Offset(
      size.width * (i / (values.length - 1)),
      baseY - h * (values[i] / max),
    );

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      final prev = point(i - 1);
      final cur = point(i);
      path.cubicTo(
        prev.dx + (cur.dx - prev.dx) / 2,
        prev.dy,
        prev.dx + (cur.dx - prev.dx) / 2,
        cur.dy,
        cur.dx,
        cur.dy,
      );
    }

    final filled = Path.from(path)
      ..lineTo(size.width, baseY)
      ..lineTo(0, baseY)
      ..close();
    canvas.drawPath(
      filled,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.28), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, top, size.width, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  TextPainter _text(String value, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.color != color || old.label != label;
}

/// Распределение оценок 5..1 — как в Play Console: плохие видно рядом с
/// хорошими, а не только среднее, которое сглаживает всё.
class RatingHistogram extends StatelessWidget {
  const RatingHistogram({super.key, required this.counts, required this.color});

  /// Пять чисел: оценки 5, 4, 3, 2, 1.
  final List<int> counts;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = counts.fold(0, (a, b) => a + b);
    return Column(
      children: [
        for (var i = 0; i < counts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    '${counts.length - i} ★',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : counts[i] / total,
                      minHeight: 8,
                      color: color,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    total == 0 ? '—' : '${counts[i]}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Воронка «посмотрели → скачали → сыграли → лайкнули». Шаг без перехода
/// показывается прочерком: «не из чего считать» честнее нуля.
class FunnelChart extends StatelessWidget {
  const FunnelChart({super.key, required this.steps, required this.color});

  final List<FunnelStep> steps;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = steps.fold<int>(0, (a, s) => s.value > a ? s.value : a);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        steps[i].label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      formatCompactCount(steps[i].value),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Ширина — доля от самого большого шага, а не от абстрактной
                // сотни: иначе воронка не влезала бы в узкую карточку.
                LayoutBuilder(
                  builder: (context, box) {
                    final ratio = max == 0 ? 0.0 : steps[i].value / max;
                    return Container(
                      height: 10,
                      width: ratio <= 0
                          ? 0
                          : math.max(6.0, box.maxWidth * ratio),
                      decoration: BoxDecoration(
                        color: color.withOpacity(i == 0 ? 0.95 : 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    );
                  },
                ),
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      steps[i].transition ?? '—',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class FunnelStep {
  const FunnelStep({required this.label, required this.value, this.transition});

  final String label;
  final int value;

  /// «12% от прошлого шага», посчитанное снаружи — здесь нет знаменателя.
  final String? transition;
}

/// Одна карточка графика: заголовок, пояснение про масштаб и сам график.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: item.$1,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                item.$2,
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
