import 'package:canvas_app/core/services/cloud_sync_service.dart';
import 'package:canvas_app/features/quests/providers/cloud_sync_provider.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

/// =============================================================================
///   Экран настроек Meander Cloud Sync — Material 3.
/// =============================================================================

class CloudSyncSettingsScreen extends ConsumerStatefulWidget {
  const CloudSyncSettingsScreen({super.key});

  @override
  ConsumerState<CloudSyncSettingsScreen> createState() =>
      _CloudSyncSettingsScreenState();
}

class _CloudSyncSettingsScreenState
    extends ConsumerState<CloudSyncSettingsScreen> {
  bool _didInitialLoad = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cloudSyncProvider.notifier).refreshQuota();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(cloudSyncProvider);
    final remoteAsync = ref.watch(cloudSyncRemoteListProvider);

    if (!_didInitialLoad && state.quota == null && !state.isLoadingQuota) {
      _didInitialLoad = true;
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Meander Cloud'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: AdaptiveContent(
        maxWidth: 720,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(cloudSyncProvider.notifier).refreshQuota();
            ref.invalidate(cloudSyncRemoteListProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _QuotaCard(state: state),
              const SizedBox(height: 16),
              if (state.error != null) ...[
                _ErrorBanner(message: state.error!),
                const SizedBox(height: 16),
              ],
              if (state.quota != null &&
                  state.quota!.upgradeHints.isNotEmpty) ...[
                _UpgradeHintsCard(hints: state.quota!.upgradeHints),
                const SizedBox(height: 16),
              ],
              _SyncActionsCard(state: state),
              const SizedBox(height: 16),
              _RemoteListSection(async: remoteAsync),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  QuotaCard
// ============================================================================

class _QuotaCard extends StatelessWidget {
  final CloudSyncState state;
  const _QuotaCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quota = state.quota;

    if (state.isLoadingQuota && quota == null) {
      return _glass(
        context,
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (quota == null) {
      return _glass(
        context,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(tr('Не удалось получить информацию о квоте.')),
        ),
      );
    }

    final tierLabel = _tierLabel(quota.tier);
    final usageRatio = _isUnlimited(quota.maxBytes) ? 0.0 : quota.bytesUsage;
    final used = _formatBytes(quota.usedBytes);
    final max = _isUnlimited(quota.maxBytes)
        ? '∞'
        : _formatBytes(quota.maxBytes);
    final maxQuestsLabel = _isUnlimitedCount(quota.maxQuests)
        ? '∞'
        : quota.maxQuests.toString();
    final maxQuestBytesLabel = _isUnlimited(quota.maxQuestBytes)
        ? '∞'
        : _formatBytes(quota.maxQuestBytes);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.alphaBlend(
              scheme.secondaryContainer.withOpacity(0.6),
              scheme.primaryContainer,
            ),
          ],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_rounded, color: scheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Text(
                'Meander Cloud',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.onPrimaryContainer.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tierLabel,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (quota.hasAccess) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: usageRatio,
                minHeight: 10,
                color: scheme.onPrimaryContainer,
                backgroundColor: scheme.onPrimaryContainer.withOpacity(0.18),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              trf('{used} / {max}  ·  {p0} из {maxQuestsLabel} квестов', {'used': used, 'max': max, 'p0': quota.usedQuests, 'maxQuestsLabel': maxQuestsLabel}),
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (quota.usedRefs > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _isUnlimitedCount(quota.maxRefs)
                      ? trf('Маркет-ссылок: {p0}', {'p0': quota.usedRefs})
                      : trf('Маркет-ссылок: {p0} (из {p1})', {'p0': quota.usedRefs, 'p1': quota.maxRefs}),
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withOpacity(0.85),
                    fontSize: 12.5,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              trf('Макс. размер одного квеста: {maxQuestBytesLabel}', {'maxQuestBytesLabel': maxQuestBytesLabel}),
              style: TextStyle(
                color: scheme.onPrimaryContainer.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ] else ...[
            Text(
              tr('У вас пока нет доступа к облачному хранилищу.'),
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Опубликуйте свой первый квест или ознакомьтесь с подсказками ниже.'),
              style: TextStyle(
                color: scheme.onPrimaryContainer.withOpacity(0.8),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// MAX_SAFE_INTEGER (9007199254740991) или близкие к нему значения,
  /// которые приходят с бэка для admin/безлимитного tier, отображаем как «∞».
  static bool _isUnlimited(int bytes) => bytes >= 1024 * 1024 * 1024 * 1024;
  static bool _isUnlimitedCount(int count) => count >= 100000;

  static String _tierLabel(CloudSyncTier t) {
    switch (t) {
      case CloudSyncTier.starter:
        return 'STARTER';
      case CloudSyncTier.free:
        return 'FREE';
      case CloudSyncTier.creator:
        return 'CREATOR';
      case CloudSyncTier.pro:
        return 'PRO';
      case CloudSyncTier.admin:
        return 'ADMIN';
      case CloudSyncTier.none:
        return tr('НЕТ');
    }
  }

  static String _formatBytes(int b) {
    if (b <= 0) return '0';
    if (b >= 1024 * 1024 * 1024) {
      return trf('{p0} ГБ', {'p0': (b / (1024 * 1024 * 1024)).toStringAsFixed(1)});
    }
    if (b >= 1024 * 1024) {
      return trf('{p0} МБ', {'p0': (b / (1024 * 1024)).toStringAsFixed(1)});
    }
    if (b >= 1024) {
      return trf('{p0} КБ', {'p0': (b / 1024).toStringAsFixed(1)});
    }
    return trf('{p0} Б', {'p0': b});
  }

  static Widget _glass(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

// ============================================================================
//  UpgradeHintsCard
// ============================================================================

class _UpgradeHintsCard extends StatelessWidget {
  final List<CloudUpgradeHint> hints;
  const _UpgradeHintsCard({required this.hints});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  tr('Как получить больше места'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          for (final h in hints) _HintTile(hint: h),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _HintTile extends StatelessWidget {
  final CloudUpgradeHint hint;
  const _HintTile({required this.hint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hint.text,
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
                if (hint.progress != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: hint.progress!.clamp(0, 1),
                      minHeight: 4,
                      color: scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  SyncActionsCard
// ============================================================================

class _SyncActionsCard extends ConsumerWidget {
  final CloudSyncState state;
  const _SyncActionsCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isSyncing = state.isSyncing;
    final hasAccess = state.hasAccess;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSyncing ? Icons.sync_rounded : Icons.sync_alt_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.displayStatus,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (state.lastSyncAt != null && !isSyncing)
                Text(
                  _ago(state.lastSyncAt!),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
          if (isSyncing) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress <= 0 ? null : state.progress,
                minHeight: 4,
                color: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (isSyncing || !hasAccess)
                  ? null
                  : () => ref.read(cloudSyncProvider.notifier).syncNow(),
              icon: Icon(
                isSyncing
                    ? Icons.hourglass_top_rounded
                    : Icons.cloud_sync_rounded,
              ),
              label: Text(
                isSyncing ? tr('Идёт синхронизация…') : tr('Синхронизировать сейчас'),
              ),
            ),
          ),
          if (state.lastSummary != null) ...[
            const SizedBox(height: 12),
            _SummaryRow(summary: state.lastSummary!),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return tr('только что');
    if (diff.inMinutes < 60) return trf('{p0} мин назад', {'p0': diff.inMinutes});
    if (diff.inHours < 24) return trf('{p0} ч назад', {'p0': diff.inHours});
    return trf('{p0} дн назад', {'p0': diff.inDays});
  }
}

class _SummaryRow extends StatelessWidget {
  final CloudSyncSummary summary;
  const _SummaryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[
      _summaryChip(
        context,
        icon: Icons.upload_rounded,
        label: '↑ ${summary.uploaded}',
        tooltip: tr('Загружено'),
      ),
      _summaryChip(
        context,
        icon: Icons.link_rounded,
        label: '⇄ ${summary.refLinked}',
        tooltip: tr('Связано с маркетом (бесплатно)'),
      ),
      _summaryChip(
        context,
        icon: Icons.download_rounded,
        label: '↓ ${summary.downloaded}',
        tooltip: tr('Скачано'),
      ),
      _summaryChip(
        context,
        icon: Icons.check_circle_outline_rounded,
        label: '✓ ${summary.skipped}',
        tooltip: tr('Пропущено (актуально)'),
      ),
      if (summary.quotaFull > 0)
        _summaryChip(
          context,
          icon: Icons.hourglass_bottom_rounded,
          label: '⏳ ${summary.quotaFull}',
          tooltip:
              tr('Не поместились в квоту. Освободите место или повысьте уровень.'),
          color: scheme.tertiaryContainer,
          fg: scheme.onTertiaryContainer,
        ),
      if (summary.failed.isNotEmpty)
        _summaryChip(
          context,
          icon: Icons.error_outline_rounded,
          label: '× ${summary.failed.length}',
          tooltip: tr('Нажмите, чтобы увидеть ошибки'),
          color: scheme.errorContainer,
          fg: scheme.onErrorContainer,
          onTap: () => _showFailedSheet(context, summary.failed),
        ),
    ];

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _summaryChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tooltip,
    Color? color,
    Color? fg,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg ?? scheme.onSurface),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg ?? scheme.onSurface,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    final body = onTap == null
        ? chip
        : Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: chip,
            ),
          );
    return Tooltip(message: tooltip, child: body);
  }

  void _showFailedSheet(BuildContext context, List<String> failed) {
    final scheme = Theme.of(context).colorScheme;
    showAdaptiveSheet(
      context: context,
      scrollable: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: scheme.error),
                  const SizedBox(width: 10),
                  Text(
                    trf('Ошибки синхронизации ({p0})', {'p0': failed.length}),
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: failed.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: scheme.outlineVariant, height: 16),
                  itemBuilder: (_, i) => Text(
                    failed[i],
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Закрыть')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  Error banner
// ============================================================================

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  Remote list
// ============================================================================

class _RemoteListSection extends ConsumerWidget {
  final AsyncValue<List<CloudQuestEntry>> async;
  const _RemoteListSection({required this.async});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.folder_special_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                tr('В облаке'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: tr('Обновить'),
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.invalidate(cloudSyncRemoteListProvider),
              ),
            ],
          ),
        ),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(trf('Не удалось загрузить список: {p0}', {'p0': friendlyError(e)})),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    tr('В облаке пока ничего нет — нажмите «Синхронизировать сейчас».'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              );
            }
            return Column(
              children: [for (final e in list) _RemoteQuestTile(entry: e)],
            );
          },
        ),
      ],
    );
  }
}

class _RemoteQuestTile extends ConsumerWidget {
  final CloudQuestEntry entry;
  const _RemoteQuestTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isRef = entry.isMarketRef;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isRef
                      ? scheme.tertiaryContainer
                      : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isRef ? Icons.shop_rounded : Icons.cloud_done_rounded,
                  size: 18,
                  color: isRef
                      ? scheme.onTertiaryContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRef
                          ? trf('Маркет-ссылка{p0}', {'p0': entry.marketVersion != null ? ' · v${entry.marketVersion}' : ''})
                          : _QuotaCard._formatBytes(entry.size),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('Удалить из облака'),
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
                onPressed: () async {
                  final confirm = await showAppDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(tr('Удалить из облака?')),
                      content: Text(
                        trf('Запись «{p0}» будет удалена из облака. Локально квест останется на устройстве.', {'p0': entry.title}),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(tr('Отмена')),
                        ),
                        FilledButton.tonal(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.errorContainer,
                            foregroundColor: scheme.onErrorContainer,
                          ),
                          child: Text(tr('Удалить')),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await ref
                        .read(cloudSyncProvider.notifier)
                        .deleteRemoteQuest(entry.questId);
                    ref.invalidate(cloudSyncRemoteListProvider);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
