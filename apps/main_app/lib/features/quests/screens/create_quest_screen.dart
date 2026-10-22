import 'dart:io';

import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/quest_store.dart';
import 'package:canvas_app/core/utils/error_text.dart';
import 'package:canvas_app/features/onboarding/controllers/tutorial_controller.dart';
import 'package:canvas_app/features/quests/providers/quest_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// План 020-C4.5: операции над квестом — через ядро (QuestStore).
Future<QuestStore> _qs() => QuestStore.defaultInstance();

// ============================================================================
//  СОЗДАНИЕ КВЕСТА — Material 3 редизайн
// ============================================================================

class CreateQuestScreen extends ConsumerStatefulWidget {
  const CreateQuestScreen({super.key});

  @override
  ConsumerState<CreateQuestScreen> createState() => _CreateQuestScreenState();
}

class _CreateQuestScreenState extends ConsumerState<CreateQuestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _versionController = TextEditingController(text: '1.0.0');

  // Ключи для интерактивного обучения
  final GlobalKey _titleFieldKey = GlobalKey();
  final GlobalKey _authorFieldKey = GlobalKey();
  final GlobalKey _descriptionFieldKey = GlobalKey();
  final GlobalKey _submitButtonKey = GlobalKey();

  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = ref.read(tutorialControllerProvider.notifier);
      ctrl.registerTarget(TutorialTargets.titleField, _titleFieldKey);
      ctrl.registerTarget(TutorialTargets.authorField, _authorFieldKey);
      ctrl.registerTarget(
        TutorialTargets.descriptionField,
        _descriptionFieldKey,
      );
      ctrl.registerTarget(TutorialTargets.createSubmitButton, _submitButtonKey);

      // Если обучение всё ещё на шаге «нажми FAB» — продвигаем
      // на «введи название».
      final state = ref.read(tutorialControllerProvider);
      if (state.step == TutorialStep.highlightCreateButton) {
        ctrl.goTo(TutorialStep.fillTitle);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _versionController.dispose();
    super.dispose();
  }

  /// Когда пользователь печатает в поле — продвигаем туториал,
  /// если он сейчас на соответствующем шаге и поле уже не пустое.
  void _onFieldChanged({required TutorialStep step, required String value}) {
    final tutorialState = ref.read(tutorialControllerProvider);
    if (tutorialState.step != step) return;
    if (value.trim().isEmpty) return;
    ref.read(tutorialControllerProvider.notifier).next();
  }

  Future<void> _createQuest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isCreating) return;

    // Если обучение ждёт нажатия на «Создать проект» — продвигаем дальше.
    final tutorialState = ref.read(tutorialControllerProvider);
    if (tutorialState.step == TutorialStep.pressCreate) {
      ref.read(tutorialControllerProvider.notifier).next();
    }

    setState(() => _isCreating = true);

    // Контейнер берётся до первого await: запись папок и config не мгновенна,
    // а новичок в этот момент вправе нажать «Закрыть». После dispose `ref`
    // бросает, и библиотека так и не узнала бы о квесте, который всё равно
    // лег на диск.
    final container = ProviderScope.containerOf(context, listen: false);

    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    final description = _descriptionController.text.trim();

    try {
      final version = _normalizeQuestVersion(_versionController.text);

      final questId = FileStorage.generateUniqueId();
      await FileStorage.createFolder(QuestPaths.questRoot(questId));
      await FileStorage.createFolder(QuestPaths.resImagesDir(questId));
      await FileStorage.createFolder(QuestPaths.resAudioDir(questId));

      final now = DateTime.now();

      // authorId — кому принадлежит квест; используется для определения
      // «свой/чужой» у контента (например, можно ли публиковать пресеты).
      String? authorId;
      try {
        final prefs = await SharedPreferences.getInstance();
        authorId = prefs.getString('user_id');
      } catch (_) {}

      await (await _qs()).writeJson(QuestPaths.config(questId), {
        'id': questId,
        'title': title,
        'description': description,
        'author': author,
        if (authorId != null && authorId.isNotEmpty) 'authorId': authorId,
        'startNodeId': null,
        'password': null,
        'created': now.toIso8601String(),
        'lastEditedAt': now.toIso8601String(),
        'lastOpened': now.toIso8601String(),
        'version': version,
        'updated': now.toIso8601String(),
        'backgroundAssetId': null,
        'dimBackground': false,
        'hideNodeTitles': false,
        'nodeTransitionMode': 'none',
        'scriptEngineMode': kScriptEngineModeNew,
        'pluginDependencies': [],
        'tags': [],
        'nodes': [],
        'connections': [],
        'variables': [],
      });

      try {
        final byteData = await rootBundle.load(
          'assets/images/preview_quest.png',
        );
        final previewPath = await FileStorage.getFilePath(
          QuestPaths.preview(questId),
        );
        final previewFile = File(previewPath);
        await previewFile.writeAsBytes(byteData.buffer.asUint8List());
      } catch (e) {
        debugPrint('⚠️ Ошибка копирования превью: $e');
      }

      // Квест на диске уже лежит, а экрана может не быть: новичок вправе
      // выйти назад, пока пишется config и копируется превью. Поэтому
      // обновляем список через container, а не через `ref` — после dispose
      // `ref` бросает, и библиотека осталась бы без карточки, которая
      // всё равно появилась на диске.
      container.invalidate(questsProvider);

      // Запоминаем id созданного квеста в контроллере обучения —
      // чтобы подсветить именно эту карточку в библиотеке.
      container
          .read(tutorialControllerProvider.notifier)
          .setLastCreatedQuestId(questId);

      if (mounted) {
        Navigator.pop(
          context,
          Quest(
            id: questId,
            title: title,
            author: author,
            description: description,
            imageUrl: null,
            backgroundAssetId: null,
            created: now,
            lastEditedAt: now,
            lastOpened: now,
            version: version,
            dimBackground: false,
            hideNodeTitles: false,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trf('Ошибка: {p0}', {'p0': questCreationErrorText(e)})),
            backgroundColor: scheme.error,
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
            closeIconColor: scheme.onError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  String _normalizeQuestVersion(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '1.0.0' : trimmed;
  }

  // ---------------------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          tr('Новый квест'),
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: tr('Закрыть'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AdaptiveContent(
        maxWidth: 720,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _CoverPreview(),
                const SizedBox(height: 24),
                _SectionLabel(
                  title: tr('Основное'),
                  subtitle: tr('Что увидят игроки в маркете и библиотеке'),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _titleFieldKey,
                  child: TextFormField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? tr('Введите название')
                        : null,
                    decoration: _decoration(
                      label: tr('Название'),
                      hint: tr('Например: Загадка леса'),
                      icon: Icons.title_rounded,
                    ),
                    onChanged: (value) => _onFieldChanged(
                      step: TutorialStep.fillTitle,
                      value: value,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: _authorFieldKey,
                  child: TextFormField(
                    controller: _authorController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration(
                      label: tr('Автор'),
                      hint: tr('Ваше имя или псевдоним'),
                      icon: Icons.person_outline_rounded,
                    ),
                    onChanged: (value) => _onFieldChanged(
                      step: TutorialStep.fillAuthor,
                      value: value,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: _descriptionFieldKey,
                  child: TextFormField(
                    controller: _descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    decoration: _decoration(
                      label: tr('Описание'),
                      hint: tr('О чём будет эта история?'),
                      icon: Icons.description_outlined,
                    ),
                    onChanged: (value) => _onFieldChanged(
                      step: TutorialStep.fillDescription,
                      value: value,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _SectionLabel(
                  title: tr('Метаданные'),
                  subtitle: tr('Эти поля можно изменить позже'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _versionController,
                  decoration: _decoration(
                    label: tr('Версия'),
                    hint: '1.0.0',
                    icon: Icons.numbers_rounded,
                  ),
                ),
                const SizedBox(height: 20),
                _HintCard(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            height: 54,
            child: FilledButton.icon(
              key: _submitButtonKey,
              onPressed: _isCreating ? null : _createQuest,
              icon: _isCreating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                tr('Создать проект'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
  }
}

// ============================================================================
//  COVER PREVIEW
// ============================================================================

class _CoverPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withOpacity(0.6),
              scheme.tertiaryContainer.withOpacity(0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 44,
              color: scheme.onPrimaryContainer.withOpacity(0.7),
            ),
            const SizedBox(height: 10),
            Text(
              tr('Стандартная обложка'),
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tr('Изменить можно в настройках'),
              style: TextStyle(
                color: scheme.onPrimaryContainer.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  PRIMITIVES
// ============================================================================

class _SectionLabel extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionLabel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _HintCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.tips_and_updates_outlined,
            color: scheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('После создания вы сможете добавить ноды, ресурсы и теги. Обложку можно сменить в настройках квеста.'),
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Почему проект не создался — фраза, а не дамп.
///
/// Создание пишет папку квеста через `dart:io`: на заполненном телефоне, на
/// запрещённом каталоге или без плагина путей прилетает `FileSystemException`
/// с путём и `errno`. Новичок, который только что ввёл название проекта и
/// нажал «Создать проект», читал такой снэкбар как сломанный Meander и уходил,
/// хотя проверять надо свободное место и разрешения.
String questCreationErrorText(Object error) {
  if (looksLikeStorageFailure(error)) {
    return tr('Meander не может записать проект на устройство. Проверьте свободное место и разрешите приложению хранить файлы.');
  }
  return friendlyError(error);
}
