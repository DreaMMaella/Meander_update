import 'package:canvas_app/core/utils/date_format.dart';
import 'package:canvas_app/core/utils/playtime_formatter.dart';
import 'package:canvas_app/features/analytics/models/quest_analytics_model.dart';
import 'package:canvas_app/features/analytics/providers/quest_analytics_provider.dart';
import 'package:canvas_app/features/analytics/widgets/analytics_charts.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
//  СТАТИСТИКА КВЕСТА — как в консоли разработчика, только для автора Meander
//
//  Всё считается на сервере и приходит одним ответом. Экран ничего не
//  пересчитывает по своим правилам: иначе «скачивания за неделю» в двух
//  местах приложения разошлись бы.
// ============================================================================

/// Длина окна в днях. Три фиксированных значения, а не произвольный ввод:
/// сравнение «текущее окно против предыдущего того же размера» имеет смысл
/// только для осмысленных человеку горизонтов.
const List<int> kAnalyticsWindows = [7, 30, 90];

class QuestAnalyticsScreen extends ConsumerStatefulWidget {
  const QuestAnalyticsScreen({
    super.key,
    required this.questId,
    required this.title,
    this.days = 30,
  });

  final String questId;
  final String title;
  final int days;

  @override
  ConsumerState<QuestAnalyticsScreen> createState() =>
      _QuestAnalyticsScreenState();
}

class _QuestAnalyticsScreenState extends ConsumerState<QuestAnalyticsScreen> {
  late int _days = widget.days;

