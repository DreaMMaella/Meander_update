import 'package:canvas_app/core/utils/error_text.dart';
import 'package:canvas_app/models/market_quest_model.dart';
import 'package:canvas_app/features/analytics/screens/author_analytics_screen.dart';
import 'package:canvas_app/features/analytics/screens/quest_analytics_screen.dart';
import 'package:canvas_app/features/profile/providers/profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  МОИ ПУБЛИКАЦИИ — Material You / Material 3 редизайн
// ============================================================================

class MyPublicationsScreen extends ConsumerStatefulWidget {
  const MyPublicationsScreen({super.key});

  @override
  ConsumerState<MyPublicationsScreen> createState() =>
      _MyPublicationsScreenState();
}

class _MyPublicationsScreenState extends ConsumerState<MyPublicationsScreen> {
  String? _userId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id');
    if (mounted) {
      setState(() {
        _userId = uid;
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return tr('только что');
    if (diff.inHours < 24) return trf('{p0} ч назад', {'p0': diff.inHours});
    if (diff.inDays < 7) return trf('{p0} дн назад', {'p0': diff.inDays});
    final year = date.year;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$day.$month.$year';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_userId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Мои публикации'))),
        body: _EmptyBlock(
          icon: Icons.login_rounded,
          text: tr('Войдите в аккаунт, чтобы увидеть свои публикации.'),
        ),
      );
    }

    final myPubsAsync = ref.watch(userPublicationsProvider(_userId!));

    return Scaffold(
      body: AdaptiveContent(
        maxWidth: 900,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () =>
                ref.refresh(userPublicationsProvider(_userId!).future),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverAppBar.large(
                  title: Text(tr('Мои публикации')),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.insights_rounded),
                      tooltip: tr('Статистика автора'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AuthorAnalyticsScreen(),
                        ),
                      ),
                    ),
                  ],
                  // Прозрачная подложка пропускала контент списка сквозь
                  // крупный заголовок — строки рисовались поверх него.
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                ),
                myPubsAsync.when(
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, _) => SliverFillRemaining(
                    child: _PubsErrorState(
                      error: err,
                      onRetry: () =>
                          ref.invalidate(userPublicationsProvider(_userId!)),
                    ),
                  ),
                  data: (quests) {
                    if (quests.isEmpty) {
                      return SliverFillRemaining(
                        child: _EmptyBlock(
                          icon: Icons.publish_outlined,
                          text: tr('Вы ещё ничего не публиковали'),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      sliver: SliverList.separated(
                        itemCount: quests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _PublicationCard(
                          quest: quests[i],
                          formattedDate: _formatDate(quests[i].createdAt),
                        ),
                      ),
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
//  КАРТОЧКА ПУБЛИКАЦИИ
// ============================================================================

class _PublicationCard extends StatelessWidget {
  final MarketQuest quest;
  final String formattedDate;
  const _PublicationCard({required this.quest, required this.formattedDate});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = _StatusInfo.fromStatus(quest.status ?? 'in_review', scheme);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 52,
                  decoration: BoxDecoration(
                    color: status.color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quest.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formattedDate,
                            style: textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: status.container,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(status.icon, color: status.onContainer, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        status.text,
                        style: textTheme.labelMedium?.copyWith(
                          color: status.onContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (quest.status == 'rejected' &&
                quest.moderatorComment != null &&
                quest.moderatorComment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.comment_rounded,
                          size: 14,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tr('Комментарий модератора'),
                          style: textTheme.labelMedium?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      quest.moderatorComment!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QuestAnalyticsScreen(
                      questId: quest.id,
                      title: quest.title,
                    ),
                  ),
                ),
                icon: const Icon(Icons.insights_rounded, size: 18),
                label: Text(tr('Статистика')),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  СТАТУС
// ============================================================================

class _StatusInfo {
  final String text;
  final Color color;
  final Color container;
  final Color onContainer;
  final IconData icon;

  const _StatusInfo({
    required this.text,
    required this.color,
    required this.container,
    required this.onContainer,
    required this.icon,
  });

  static _StatusInfo fromStatus(String status, ColorScheme scheme) {
    switch (status) {
      case 'published':
        return _StatusInfo(
          text: tr('Опубликовано'),
          color: scheme.primary,
          container: scheme.primaryContainer,
          onContainer: scheme.onPrimaryContainer,
          icon: Icons.check_circle_rounded,
        );
      case 'rejected':
        return _StatusInfo(
          text: tr('Отклонено'),
          color: scheme.error,
          container: scheme.errorContainer,
          onContainer: scheme.onErrorContainer,
          icon: Icons.cancel_rounded,
        );
      default:
        return _StatusInfo(
          text: tr('На проверке'),
          color: scheme.tertiary,
          container: scheme.tertiaryContainer,
          onContainer: scheme.onTertiaryContainer,
          icon: Icons.hourglass_top_rounded,
        );
    }
  }
}

// ============================================================================
//  ПУСТОЙ СТЕЙТ
// ============================================================================

class _EmptyBlock extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyBlock({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 72,
              color: scheme.onSurfaceVariant.withOpacity(0.6),
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  ОШИБКА ЗАГРУЗКИ ПУБЛИКАЦИЙ
// ============================================================================

/// Почему список не собрался — фразой и с рабочей кнопкой.
///
/// Ветка ошибки показывала только текст сбоя: без сети или при живом, но
/// медленном сервере человек попадал на экран с нулём действий, а спрятанный
/// выше pull-to-refresh он не находил. `userPublicationsProvider` —
/// autoDispose-футура, поэтому `invalidate` перевызывает запрос по-настоящему.
class _PubsErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _PubsErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 64,
            color: scheme.onSurfaceVariant.withOpacity(0.6),
          ),
          const SizedBox(height: 12),
          Text(
            tr('Публикации не загрузились'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              friendlyError(error),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('my-pubs-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(tr('Повторить')),
          ),
        ],
      ),
    );
  }
}
