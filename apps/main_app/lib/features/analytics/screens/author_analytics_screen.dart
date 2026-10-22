import 'package:canvas_app/core/utils/date_format.dart';
import 'package:canvas_app/core/utils/playtime_formatter.dart';
import 'package:canvas_app/features/analytics/models/quest_analytics_model.dart';
import 'package:canvas_app/features/analytics/providers/quest_analytics_provider.dart';
import 'package:canvas_app/features/analytics/screens/quest_analytics_screen.dart';
import 'package:canvas_app/features/analytics/widgets/analytics_charts.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
//  СВОДКА АВТОРА — все квесты сразу
//
//  Экран одного квеста отвечает на «как у него», этот — на «сколько у меня
//  вообще и где именно». Числа приходят с сервера теми же окнами и теми же
//  правилами, поэтому одна и та же строка «игроки» здесь и в квесте означает
//  одно и то же.
// ============================================================================

class AuthorAnalyticsScreen extends ConsumerStatefulWidget {
  const AuthorAnalyticsScreen({super.key, this.days = 30, this.nick = ''});

  final int days;

  /// Имя автора в подзаголовке — экран открывается из «Мои публикации», где
  /// имени нет, а без него «12 публикаций» висит в пустоте.
  final String nick;

  @override
  ConsumerState<AuthorAnalyticsScreen> createState() =>
      _AuthorAnalyticsScreenState();
}

class _AuthorAnalyticsScreenState extends ConsumerState<AuthorAnalyticsScreen> {
  late int _days = widget.days;

  void _setDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(authorAnalyticsProvider(_days));

    return Scaffold(
      body: AdaptiveContent(
        maxWidth: 900,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(authorAnalyticsProvider(_days).future),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverAppBar.large(
                  title: Text(tr('Статистика автора')),
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
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.query_stats_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr('Сводка не загрузилась'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$err',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (data) => SliverToBoxAdapter(
                    child: _SummaryBody(data: data, nick: widget.nick),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.data, required this.nick});

  final AuthorAnalytics data;
  final String nick;

  String get _periodLabel => trf('с {from} по {to}', {
    'from': formatDayMonth(data.from),
    'to': formatDayMonth(data.to),
  });

  String get _headline {
    final n = data.questsTotal;
    final count = '$n ${trp(['публикация', 'публикации', 'публикаций'], n)}';
    return nick.isEmpty ? count : '$nick · $count';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = data.window;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _headline,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            trf('{_periodLabel} · из них в маркете {p0}. Сравнение — с предыдущим окном той же длины.', {'_periodLabel': _periodLabel, 'p0': data.questsPublished}),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          _TileRow(
            tiles: [
              _Tile(
                label: tr('Просмотры'),
                value: formatCompactCount(w.views),
                delta: data.deltaViews(),
                color: scheme.primary,
              ),
              _Tile(
                label: tr('Скачивания'),
                value: formatCompactCount(w.downloads),
                delta: data.deltaDownloads(),
                color: scheme.tertiary,
              ),
              _Tile(
                label: tr('Игроки'),
                value: formatCompactCount(w.players),
                delta: data.deltaPlayers(),
                color: scheme.secondary,
              ),
              _Tile(
                label: tr('Время в квестах'),
                value: PlaytimeFormatter.format(w.playtimeSeconds),
                delta: data.deltaPlaytime(),
                color: scheme.primary,
                isDuration: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (data.isEmpty)
            ChartCard(
              title: tr('За это окно никто не заходил'),
              subtitle:
                  tr('Просмотры считаются отдельной проверкой: если квесты опубликованы давно, история до этого момента не восстановится.'),
              child: Text(
                tr('Скачивания, голоса и игровое время копятся с самого начала — если и они нулевые, аудитора у публикаций пока нет.'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          if (data.isEmpty) const SizedBox(height: 12),
          ChartCard(
            title: tr('Просмотры по дням'),
            subtitle: trf('все квесты вместе · {_periodLabel}', {'_periodLabel': _periodLabel}),
            child: DailyBarChart(
              values: data.viewsSeries,
              dates: data.dates,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          ChartCard(
            title: tr('Скачивания и игроки по дням'),
            subtitle:
                tr('столбик — скачивания, тёмная часть сверху — те, кто наиграл не меньше десяти минут'),
            trailing: ChartLegend(
              items: [
                (scheme.tertiary, tr('скачивания')),
                (scheme.tertiary.withOpacity(0.45), tr('игроки')),
              ],
            ),
            child: DailyBarChart(
              values: data.downloadsSeries,
              secondary: data.playersSeries,
              secondaryColor: scheme.tertiary.withOpacity(0.45),
              dates: data.dates,
              color: scheme.tertiary,
            ),
          ),
          const SizedBox(height: 12),
          ChartCard(
            title: tr('По квестам за окно'),
            subtitle: data.quests.length >= _kQuestRowsCap
                ? trf('показаны первые {cap} по просмотрам', {
                    'cap': _kQuestRowsCap,
                  })
                : tr('отсортировано по просмотрам'),
            child: data.quests.isEmpty
                ? Text(
                    tr('Публикаций пока нет.'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: [
                      for (final quest in data.quests)
                        _QuestRow(quest: quest, days: data.days),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Сервер отдаёт не больше этого числа строк — подпись должна говорить ровно
/// то, что отрезал сервер, а не то, что видно на экране.
const int _kQuestRowsCap = 60;

class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.quest, required this.days});

  final AuthorAnalyticsQuest quest;
  final int days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuestAnalyticsScreen(
            questId: quest.id,
            title: quest.title,
            days: days,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quest.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (quest.status != 'published')
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.visibility_off_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              trf('{p0} · {p1} · {p2} · {p3} · {p4}', {'p0': _count(quest.views, ['просмотр', 'просмотра', 'просмотров']), 'p1': _count(quest.downloads, ['скачивание', 'скачивания', 'скачиваний']), 'p2': _count(quest.players, ['игрок', 'игрока', 'игроков']), 'p3': PlaytimeFormatter.format(quest.playtimeSeconds), 'p4': _count(quest.likes, ['лайк', 'лайка', 'лайков'])}),
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final pair = tiles.sublist(
        i,
        i + 2 > tiles.length ? tiles.length : i + 2,
      );
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final tile in pair) ...[
                  Expanded(child: tile),
                  if (tile != pair.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.delta,
    required this.color,
    this.isDuration = false,
  });

  final String label;
  final String value;
  final int delta;
  final Color color;
  final bool isDuration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final up = delta > 0;
    final deltaColor = delta == 0
        ? scheme.onSurfaceVariant
        : (up ? Colors.green.shade400 : scheme.error);
    final deltaText = delta == 0
        ? tr('без изменений')
        : trf('{p0} за окно', {
            'p0':
                '${up ? '+' : '−'}'
                '${isDuration ? PlaytimeFormatter.format(delta.abs()) : formatCompactCount(delta.abs())}',
          });
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
          Text(
            deltaText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: deltaColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Склонение по трём формам с числом: «1 публикация / 2 публикации /
/// 5 публикаций». Заголовок без числа читается как машинный перевод.
String _plural(int n, List<String> forms) => '$n ${trp(forms, n)}';

/// Тот же смысл, что и в KPI: крупные числа сворачиваются в 1.2k, а склонение
/// берётся из последней цифры разряда — для «километров» форма всегда множественная.
String _count(int n, List<String> forms) =>
    n >= 1000 ? '${formatCompactCount(n)} ${trpMany(forms)}' : _plural(n, forms);
