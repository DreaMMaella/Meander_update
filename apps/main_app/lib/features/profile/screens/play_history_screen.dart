import 'package:canvas_app/core/utils/playtime_formatter.dart';
import 'package:canvas_app/features/market/widgets/market_widgets.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';
import 'package:canvas_app/features/profile/providers/play_history_provider.dart';
import 'package:canvas_app/features/profile/providers/profile_provider.dart';
import 'package:canvas_app/features/profile/widgets/profile_widgets.dart';
import 'package:canvas_app/features/market/screens/quest_market_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

// ============================================================================
//  ИГРОВАЯ ИСТОРИЯ — во что и сколько играл, как в Steam
// ============================================================================

class PlayHistoryScreen extends ConsumerStatefulWidget {
  const PlayHistoryScreen({super.key, this.userId, this.ownerName});

  /// Кого показываем: `null` — себя, иначе id другого профиля.
  final String? userId;

  /// Имя владельца библиотеки — чтобы заголовок не врал, чужой список смотреть.
  final String? ownerName;

  @override
  ConsumerState<PlayHistoryScreen> createState() => _PlayHistoryScreenState();
}

class _PlayHistoryScreenState extends ConsumerState<PlayHistoryScreen> {
  /// false — «недавние» (как в Steam по умолчанию), true — «больше всего».
  bool _sortByTime = false;
  bool _opening = false;

  List<PlayHistoryEntry> _ordered(List<PlayHistoryEntry> items) {
    final list = [...items];
    if (_sortByTime) {
      list.sort((a, b) => b.seconds.compareTo(a.seconds));
    }
    return list;
  }

  /// Карточка квеста живёт в маркете, а история знает только id — тянем
  /// публикацию существующим провайдером. Снятый квест отвечает ошибкой,
  /// и это честный ответ, а не молчаливый пустой экран.
  Future<void> _openDetails(PlayHistoryEntry entry) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final quest = await ref.read(marketQuestProvider(entry.questId).future);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuestMarketDetailsScreen(quest: quest),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Квест больше недоступен'))),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subjectId = widget.userId ?? 'me';
    final historyAsync = ref.watch(playHistoryProvider(subjectId));
    final ownerName = widget.ownerName;

