import 'package:canvas_app/core/services/github_sync_service.dart';
import 'package:canvas_app/features/quests/providers/quest_sync_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

class QuestSyncSettingsScreen extends ConsumerStatefulWidget {
  const QuestSyncSettingsScreen({super.key});

  @override
  ConsumerState<QuestSyncSettingsScreen> createState() =>
      _QuestSyncSettingsScreenState();
}

class _QuestSyncSettingsScreenState
    extends ConsumerState<QuestSyncSettingsScreen> {
  final _tokenController = TextEditingController();
  final _ownerController = TextEditingController();
  final _repoController = TextEditingController();
  final _branchController = TextEditingController();
  final _rootController = TextEditingController();

  bool _enabled = false;
  bool _obscureToken = true;
  bool _initialized = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _ownerController.dispose();
    _repoController.dispose();
    _branchController.dispose();
    _rootController.dispose();
    super.dispose();
  }

  void _initFromState(GitHubSyncSettings settings) {
    if (_initialized) return;
    _enabled = settings.enabled;
    _tokenController.text = settings.token;
    _ownerController.text = settings.owner;
    _repoController.text = settings.repo;
    _branchController.text = settings.branch;
    _rootController.text = settings.rootPath;
    _initialized = true;
  }

  GitHubSyncSettings _collect() {
    return GitHubSyncSettings(
      enabled: _enabled,
      token: _tokenController.text.trim(),
      owner: _ownerController.text.trim(),
      repo: _repoController.text.trim(),
      branch: _branchController.text.trim().isEmpty
          ? 'main'
          : _branchController.text.trim(),
      rootPath: _rootController.text.trim().isEmpty
          ? 'meander-sync'
          : _rootController.text.trim(),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final notifier = ref.read(questSyncProvider.notifier);
    final settings = _collect();
    try {
      await notifier.saveSettings(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Настройки синхронизации сохранены')),
          backgroundColor: Color(0xFF00C853),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trf('Ошибка сохранения: {p0}', {'p0': friendlyError(e)})),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _validate() async {
    final notifier = ref.read(questSyncProvider.notifier);
    final settings = _collect();
    await notifier.saveSettings(settings);
    await notifier.validateSettings(settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Подключение к GitHub успешно')),
        backgroundColor: Color(0xFF00C853),
      ),
    );
  }

  Future<void> _syncNow() async {
    await _save();
    await ref.read(questSyncProvider.notifier).syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(questSyncProvider);
    _initFromState(state.settings);

    final lastSyncLabel = state.lastSyncAt == null
        ? '—'
        : '${state.lastSyncAt!.day.toString().padLeft(2, '0')}.'
              '${state.lastSyncAt!.month.toString().padLeft(2, '0')}.'
              '${state.lastSyncAt!.year} '
              '${state.lastSyncAt!.hour.toString().padLeft(2, '0')}:'
              '${state.lastSyncAt!.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: Text(tr('Синхронизация квестов')),
      ),
      body: AdaptiveContent(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2330),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Как настроить GitHub Sync (для новичков)'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    tr('1. Создайте репозиторий на GitHub (можно приватный).'),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    tr('2. В GitHub откройте Settings -> Developer settings -> Personal access tokens -> Tokens (classic).'),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    tr('3. Создайте токен с правом repo (для private) или public_repo (для public).'),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    tr('4. Введите Token, Owner (ваш логин), Repository, Branch (обычно main).'),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    tr('5. Нажмите "Проверить подключение", затем "Синхронизировать сейчас".'),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 8),
                  Text(
                    tr('Важно: этот MVP работает в безопасном режиме — квесты в облаке не удаляются автоматически, даже если локально их стало 0.'),
                    style: TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Включить GitHub sync'),
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                        activeColor: const Color(0xFF00C853),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('MVP: PAT токен + синк в ваш GitHub репозиторий без отдельного сервера.'),
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _input(
              label: 'GitHub Token (PAT)',
              controller: _tokenController,
              obscure: _obscureToken,
              suffix: IconButton(
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
                icon: Icon(
                  _obscureToken ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white70,
                ),
              ),
            ),
            _input(label: 'Owner', controller: _ownerController),
            _input(label: 'Repository', controller: _repoController),
            _input(label: 'Branch', controller: _branchController),
            _input(
              label: 'Path Prefix',
              controller: _rootController,
              hint: 'meander-sync',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sync, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.displayStatus,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  if (state.isSyncing) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: state.progress <= 0 ? null : state.progress,
                      color: const Color(0xFF00C853),
                      backgroundColor: Colors.white12,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    trf('Последняя синхронизация: {lastSyncLabel}', {'lastSyncLabel': lastSyncLabel}),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  if (state.error != null && state.error!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SelectableText(
                              state.error!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: tr('Скопировать ошибку'),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: state.error ?? ''),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(tr('Ошибка скопирована')),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.copy,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!state.isSyncing &&
                      (state.uploaded > 0 ||
                          state.downloaded > 0 ||
                          state.skipped > 0 ||
                          state.conflicts > 0))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        trf('Загружено: {p0}, скачано: {p1}, без изменений: {p2}, конфликты: {p3}', {'p0': state.uploaded, 'p1': state.downloaded, 'p2': state.skipped, 'p3': state.conflicts}),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (!state.isSyncing && state.conflicts > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Есть конфликты. Для безопасности синк не перезаписывает удалённые/изменённые в облаке квесты.'),
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...state.conflictItems.map((c) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2330),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.title,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: state.isSyncing
                                              ? null
                                              : () => ref
                                                    .read(
                                                      questSyncProvider
                                                          .notifier,
                                                    )
                                                    .resolveConflictUpload(
                                                      c.questId,
                                                    ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            side: const BorderSide(
                                              color: Colors.white24,
                                            ),
                                            minimumSize: const Size.fromHeight(
                                              40,
                                            ),
                                          ),
                                          child: Text(
                                            tr('Оставить локальный'),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: state.isSyncing
                                              ? null
                                              : () => ref
                                                    .read(
                                                      questSyncProvider
                                                          .notifier,
                                                    )
                                                    .resolveConflictDownload(
                                                      c.questId,
                                                    ),
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(
                                              40,
                                            ),
                                            backgroundColor: const Color(
                                              0xFF2E7D32,
                                            ),
                                          ),
                                          child: Text(
                                            tr('Оставить облачный'),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: state.isSyncing ? null : _validate,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: Text(tr('Проверить подключение')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: state.isSyncing || _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                    child: Text(tr('Сохранить')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.isSyncing ? null : _syncNow,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFF00C853),
                  foregroundColor: Colors.black,
                ),
                icon: state.isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.cloud_sync),
                label: Text(
                  state.isSyncing
                      ? tr('Синхронизация...')
                      : tr('Синхронизировать сейчас'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white38),
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00C853)),
          ),
        ),
      ),
    );
  }
}
