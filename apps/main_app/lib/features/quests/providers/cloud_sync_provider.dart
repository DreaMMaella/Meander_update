import 'dart:async';

import 'package:canvas_app/core/services/cloud_sync_service.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/quests/providers/quest_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// =============================================================================
///   Состояние Meander Cloud Sync для UI.
/// =============================================================================

class CloudSyncState {
  final bool isLoadingQuota;
  final CloudQuotaInfo? quota;
  final bool isSyncing;
  final double progress;
  final String? status;
  final String? error;
  final CloudSyncSummary? lastSummary;
  final DateTime? lastSyncAt;

  /// Пустой status = ещё ничего не происходило: текст строим под текущий язык.
  String get displayStatus => status ?? tr('Готово');

  const CloudSyncState({
    this.isLoadingQuota = false,
    this.quota,
    this.isSyncing = false,
    this.progress = 0,
    this.status,
    this.error,
    this.lastSummary,
    this.lastSyncAt,
  });

  bool get hasAccess => quota?.hasAccess ?? false;

  CloudSyncState copyWith({
    bool? isLoadingQuota,
    CloudQuotaInfo? quota,
    bool? isSyncing,
    double? progress,
    String? status,
    String? error,
    bool clearError = false,
    CloudSyncSummary? lastSummary,
    DateTime? lastSyncAt,
  }) {
    return CloudSyncState(
      isLoadingQuota: isLoadingQuota ?? this.isLoadingQuota,
      quota: quota ?? this.quota,
      isSyncing: isSyncing ?? this.isSyncing,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      lastSummary: lastSummary ?? this.lastSummary,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

class CloudSyncNotifier extends StateNotifier<CloudSyncState> {
  final Ref _ref;
  final CloudSyncService _service;

  CloudSyncNotifier(this._ref, this._service) : super(const CloudSyncState());

  Future<void> refreshQuota() async {
    state = state.copyWith(isLoadingQuota: true, clearError: true);
    try {
      final q = await _service.fetchQuota();
      state = state.copyWith(quota: q, isLoadingQuota: false, clearError: true);
    } catch (e) {
      state = state.copyWith(isLoadingQuota: false, error: e.toString());
    }
  }

  Future<void> syncNow() async {
    if (state.isSyncing) return;
    state = state.copyWith(
      isSyncing: true,
      progress: 0,
      status: tr('Подготовка…'),
      clearError: true,
    );
    try {
      final quests = await _ref.read(questsProvider.future);
      final summary = await _service.syncAll(
        localQuests: quests,
        onProgress: (p) {
          if (!mounted) return;
          state = state.copyWith(
            status: p.message,
            progress: p.progress,
            clearError: true,
          );
        },
      );
      if (!mounted) return;
      _ref.invalidate(questsProvider);
      state = state.copyWith(
        isSyncing: false,
        progress: 1.0,
        status: summary.noChanges ? tr('Изменений нет') : tr('Готово'),
        lastSummary: summary,
        lastSyncAt: DateTime.now(),
        clearError: true,
      );
      // Обновим квоту после успешной синхронизации
      unawaited(refreshQuota());
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isSyncing: false,
        status: tr('Ошибка'),
        error: e.toString(),
      );
    }
  }

  Future<void> deleteRemoteQuest(String questId) async {
    try {
      await _service.deleteRemote(questId);
      await refreshQuota();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  return CloudSyncService();
});

final cloudSyncProvider =
    StateNotifierProvider<CloudSyncNotifier, CloudSyncState>((ref) {
      return CloudSyncNotifier(ref, ref.read(cloudSyncServiceProvider));
    });

/// Список квестов на сервере (отдельный provider для UI настроек).
final cloudSyncRemoteListProvider = FutureProvider<List<CloudQuestEntry>>((
  ref,
) async {
  final svc = ref.read(cloudSyncServiceProvider);
  return svc.listRemoteQuests();
});
