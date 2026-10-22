import 'package:canvas_app/core/services/github_sync_service.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/quests/providers/quest_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuestSyncState {
  final GitHubSyncSettings settings;
  final bool isSyncing;
  final String? status;
  final double progress;
  final DateTime? lastSyncAt;
  final String? error;

  /// Пустой status = ещё ничего не происходило: текст строим под текущий язык.
  String get displayStatus => status ?? tr('Не синхронизировано');
  final int uploaded;
  final int downloaded;
  final int skipped;
  final int conflicts;
  final List<GitHubSyncConflict> conflictItems;
  final bool noChanges;

  const QuestSyncState({
    required this.settings,
    this.isSyncing = false,
    this.status,
    this.progress = 0,
    this.lastSyncAt,
    this.error,
    this.uploaded = 0,
    this.downloaded = 0,
    this.skipped = 0,
    this.conflicts = 0,
    this.conflictItems = const [],
    this.noChanges = false,
  });

  QuestSyncState copyWith({
    GitHubSyncSettings? settings,
    bool? isSyncing,
    String? status,
    double? progress,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    String? error,
    bool clearError = false,
    int? uploaded,
    int? downloaded,
    int? skipped,
    int? conflicts,
    List<GitHubSyncConflict>? conflictItems,
    bool? noChanges,
  }) {
    return QuestSyncState(
      settings: settings ?? this.settings,
      isSyncing: isSyncing ?? this.isSyncing,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      error: clearError ? null : (error ?? this.error),
      uploaded: uploaded ?? this.uploaded,
      downloaded: downloaded ?? this.downloaded,
      skipped: skipped ?? this.skipped,
      conflicts: conflicts ?? this.conflicts,
      conflictItems: conflictItems ?? this.conflictItems,
      noChanges: noChanges ?? this.noChanges,
    );
  }
}

class QuestSyncNotifier extends StateNotifier<QuestSyncState> {
  final Ref _ref;
  final GitHubSyncService _service;

  QuestSyncNotifier(this._ref, this._service)
    : super(const QuestSyncState(settings: GitHubSyncSettings.empty)) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _service.loadSettings();
    if (!mounted) return;
    state = state.copyWith(settings: settings);
  }

  Future<void> saveSettings(GitHubSyncSettings settings) async {
    await _service.saveSettings(settings);
    if (!mounted) return;
    state = state.copyWith(settings: settings, clearError: true);
  }

  Future<void> validateSettings(GitHubSyncSettings settings) async {
    await _service.validateConnection(settings);
    if (!mounted) return;
    state = state.copyWith(
      settings: settings,
      status: tr('GitHub подключён'),
      clearError: true,
    );
  }

  Future<void> syncNow() async {
    if (state.isSyncing) return;
    final settings = await _service.loadSettings();
    if (!settings.enabled) {
      state = state.copyWith(
        settings: settings,
        error: tr('Включите синхронизацию в настройках'),
      );
      return;
    }
    if (!settings.isConfigured) {
      state = state.copyWith(
        settings: settings,
        error: tr('Заполните токен/owner/repo/branch'),
      );
      return;
    }

      state = state.copyWith(
        settings: settings,
        isSyncing: true,
        progress: 0,
        status: tr('Подготовка синхронизации...'),
        clearError: true,
        uploaded: 0,
        downloaded: 0,
        skipped: 0,
        conflicts: 0,
        conflictItems: const [],
        noChanges: false,
      );

    try {
      final quests = await _ref.read(questsProvider.future);
      final result = await _service.syncQuests(
        settings: settings,
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

      _ref.invalidate(questsProvider);
      if (!mounted) return;
      state = state.copyWith(
        isSyncing: false,
        progress: 1,
        status: result.noChanges
            ? tr('Изменений нет, синхронизация не требуется')
            : tr('Синхронизация завершена'),
        lastSyncAt: DateTime.now(),
        uploaded: result.uploaded,
        downloaded: result.downloaded,
        skipped: result.skipped,
        conflicts: result.conflicts,
        conflictItems: result.conflictItems,
        noChanges: result.noChanges,
        clearError: true,
      );
    } catch (e) {
      print('❌ [Sync] error: $e');
      if (!mounted) return;
      state = state.copyWith(
        isSyncing: false,
        status: tr('Ошибка синхронизации'),
        error: e.toString(),
      );
    }
  }

  Future<void> resolveConflictUpload(String questId) async {
    if (state.isSyncing) return;
    final settings = await _service.loadSettings();
    if (!settings.enabled || !settings.isConfigured) return;

    final quests = await _ref.read(questsProvider.future);
    final quest = quests.cast().firstWhere(
      (q) => q.id == questId,
      orElse: () => Quest(id: questId, title: questId),
    );

    state = state.copyWith(
      isSyncing: true,
      progress: 0,
      status: tr('Разрешение конфликта: загрузка локальной версии...'),
      clearError: true,
    );

    try {
      await _service.forceUploadQuest(
        settings: settings,
        questId: questId,
        questTitle: quest.title,
        onProgress: (p) {
          if (!mounted) return;
          state = state.copyWith(status: p.message, progress: p.progress);
        },
      );
      final updated = state.conflictItems.where((c) => c.questId != questId).toList();
      if (!mounted) return;
      state = state.copyWith(
        isSyncing: false,
        progress: 1,
        status: tr('Конфликт решён: локальная версия загружена'),
        conflictItems: updated,
        conflicts: updated.length,
        clearError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isSyncing: false,
        status: tr('Ошибка разрешения конфликта'),
        error: e.toString(),
      );
    }
  }

  Future<void> resolveConflictDownload(String questId) async {
    if (state.isSyncing) return;
    final settings = await _service.loadSettings();
    if (!settings.enabled || !settings.isConfigured) return;

    state = state.copyWith(
      isSyncing: true,
      progress: 0,
      status: tr('Разрешение конфликта: загрузка версии из GitHub...'),
      clearError: true,
    );

    try {
      await _service.forceDownloadQuest(
        settings: settings,
        questId: questId,
        onProgress: (p) {
          if (!mounted) return;
          state = state.copyWith(status: p.message, progress: p.progress);
        },
      );
      _ref.invalidate(questsProvider);
      final updated = state.conflictItems.where((c) => c.questId != questId).toList();
      if (!mounted) return;
      state = state.copyWith(
        isSyncing: false,
        progress: 1,
        status: tr('Конфликт решён: версия из GitHub скачана'),
        conflictItems: updated,
        conflicts: updated.length,
        clearError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isSyncing: false,
        status: tr('Ошибка разрешения конфликта'),
        error: e.toString(),
      );
    }
  }
}

final githubSyncServiceProvider = Provider<GitHubSyncService>((ref) {
  return GitHubSyncService();
});

final questSyncProvider = StateNotifierProvider<QuestSyncNotifier, QuestSyncState>((
  ref,
) {
  return QuestSyncNotifier(ref, ref.read(githubSyncServiceProvider));
});
