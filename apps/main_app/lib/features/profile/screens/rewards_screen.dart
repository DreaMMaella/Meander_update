import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';
import 'package:canvas_app/features/profile/providers/rewards_provider.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

// ============================================================================
//  НАГРАДЫ — оформление за то, что человек реально делает в Meander
//
//  Экран не настраивает решительно ничего: права выдаёт сервер по серверным
//  же метрикам. Здесь только прогресс и напоминание, где потом надеть.
// ============================================================================

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  bool _greeted = false;

  void _greet(List<RewardRule> rules) {
    if (_greeted || rules.isEmpty || !mounted) return;
    _greeted = true;
    final names = rules.map((r) => r.title).join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trf('Награда ваша: {names}. Надеть — в «Оформлении профиля»', {'names': names})),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(rewardsProvider);

    return Scaffold(
      body: AdaptiveContent(
        maxWidth: 900,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(rewardsProvider.future),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverAppBar.large(
                  title: Text(tr('Награды')),
                  // Прозрачная подложка пропускала контент списка сквозь
                  // крупный заголовок — строки рисовались поверх него.
                  backgroundColor: scheme.surface,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                ),
                async.when(
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, _) => SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          trf('Награды не загрузились. {p0}', {'p0': friendlyError(err)}),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ),
                  ),
                  data: (list) {
                    if (list.justGranted.isNotEmpty) {
                      final rules = list.justGranted
                          .map(list.byId)
                          .whereType<RewardRule>()
                          .toList();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _greet(rules);
                      });
                    }
                    return SliverList(
                      delegate: SliverChildListDelegate([
                        Padding(
                          padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                          child: Text(
                            tr('Оформление здесь не продаётся и не выбирается вручную: сервер выдаёт его за дни подряд, игровые часы, отзывы и скачанные чужие квесты. Всё уже полученное надевается в «Оформлении профиля».'),
                          ),
                        ),
                        if (list.rules.isEmpty)
                          _RewardsUnavailable()
                        else
                          for (final metric in RewardMetric.values)
                            if (list.byMetric(metric).isNotEmpty) ...[
                                  _MetricHeader(metric: metric, list: list),
                                  for (final rule in list.byMetric(metric))
                                    _RewardCard(rule: rule),
                                ],
                        const SizedBox(height: 32),
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

class _MetricHeader extends StatelessWidget {
  const _MetricHeader({required this.metric, required this.list});

  final RewardMetric metric;
  final RewardList list;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rules = list.byMetric(metric);
    final claimed = rules.where((r) => r.claimed).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Text(
            metric.label,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          Text(
            trf('{claimed} из {p0}', {'claimed': claimed, 'p0': rules.length}),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({required this.rule});

  final RewardRule rule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = rule.claimed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      rule.title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StateBadge(done: done, ratio: rule.ratio),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                rule.hint,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
              if (!done) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: rule.ratio,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trf('{p0} из {p1} · осталось {p2}', {'p0': rule.current, 'p1': rule.threshold, 'p2': rule.remaining}),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final def in rule.cosmetics)
                    SizedBox(
                      width: 96,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CosmeticPreview(def: def, height: 44),
                          const SizedBox(height: 4),
                          Text(
                            def.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            def.tier.title,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.done, required this.ratio});

  final bool done;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = done ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(done ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.card_giftcard_rounded : Icons.lock_outline_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            done ? tr('Ваша') : (ratio > 0 ? tr('Растёт') : tr('Закрыто')),
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Пустой ответ сервера — это ещё не «наград нет вообще»: чаще всего значит,
/// что прод ещё не догнал новую версию бэкенда.
class _RewardsUnavailable extends StatelessWidget {
  const _RewardsUnavailable();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        tr('Список наград пока пуст. Как только сервер начнёт их считать, здесь появятся прогресс и подарки.'),
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
    );
  }
}
