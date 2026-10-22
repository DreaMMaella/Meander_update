import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:canvas_app/features/export/providers/cloud_builder_provider.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

class CloudBuilderProgressScreen extends ConsumerStatefulWidget {
  final String questId;
  final String appName;
  final String packageName;
  final String platform;
  final String? iconPath;

  const CloudBuilderProgressScreen({
    super.key,
    required this.questId,
    required this.appName,
    required this.packageName,
    required this.platform,
    this.iconPath,
  });

  @override
  ConsumerState<CloudBuilderProgressScreen> createState() =>
      _CloudBuilderProgressScreenState();
}

class _CloudBuilderProgressScreenState
    extends ConsumerState<CloudBuilderProgressScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _triggerBuild();
    });
  }

  void _triggerBuild() {
    if (_started) return;
    _started = true;
    ref
        .read(cloudBuilderProvider.notifier)
        .startBuild(
          questId: widget.questId,
          appName: widget.appName,
          packageName: widget.packageName,
          platform: widget.platform,
          iconPath: widget.iconPath,
        );
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  void _openAuthUrl(String uri) async {
    final url = Uri.parse(uri);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _openFileLocation(String path) {
    // Текст сника на десктопе не выделяется мышью, поэтому «OK» был не
    // кнопкой, а декорацией: путь показали, а скопировать его нечем.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trf('Файл сохранён:\n{path}', {'path': path})),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: tr('Копировать'),
          onPressed: () => Clipboard.setData(ClipboardData(text: path)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(cloudBuilderProvider);

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: Text(tr('Сборка...')),
          backgroundColor: scheme.surface,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: scheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: AdaptiveContent(
          maxWidth: 720,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  // Auth code display — shown whenever we're waiting for user to enter code
                  if (state.step == BuilderStep.authWaiting &&
                      state.deviceCode != null) ...[
                    const Spacer(flex: 1),
                    Icon(Icons.lock_rounded, size: 64, color: scheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      tr('Авторизация GitHub'),
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Введите этот код на сайте GitHub\nдля подтверждения сборки:'),
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                state.deviceCode!,
                                style: textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 8,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: Icon(
                                  Icons.copy_rounded,
                                  color: scheme.primary,
                                  size: 24,
                                ),
                                tooltip: tr('Копировать код'),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: state.deviceCode!),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(tr('Код скопирован')),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _openAuthUrl(state.verificationUri!),
                      icon: const Icon(Icons.open_in_browser_rounded),
                      label: Text(tr('Открыть github.com')),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('Код действителен 15 минут'),
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(flex: 2),
                  ] else ...[
                    const Spacer(flex: 1),
                    AnimatedBuilder(
                      animation: _spinCtrl,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _spinCtrl.value * 6.2832,
                          child: child,
                        );
                      },
                      child: state.step == BuilderStep.done
                          ? Icon(
                              Icons.check_circle_rounded,
                              size: 64,
                              color: scheme.primary,
                            )
                          : state.step == BuilderStep.error
                          ? Icon(
                              Icons.error_rounded,
                              size: 64,
                              color: scheme.error,
                            )
                          : Icon(
                              Icons.sync_rounded,
                              size: 64,
                              color: scheme.primary,
                            ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      state.step == BuilderStep.done
                          ? tr('Готово!')
                          : state.step == BuilderStep.error
                          ? tr('Ошибка')
                          : tr('Выполняется...'),
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.statusText,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.errorMessage!,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],

                    // Steps
                    const SizedBox(height: 32),
                    _StepRow(
                      icon: Icons.login_rounded,
                      label: tr('Авторизация'),
                      done: state.step.index >= BuilderStep.authDone.index,
                      error:
                          state.errorMessage != null &&
                          state.step.index < BuilderStep.authDone.index,
                    ),
                    _StepRow(
                      icon: Icons.fork_right_rounded,
                      label: tr('Подготовка репозитория'),
                      done: state.step.index >= BuilderStep.forkDone.index,
                      error:
                          state.errorMessage != null &&
                          state.step == BuilderStep.forking,
                    ),
                    _StepRow(
                      icon: Icons.upload_file_rounded,
                      label: tr('Загрузка файлов'),
                      done: state.step.index >= BuilderStep.uploadDone.index,
                      error:
                          state.errorMessage != null &&
                          (state.step == BuilderStep.uploadingQuest ||
                              state.step == BuilderStep.uploadingIcon),
                    ),
                    _StepRow(
                      icon: Icons.build_rounded,
                      label: tr('Сборка на сервере'),
                      done: state.step == BuilderStep.done,
                      active:
                          state.step == BuilderStep.building ||
                          state.step == BuilderStep.downloading,
                      error:
                          state.errorMessage != null &&
                          (state.step == BuilderStep.dispatching ||
                              state.step == BuilderStep.building),
                    ),
                    const SizedBox(height: 32),

                    if (state.downloadedFilePath != null)
                      FilledButton.icon(
                        onPressed: () =>
                            _openFileLocation(state.downloadedFilePath!),
                        icon: const Icon(Icons.download_done_rounded),
                        label: Text(tr('Файл сохранён — показать путь')),
                      ),

                    if (state.step == BuilderStep.error)
                      FilledButton.tonal(
                        onPressed: () {
                          ref.read(cloudBuilderProvider.notifier).reset();
                          Navigator.pop(context);
                        },
                        child: Text(tr('Назад')),
                      ),

                    const Spacer(flex: 2),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;
  final bool active;
  final bool error;

  const _StepRow({
    required this.icon,
    required this.label,
    this.done = false,
    this.active = false,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Color iconColor;
    if (error) {
      iconColor = scheme.error;
    } else if (done) {
      iconColor = scheme.primary;
    } else if (active) {
      iconColor = scheme.primary;
    } else {
      iconColor = scheme.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: done
                  ? scheme.primaryContainer
                  : active
                  ? scheme.primaryContainer.withAlpha(80)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: active && !done && !error
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    done ? Icons.check_rounded : icon,
                    size: 18,
                    color: iconColor,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done
                    ? scheme.onSurface
                    : active
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
                fontWeight: done || active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
