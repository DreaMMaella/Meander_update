import 'package:canvas_app/features/hub/screens/preset_details_screen.dart';
import 'package:canvas_app/features/hub/widgets/preset_market.dart';
import 'package:canvas_app/features/market/widgets/market_widgets.dart';
import 'package:canvas_app/shared/widgets/catalog_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  ЛОКАЛЬНЫЕ ПРЕСЕТЫ
//
//  Пресеты кнопок, которые лежат в config.json квестов на этом устройстве —
//  свои и принесённые из скачанных квестов. Это НЕ контент маркета: у них нет
//  id публикации, поэтому их не за что ни удалить, ни смодерировать, ни
//  пожаловаться. В хабе (hub_screen) показываются только серверные ресурсы,
//  а локальное живёт здесь — рядом с локальными квестами («Мои»).
// ============================================================================

enum _PresetFilter { all, own, fromMarket }

class LocalPresetsScreen extends ConsumerStatefulWidget {
  const LocalPresetsScreen({super.key});

  @override
  ConsumerState<LocalPresetsScreen> createState() => _LocalPresetsScreenState();
}

class _LocalPresetsScreenState extends ConsumerState<LocalPresetsScreen> {
  _PresetFilter _filter = _PresetFilter.all;
  bool _publishing = false;

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() => _publishing = true);
    try {
      await showPresetMarketSheet(
        context,
        onOpen: (entry) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PresetDetailsScreen(entry: entry)),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presetsAsync = ref.watch(allQuestPresetsProvider);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: AdaptiveContent(
        maxWidth: 900,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(allQuestPresetsProvider),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  floating: true,
                  pinned: false,
                  snap: true,
                  toolbarHeight: 64,
                  title: Text(
                    tr('Локальные пресеты'),
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                SliverToBoxAdapter(
                  child: CatalogSectionHeader(
                    title: tr('Стили кнопок на устройстве'),
                    icon: Icons.smart_button_rounded,
                    subtitle:
                        tr('Из config.json ваших и скачанных квестов. Опубликованные версии лежат в Хабе, в разделе «Пресеты маркета».'),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: _FilterRow(
                    selected: _filter,
                    onSelected: (value) => setState(() => _filter = value),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                // SliverLayoutBuilder, не LayoutBuilder: внутри CustomScrollView
                // у сливеров нет box-ограничений, и box-виджет здесь роняет вьюпорт.
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    return presetsAsync.when(
                      loading: () => CatalogGridShimmer(width: width),
                      error: (e, _) => SliverToBoxAdapter(
                        child: MarketErrorBlock(
                          error: e,
                          onRetry: () =>
                              ref.invalidate(allQuestPresetsProvider),
                        ),
                      ),
                      data: (all) {
                        final presets = switch (_filter) {
                          _PresetFilter.all => all,
                          _PresetFilter.own =>
                            all.where((p) => p.isOwn).toList(),
                          _PresetFilter.fromMarket =>
                            all.where((p) => !p.isOwn).toList(),
                        };
                        if (presets.isEmpty) {
                          return SliverToBoxAdapter(
                            child: MarketEmptyState(
                              message:
                                  tr('Пресетов нет.\nСоздайте их в редакторе квеста: Настройки квеста → Кастомные кнопки'),
                            ),
                          );
                        }
                        return CatalogSliverGrid(
                          itemCount: presets.length,
                          width: width,
                          itemBuilder: (context, i) => RepaintBoundary(
                            child: _PresetCard(
                              entry: presets[i],
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PresetDetailsScreen(entry: presets[i]),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: _publishing ? null : _publish,
        icon: _publishing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_upload_rounded),
        label: Text(tr('Опубликовать пресет')),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final _PresetFilter selected;
  final ValueChanged<_PresetFilter> onSelected;

  const _FilterRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    Widget chip(_PresetFilter value, String label) => Padding(
      padding: const EdgeInsets.only(left: 16),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_PresetFilter.all, tr('Все')),
          chip(_PresetFilter.own, tr('Мои')),
          chip(_PresetFilter.fromMarket, tr('Из скачанных квестов')),
        ],
      ),
    );
  }
}

/// Карточка пресета — тот же вид, что у карточки ресурса в Хабе, но с бейджем
/// «ваш» / «из маркета»: чужой пресет опубликовать от своего имени нельзя.
class _PresetCard extends StatelessWidget {
  final QuestPresetEntry entry;
  final VoidCallback onTap;

  const _PresetCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 11,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF141B2B), Color(0xFF0D1220)],
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PresetButtonPreview(
                          style: entry.config,
                          questIdOrNull: entry.questId,
                          text: entry.presetName,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: MarketBadge(
                      label: entry.isOwn ? tr('ВАШ') : tr('ИЗ МАРКЕТА'),
                      background: scheme.surface.withValues(alpha: 0.88),
                      foreground: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.presetName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.questTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