  void _setDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      questAnalyticsProvider((questId: widget.questId, days: _days)),
    );

    return Scaffold(
      body: AdaptiveContent(
        maxWidth: 900,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(
              questAnalyticsProvider((
                questId: widget.questId,
                days: _days,
              )).future,
            ),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverAppBar.large(
                  title: Text(tr('Статистика')),
                  // Прозрачная подложка пропускала контент списка сквозь
                  // крупный заголовок — строки рисовались поверх него.
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final days in kAnalyticsWindows)
                          ChoiceChip(
                            label: Text(trf('{days} дн', {'days': days})),
                            selected: _days == days,
                            onSelected: (_) => _setDays(days),
                          ),
                      ],
                    ),
                  ),
                ),
                async.when(
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, _) => SliverToBoxAdapter(
                    child: _LoadFailed(error: err.toString()),
                  ),
                  data: (data) =>
                      SliverToBoxAdapter(child: _AnalyticsBody(data: data)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.data});

  final QuestAnalytics data;

  String get _periodLabel =>
      trf('с {p0} по {p1}', {
        'p0': formatDayMonth(data.from),
        'p1': formatDayMonth(data.to),
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = data.window;
    final prev = data.previous;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            trf('{_periodLabel} · рядом за то же число дней до этого', {'_periodLabel': _periodLabel}),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          _KpiGrid(
            cards: [
              _KpiCard(
                label: tr('Просмотры'),
                value: formatCompactCount(w.views),
                delta: data.deltaViews(),
                baseline: prev.views,
                sparkline: data.viewsSeries,
                color: scheme.primary,
              ),
              _KpiCard(
                label: tr('Скачивания'),
                value: formatCompactCount(w.downloads),
                delta: data.deltaDownloads(),
                baseline: prev.downloads,
                sparkline: data.downloadsSeries,
                color: scheme.tertiary,
              ),
              _KpiCard(
                label: tr('Игроки'),
                value: formatCompactCount(w.players),
                delta: data.deltaPlayers(),
                baseline: prev.players,
                sparkline: data.playersSeries,
                color: scheme.secondary,
              ),
              _KpiCard(
                label: tr('Время в квесте'),
                value: PlaytimeFormatter.format(w.playtimeSeconds),
                delta: data.deltaPlaytime(),
                baseline: prev.playtimeSeconds,
                sparkline: data.playtimeSeries,
                color: scheme.primary,
                isDuration: true,
              ),
              _KpiCard(
                label: tr('Лайки'),
                value: formatCompactCount(w.likes),
                delta: data.deltaLikes(),
                baseline: prev.likes,
                sparkline: data.likesSeries,
                color: scheme.primary,
              ),
              _KpiCard(
                label: tr('Отзывы'),
                value: formatCompactCount(w.reviews),
                delta: data.deltaReviews(),
                baseline: prev.reviews,
                sparkline: data.reviewsSeries,
                color: scheme.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (data.isEmpty) ...[
            ChartCard(
              title: tr('Пока никто не заходил'),
              subtitle:
                  tr('Просмотры начали считаться отдельной проверкой: если квест опубликован давно, история до этого момента не восстановится.'),
              child: Text(
                tr('Как только страницу откроют, здесь появятся дневные графики, воронка и распределение оценок.'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ChartCard(
            title: tr('Просмотры по дням'),
            subtitle: trf('сколько раз открывали страницу квеста · {_periodLabel}', {'_periodLabel': _periodLabel}),
            child: DailyBarChart(
              values: data.viewsSeries,
              dates: data.dates,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          ChartCard(
            title: tr('Скачивания по дням'),
            subtitle:
                tr('первое скачивание человеком — это скачивание; повторные заходы в уже скачанный квест сюда не входят'),
            child: DailyBarChart(
              values: data.downloadsSeries,
              dates: data.dates,
              color: scheme.tertiary,
            ),
          ),
          const SizedBox(height: 12),
          ChartCard(
            title: tr('Голоса по дням'),
            subtitle: tr('высота — всего голосов, тёмная часть сверху — дизлайки'),
            trailing: ChartLegend(
              items: [
                (scheme.primary, tr('лайки')),
                (scheme.error, tr('дизлайки')),
              ],
            ),
            child: DailyBarChart(
              values: data.likesSeries,
              secondary: data.dislikesSeries,
              secondaryColor: scheme.error.withOpacity(0.75),
              dates: data.dates,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          ChartCard(
            title: tr('Время игры по дням'),
            subtitle: tr('часы, наигранные всеми в этом квесте за день'),
            child: DailyLineChart(
              values: data.playtimeSeries.map((s) => s / 3600).toList(),
              dates: data.dates,
              color: scheme.secondary,
              unitLabel: tr('ч.'),
            ),
          ),
          const SizedBox(height: 12),
          ChartCard(
            title: tr('Игроки по дням'),
            subtitle: tr('сколько человек зашли в квест хотя бы на десять минут'),
            child: DailyLineChart(
              values: data.playersSeries.map((p) => p.toDouble()).toList(),
              dates: data.dates,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          _FunnelCard(data: data),
          const SizedBox(height: 12),
          _RatingCard(data: data),
          const SizedBox(height: 12),
          _LifetimeCard(data: data),
          const SizedBox(height: 12),
          _HowItsCounted(data: data),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.cards});

  final List<_KpiCard> cards;

  @override
  Widget build(BuildContext context) {
    // По два в ряд: на телефоне два столбца читаются, на десктопе та же сетка
    // просто получает больше воздуха.
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      final pair = cards.sublist(
        i,
        i + 2 > cards.length ? cards.length : i + 2,
      );
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          // IntrinsicHeight обязателен: ряд лежит в Column внутри скролла, где
          // высоты нет вовсе, а stretch без неё роняет layout. Карточки при
          // этом одной высоты — две в ряд, как в консоли разработчика.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final card in pair) ...[
                  Expanded(child: card),
                  if (card != pair.last) const SizedBox(width: 8),
                ],
                if (pair.length == 1) const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.delta,
    required this.baseline,
    required this.sparkline,
    required this.color,
    this.isDuration = false,
  });

  final String label;
  final String value;
  final int delta;

  /// Значение в предыдущем окне: по нему решается, показывать ли процент.
  final int baseline;
  final List<int> sparkline;
  final Color color;
  final bool isDuration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          _Delta(delta: delta, baseline: baseline),
          const SizedBox(height: 6),
          _Sparkline(values: sparkline, color: color),
        ],
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.delta, required this.baseline});

  final int delta;
  final int baseline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (delta == 0 && baseline == 0) {
      return Text(
        tr('первые данные'),
        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
      );
    }
    final up = delta > 0;
    final color = delta == 0
        ? scheme.onSurfaceVariant
        : (up ? Colors.green.shade400 : scheme.error);
    final sign = up ? '+' : '';
    final pct = baseline > 0 ? (delta / baseline * 100).round() : null;
    return Row(
      children: [
        Icon(
          delta == 0
              ? Icons.remove_rounded
              : (up
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded),
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            pct == null
                ? '$sign${formatCompactCount(delta)}'
                : '$sign${formatCompactCount(delta)} · $pct%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Мини-график внутри карточки: без осей и подписей, только форма ряда.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, color: color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var max = 0;
    for (final v in values) {
      if (v > max) max = v;
    }
    final paint = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    if (max == 0) {
      canvas.drawLine(
        Offset(0, size.height - 1),
        Offset(size.width, size.height - 1),
        Paint()..color = color.withOpacity(0.25),
      );
      return;
    }

    Offset point(int i) => Offset(
      size.width * (i / (values.length - 1)),
      size.height - 1 - (size.height - 3) * (values[i] / max),
    );

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}

class _FunnelCard extends StatelessWidget {
  const _FunnelCard({required this.data});

  final QuestAnalytics data;

  static String _pct(double? ratio) =>
      ratio == null ? '—' : '${(ratio * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = data.window;
    final votes = w.likes;
    return ChartCard(
      title: tr('Путь игрока за окно'),
      subtitle: tr('где отваливается аудитория: каждый шаг считается от прошлого'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FunnelChart(
            color: scheme.primary,
            steps: [
              FunnelStep(label: tr('Открыли страницу'), value: w.views),
              FunnelStep(
                label: tr('Скачали'),
                value: w.downloads,
                transition: trf('{p0} от просмотров', {'p0': _pct(w.downloadRate)}),
              ),
              FunnelStep(
                label: tr('Сыграли ≥ 10 минут'),
                value: w.players,
                transition: w.downloads == 0
                    ? '—'
                    : trf('{pct} от скачавших', {
                        'pct': _pct(
                          (w.players / w.downloads).clamp(0.0, 1.0).toDouble(),
                        ),
                      }),
              ),
              FunnelStep(
                label: tr('Поставили лайк'),
                value: votes,
                transition: w.players == 0
                    ? '—'
                    : trf('{pct} от игроков', {
                        'pct': _pct(
                          (votes / w.players).clamp(0.0, 1.0).toDouble(),
                        ),
                      }),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            trf('Средняя сессия: {p0} на одного игрока', {'p0': PlaytimeFormatter.format(w.avgPlaytimePerPlayer.round())}),
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.data});

  final QuestAnalytics data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = data.histogram.fold<int>(0, (a, b) => a + b);
    final avg = total == 0
        ? 0.0
        : () {
            var sum = 0;
            for (var i = 0; i < data.histogram.length; i++) {
              sum += data.histogram[i] * (5 - i);
            }
            return sum / total;
          }();
    return ChartCard(
      title: tr('Оценки'),
      subtitle: total == 0
          ? tr('оценок пока нет')
          : trf('всего {total} · средняя {avg} ★ · за окно {window}', {
              'total': total,
              'avg': avg.toStringAsFixed(1),
              'window': data.window.ratings == 0
                  ? tr('ни одной')
                  : '${data.window.ratings}',
            }),
      child: RatingHistogram(counts: data.histogram, color: scheme.primary),
    );
  }
}

class _LifetimeCard extends StatelessWidget {
  const _LifetimeCard({required this.data});

  final QuestAnalytics data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = data.lifetime;
    final rows = <(String, String)>[
      (tr('Просмотров за всё время'), formatCompactCount(l.views)),
      (tr('Разных людей смотрели'), formatCompactCount(l.viewers)),
      (tr('Скачиваний всего'), formatCompactCount(data.lifetimeDownloads)),
      (tr('Игроков всего'), formatCompactCount(l.players)),
      (tr('Наиграно суммарно'), PlaytimeFormatter.format(l.playSeconds)),
      (
        tr('Лайков / дизлайков'),
        '${data.lifetimeLikes} / ${data.lifetimeDislikes}',
      ),
      (
        tr('Отзывов'),
        trf(
          '{p0} из {p1} одобрено',
          {'p0': l.reviewsApproved, 'p1': l.reviews},
        ),
      ),
      (
        tr('Отзывов с ответом автора'),
        '${l.reviewsAnswered} · ${(l.replyShare * 100).round()}%',
      ),
    ];
    return ChartCard(
      title: tr('За всё время'),
      subtitle: tr('фильтр по дням на эти числа не влияет'),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    row.$2,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          if (l.lastViewedDay != null)
            Text(
              trf('Последний заход на страницу: {p0}', {'p0': formatDayMonthYear(l.lastViewedDay!)}),
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Честно про границы измерений: автор имеет право знать, чего эти числа
/// не измеряют, иначе он будет принимать решения по пустому месту.
class _HowItsCounted extends StatelessWidget {
  const _HowItsCounted({required this.data});

  final QuestAnalytics data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Что здесь считается'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in [
            tr('просмотр — открытая страница квеста; свой же просмотр автору не считается, повторный заход того же человека внутри получаса — тоже'),
            tr('голоса берутся из текущего состояния: снятый сегодня лайк исчезнет из вчерашней колонки'),
            tr('игроки — те, кто наиграл в квесте не меньше десяти минут за день; открыл и через минуту вышел — не игрок'),
            tr('сравнение идёт с предыдущим окном той же длины, поэтому «просело» на 90 днях и «выросло» на 7 — это разные вопросы'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '· $line',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        children: [
          Icon(Icons.query_stats_rounded, size: 48, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            tr('Статистика не загрузилась'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            trf('{error}\n\nЕсли это свой квест и ошибка про доступ к таблице — значит сервер ещё не обновлён до версии, которая считает просмотры и игровые сутки.', {'error': error}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