    return Scaffold(
      body: AdaptiveContent(
        maxWidth: 900,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(playHistoryProvider(subjectId).future),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverAppBar.large(
                  title: Text(
                    ownerName == null ? tr('Игровая история') : trf('{ownerName} · игры', {'ownerName': ownerName}),
                  ),
                  // Прозрачная подложка пропускала контент списка сквозь
                  // крупный заголовок — строки рисовались поверх него.
                  backgroundColor: scheme.surface,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                ),
                historyAsync.when(
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, _) => SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          trf('Не удалось загрузить историю. {p0}', {'p0': friendlyError(err)}),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ),
                  ),
                  data: (history) {
                    if (history.items.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyHistory(isMine: ownerName == null),
                      );
                    }
                    final items = _ordered(history.items);
                    return SliverList(
                      delegate: SliverChildListDelegate([
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Summary(history: history),
                              const SizedBox(height: 12),
                              _ActivityStrip(history: history),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: [
                                  _SortChip(
                                    label: tr('Недавние'),
                                    icon: Icons.schedule_rounded,
                                    selected: !_sortByTime,
                                    onTap: () => setState(() {
                                      _sortByTime = false;
                                    }),
                                  ),
                                  _SortChip(
                                    label: tr('Больше всего'),
                                    icon: Icons.query_stats_rounded,
                                    selected: _sortByTime,
                                    onTap: () => setState(() {
                                      _sortByTime = true;
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                        for (final entry in items)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: _HistoryCard(
                              entry: entry,
                              onOpen: () => _openDetails(entry),
                            ),
                          ),
                        const SizedBox(height: 96),
                      ]),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  СВОДКА
// ============================================================================

class _Summary extends StatelessWidget {
  final PlayHistory history;
  const _Summary({required this.history});

  @override
  Widget build(BuildContext context) {
    // ProfileStatTile сам по себе Expanded — оборачивать ещё раз нельзя.
    return Row(
      children: [
        ProfileStatTile(
          icon: Icons.explore_outlined,
          value: PlaytimeFormatter.format(history.totalSeconds),
          label: tr('Всего в квестах'),
        ),
        const SizedBox(width: 8),
        ProfileStatTile(
          icon: Icons.menu_book_rounded,
          value: '${history.questsPlayed}',
          label: tr('Квестов'),
        ),
        const SizedBox(width: 8),
        ProfileStatTile(
          icon: Icons.calendar_month_rounded,
          value: '${history.activeDays}',
          label: tr('Игровых дней'),
        ),
      ],
    );
  }
}

/// Полоска дневной активности: столбцы — недели, клетки — дни. Голые секунды
/// из таблиц никто не читает, а вот «где он реально живёт» по сетке видно
/// сразу. Пустой строкой ниже summary не становится: если активности нет,
/// виджет не занимает место.
class _ActivityStrip extends StatelessWidget {
  final PlayHistory history;

  const _ActivityStrip({required this.history});

  static const double _cell = 11;
  static const double _gap = 3;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  Widget build(BuildContext context) {
    if (history.activity.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final window = history.windowDays > 0 ? history.windowDays : 91;
    final end = _dateOnly(DateTime.now());
    final start = end.subtract(Duration(days: window - 1));

    final secondsByDay = <DateTime, int>{
      for (final day in history.activity)
        _dateOnly(day.day.toLocal()): day.seconds,
    };
    var peak = 0;
    for (final value in secondsByDay.values) {
      if (value > peak) peak = value;
    }
    final playedDays = secondsByDay.length;

    // Клетки столбцами по неделям: начинаем с понедельника недели, в которую
    // попадает первый день окна.
    final lead = start.weekday - DateTime.monday;
    final weeks = <List<int>>[];
    for (var offset = 0; offset < window + lead; offset += 7) {
      final column = <int>[];
      for (var day = 0; day < 7; day++) {
        final index = offset + day - lead;
        if (index < 0 || index >= window) {
          column.add(-1); // вне окна
        } else {
          column.add(
            secondsByDay[_dateOnly(start.add(Duration(days: index)))] ?? 0,
          );
        }
      }
      weeks.add(column);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ActivityGrid(weeks: weeks, cell: _cell, gap: _gap, peak: peak),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trf('{p0} в игре', {'p0': _pluralDays(playedDays)}),
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trf('за {p0} · лучший день — {p1}', {'p0': _pluralDays(window), 'p1': PlaytimeFormatter.format(peak)}),
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityGrid extends StatelessWidget {
  final List<List<int>> weeks;
  final double cell;
  final double gap;
  final int peak;

  const _ActivityGrid({
    required this.weeks,
    required this.cell,
    required this.gap,
    required this.peak,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: weeks.length * (cell + gap) - gap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var week = 0; week < weeks.length; week++)
            Padding(
              // Последний столбец без отступа: иначе строка шире заданной
              // ширины на величину зазора.
              padding: EdgeInsets.only(right: week == weeks.length - 1 ? 0 : gap),
              child: SizedBox(
                width: cell,
                child: Column(
                  children: [
                    for (var day = 0; day < 7; day++)
                      Padding(
                        padding: EdgeInsets.only(bottom: day == 6 ? 0 : gap),
                        child: Container(
                          width: cell,
                          height: cell,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: _shade(scheme, weeks[week][day]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _shade(ColorScheme scheme, int seconds) {
    if (seconds < 0) return Colors.transparent;
    if (seconds == 0) return scheme.surfaceContainerHighest;
    final ratio = peak <= 0 ? 1.0 : (seconds / peak).clamp(0.25, 1.0);
    return scheme.primary.withValues(alpha: 0.25 + 0.75 * ratio);
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: Icon(
        icon,
        size: 16,
        color: selected
            ? Theme.of(context).colorScheme.onSecondaryContainer
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

// ============================================================================
//  СТРОКА ИСТОРИИ
// ============================================================================

class _HistoryCard extends StatelessWidget {
  final PlayHistoryEntry entry;
  final VoidCallback onOpen;

  const _HistoryCard({required this.entry, required this.onOpen});

  String get _lastPlayedLine {
    final at = entry.lastPlayedAt?.toLocal();
    if (at == null) return tr('давным-давно');
    // Не сверяемся с текстом formatRelativeTime: он локализирован, и сравнение
    // вида `rel == 'только что'` молча перестало бы срабатывать на любом языке
    // кроме русского.
    if (DateTime.now().difference(at).inMinutes < 1) {
      return tr('играл только что');
    }
    return trf('играл {p0} назад', {'p0': formatRelativeTime(at)});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 96,
                  height: 64,
                  child: MarketCoverImage(
                    url: entry.previewImageUrl,
                    fallbackColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    entry.authorName == null
                        ? const SizedBox.shrink()
                        : CosmeticNameText(
                            name: entry.authorName!,
                            def: cosmeticById(entry.authorNameStyle),
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                    const SizedBox(height: 6),
                    Text(
                      _lastPlayedLine,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (!entry.isPublished) ...[
                      const SizedBox(height: 6),
                      _RemovedBadge(status: entry.status),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Часы правее названия и тоже переменные: «999 ч. 59 мин.» на
              // узком телефоне выталкивало строку за край (переполнение
              // 9.4 px), поэтому колонка гибкая и с многоточием.
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      PlaytimeFormatter.format(entry.seconds),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // До миграции дней не было: показываем прочерк, а не выдумку.
                    if (entry.days > 0)
                      Text(
                        _pluralDays(entry.days),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Квест убрали из маркета — время в нём никуда не денется, но показать это
/// надо: иначе пустой экран деталей выглядит как баб истории.
class _RemovedBadge extends StatelessWidget {
  final String status;
  const _RemovedBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status == 'rejected' ? tr('отклонён модерацией') : tr('снят с публикации'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _pluralDays(int n) => '$n ${trp(['день', 'дня', 'дней'], n)}';

// ============================================================================
//  ПУСТО
// ============================================================================

class _EmptyHistory extends StatelessWidget {
  /// Свою пустую историю уместно объяснить, а чужую — констатировать: писать
  /// «здесь появятся квесты, которые вы открывали» про другого человека — врёт.
  final bool isMine;

  const _EmptyHistory({required this.isMine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_esports_rounded,
              size: 72,
              color: scheme.onSurfaceVariant.withOpacity(0.6),
            ),
            const SizedBox(height: 12),
            Text(
              isMine
                  ? tr('Здесь появятся квесты, которые вы открывали, и сколько времени в них провели.')
                  : tr('У этого профиля пока нет ни одного сыгранного квеста.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Время считается на сервере, а не в настройках одного устройства — история переживёт переустановку приложения.'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
