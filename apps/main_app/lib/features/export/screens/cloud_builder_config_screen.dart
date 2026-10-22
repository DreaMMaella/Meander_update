import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:canvas_app/features/export/providers/cloud_builder_provider.dart';
import 'package:canvas_app/features/export/screens/cloud_builder_progress_screen.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:mnd_core/utils/quest_paths.dart';

class CloudBuilderConfigScreen extends ConsumerStatefulWidget {
  final String questId;
  final String? defaultAppName;

  const CloudBuilderConfigScreen({
    super.key,
    required this.questId,
    this.defaultAppName,
  });

  @override
  ConsumerState<CloudBuilderConfigScreen> createState() =>
      _CloudBuilderConfigScreenState();
}

class _CloudBuilderConfigScreenState
    extends ConsumerState<CloudBuilderConfigScreen> {
  late final TextEditingController _appNameCtrl;
  late final TextEditingController _packageCtrl;
  String _platform = 'android-apk';
  String? _iconPath;

  @override
  void initState() {
    super.initState();
    _appNameCtrl = TextEditingController(
      text: widget.defaultAppName ?? tr('Мой квест'),
    );
    _packageCtrl = TextEditingController(
      text: _sanitizePackage(widget.defaultAppName ?? 'myquest'),
    );
    _autoDetectIcon();
  }

  Future<void> _autoDetectIcon() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final questDir = p.join(
        appDir.path,
        QuestPaths.questsDir,
        widget.questId,
      );
      final configFile = File(p.join(questDir, 'config.json'));
      if (await configFile.exists()) {
        final assetsDir = Directory(p.join(questDir, 'res'));
        if (await assetsDir.exists()) {
          final candidates = <String>[];
          await for (final entry in assetsDir.list(recursive: true)) {
            if (entry is File) {
              final ext = p.extension(entry.path).toLowerCase();
              if (ext == '.png' || ext == '.jpg' || ext == '.jpeg') {
                final name = p
                    .basenameWithoutExtension(entry.path)
                    .toLowerCase();
                if (name.contains('cover') ||
                    name.contains('icon') ||
                    name.contains('logo')) {
                  candidates.add(entry.path);
                }
              }
            }
          }
          if (candidates.isNotEmpty && mounted) {
            setState(() => _iconPath = candidates.first);
          }
        }
      }
    } catch (_) {}
  }

  String _sanitizePackage(String name) {
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '')
        .replaceAll(RegExp(r'^[^a-z]+'), '');
    return 'com.example.${sanitized.isEmpty ? 'myquest' : sanitized}';
  }

  @override
  void dispose() {
    _appNameCtrl.dispose();
    _packageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked != null) {
      setState(() => _iconPath = picked.path);
    }
  }

  Future<void> _logoutGitHub() async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Выйти из GitHub?')),
        content: Text(
          tr('При следующей сборке потребуется заново авторизоваться.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Выйти')),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('github_builder_token');
      ref.read(cloudBuilderProvider.notifier).reset();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Вы вышли из GitHub')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _startBuild() {
    final appName = _appNameCtrl.text.trim();
    final packageName = _packageCtrl.text.trim();

    if (appName.isEmpty || packageName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Заполните все поля')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CloudBuilderProgressScreen(
          questId: widget.questId,
          appName: appName,
          packageName: packageName,
          platform: _platform,
          iconPath: _iconPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(tr('Облачная сборка')),
        backgroundColor: scheme.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.cloud_upload_rounded, size: 48, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                tr('Собрать приложение'),
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('Квест будет собран на серверах GitHub. Потребуется бесплатный аккаунт GitHub.'),
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              _buildStatusBanner(scheme, textTheme),

              // App name
              TextField(
                controller: _appNameCtrl,
                decoration: InputDecoration(
                  labelText: tr('Название приложения'),
                  hintText: tr('Мой квест'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.text_fields_rounded),
                ),
              ),
              const SizedBox(height: 16),

              // Package name
              TextField(
                controller: _packageCtrl,
                decoration: InputDecoration(
                  labelText: tr('ID пакета'),
                  hintText: 'com.example.myquest',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.code_rounded),
                  helperText: tr('Уникальный идентификатор для Google Play'),
                ),
              ),
              const SizedBox(height: 16),

              // Platform
              DropdownButtonFormField<String>(
                value: _platform,
                decoration: InputDecoration(
                  labelText: tr('Платформа'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.devices_rounded),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'android-apk',
                    child: Text('Android (APK)'),
                  ),
                  DropdownMenuItem(
                    value: 'android-aab',
                    child: Text('Android AAB (Google Play)'),
                  ),
                  DropdownMenuItem(value: 'web', child: Text(tr('Веб (HTML/JS)'))),
                  DropdownMenuItem(value: 'windows', child: Text('Windows')),
                  DropdownMenuItem(value: 'linux', child: Text('Linux')),
                ],
                onChanged: (v) => setState(() => _platform = v!),
              ),
              const SizedBox(height: 16),

              // Icon
              InkWell(
                onTap: _pickIcon,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          image: _iconPath != null
                              ? DecorationImage(
                                  image: FileImage(File(_iconPath!)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _iconPath == null
                            ? Icon(
                                Icons.image_rounded,
                                color: scheme.onSurfaceVariant,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Иконка приложения'),
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _iconPath != null
                                  ? tr('Иконка выбрана')
                                  : tr('Нажмите, чтобы выбрать (мин. 1024×1024)'),
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _logoutGitHub,
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: Text(tr('Выйти из GitHub')),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              FilledButton.icon(
                onPressed: _startBuild,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: Text(tr('Собрать в облаке')),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(ColorScheme scheme, TextTheme textTheme) {
    final state = ref.watch(cloudBuilderProvider);

    if (state.step == BuilderStep.idle || state.step == BuilderStep.error) {
      return const SizedBox.shrink();
    }

    final isDone = state.step == BuilderStep.done;
    final isRunning = state.step != BuilderStep.done;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDone ? scheme.primaryContainer : scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isDone ? Icons.check_circle_rounded : Icons.sync_rounded,
                  color: isDone
                      ? scheme.onPrimaryContainer
                      : scheme.onTertiaryContainer,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isDone ? tr('Сборка завершена') : tr('Сборка в процессе'),
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDone
                          ? scheme.onPrimaryContainer
                          : scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (state.statusText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                state.statusText,
                style: textTheme.bodySmall?.copyWith(
                  color: isDone
                      ? scheme.onPrimaryContainer.withAlpha(180)
                      : scheme.onTertiaryContainer.withAlpha(180),
                ),
              ),
            ],
            if (isRunning) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CloudBuilderProgressScreen(
                              questId: 'reconnect',
                              appName: 'reconnect',
                              packageName: 'reconnect',
                              platform: 'reconnect',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: Text(tr('Вернуться к сборке')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (state.buildUrl != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final url = Uri.parse(state.buildUrl!);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  label: Text(tr('Открыть в браузере')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
