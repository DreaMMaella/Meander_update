import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/services/onboarding_service.dart';

/// Шаги интерактивного обучения по созданию квеста.
enum TutorialStep {
  /// Обучение неактивно.
  inactive,

  /// Приветственный модал в библиотеке.
  welcome,

  /// Подсветка кнопки «Создать квест» в библиотеке.
  highlightCreateButton,

  /// На экране создания квеста: подсветка поля «Название».
  fillTitle,

  /// Подсветка поля «Автор».
  fillAuthor,

  /// Подсветка поля «Описание».
  fillDescription,

  /// Подсветка кнопки «Создать проект».
  pressCreate,

  /// После возврата в библиотеку — подсветка свежесозданной карточки квеста.
  openQuestCard,

  /// На экране деталей квеста — подсветка кнопки «Сценарий и Главы»
  /// (редактор узлов).
  openEditor,

  /// Модальный шаг: вводное объяснение про узлы и главы.
  editorIntroModal,

  /// На экране глав (TagsScreen) — подсветка кнопки «Создать» (FAB)
  /// для создания первой главы.
  highlightCreateChapter,

  /// Модальный шаг: «глава создана, открой её, чтобы попасть в редактор».
  openChapterModal,

  /// В canvas-редакторе — подсветка кнопки «+» в тулбаре для
  /// создания первого узла.
  addNodeHighlight,

  /// В canvas-редакторе — подсветка кнопки «Связи» в тулбаре.
  connectModeHighlight,

  /// Модальный шаг: про двойной тап для редактирования узла.
  editTextModal,

  /// В canvas-редакторе — подсветка кнопки «Играть» в тулбаре.
  runQuestHighlight,

  /// Финальный поздравительный модал.
  finished,
}

/// Идентификаторы целевых виджетов, на которые туриал может указывать.
class TutorialTargets {
  static const createQuestFab = 'create_quest_fab';
  static const titleField = 'create_quest_title';
  static const authorField = 'create_quest_author';
  static const descriptionField = 'create_quest_description';
  static const createSubmitButton = 'create_quest_submit';

  /// Карточка свежесозданного квеста в библиотеке.
  static const newQuestCard = 'new_quest_card';

  /// Кнопка «Сценарий и Главы» на экране деталей квеста.
  static const openEditorTile = 'open_editor_tile';

  /// FAB «Создать» главу на экране глав (TagsScreen).
  static const tagsCreateFab = 'tags_create_fab';

  /// Кнопка «+» (создать узел) в тулбаре canvas-редактора.
  static const canvasAddNodeButton = 'canvas_add_node_button';

  /// Кнопка «Связи» (включить режим связей) в тулбаре canvas-редактора.
  static const canvasConnectButton = 'canvas_connect_button';

  /// Кнопка «Играть» в тулбаре canvas-редактора.
  static const canvasPlayButton = 'canvas_play_button';
}

/// Снимок состояния обучения для подписчиков.
class TutorialState {
  final TutorialStep step;

  /// Карта зарегистрированных целей. Хранится здесь только чтобы UI
  /// перестраивался при изменении (не для самой геометрии — её мы
  /// читаем напрямую через GlobalKey).
  final Map<String, GlobalKey> targets;

  /// Версия — увеличивается, когда что-то изменилось и подсветке нужно
  /// перерисовать позицию (например, цель только что появилась).
  final int version;

  /// Идентификатор квеста, созданного во время обучения. Используется,
  /// чтобы подсветить именно его карточку в библиотеке.
  final String? lastCreatedQuestId;

  const TutorialState({
    required this.step,
    required this.targets,
    required this.version,
    this.lastCreatedQuestId,
  });

  factory TutorialState.initial() =>
      const TutorialState(step: TutorialStep.inactive, targets: {}, version: 0);

  bool get isActive => step != TutorialStep.inactive;

  TutorialState copyWith({
    TutorialStep? step,
    Map<String, GlobalKey>? targets,
    int? version,
    String? lastCreatedQuestId,
  }) {
    return TutorialState(
      step: step ?? this.step,
      targets: targets ?? this.targets,
      version: version ?? this.version,
      lastCreatedQuestId: lastCreatedQuestId ?? this.lastCreatedQuestId,
    );
  }
}

/// Контроллер обучения. Управляет шагами и регистрирует/получает цели.
class TutorialController extends StateNotifier<TutorialState> {
  TutorialController() : super(TutorialState.initial());

  // ---------------------------------------------------------------------------
  //  Запуск / остановка
  // ---------------------------------------------------------------------------

  /// Запустить обучение с самого начала. Используется как при первом
  /// запуске, так и при ручном запуске из настроек.
  void start() {
    state = state.copyWith(
      step: TutorialStep.welcome,
      version: state.version + 1,
    );
  }

  /// Полностью прервать обучение и пометить как пропущенное.
  Future<void> skip() async {
    await OnboardingService.markQuestCreationSkipped();
    _stop();
  }

  /// Завершить обучение успешно.
  Future<void> finish() async {
    await OnboardingService.markQuestCreationCompleted();
    _stop();
  }

  void _stop() {
    state = state.copyWith(
      step: TutorialStep.inactive,
      version: state.version + 1,
    );
  }

  // ---------------------------------------------------------------------------
  //  Переходы между шагами
  // ---------------------------------------------------------------------------

  void goTo(TutorialStep step) {
    if (state.step == step) return;
    state = state.copyWith(step: step, version: state.version + 1);
  }

  void next() {
    final next = _nextStep(state.step);
    if (next == null) return;
    goTo(next);
  }

  TutorialStep? _nextStep(TutorialStep current) {
    switch (current) {
      case TutorialStep.inactive:
        return null;
      case TutorialStep.welcome:
        return TutorialStep.highlightCreateButton;
      case TutorialStep.highlightCreateButton:
        return TutorialStep.fillTitle;
      case TutorialStep.fillTitle:
        return TutorialStep.fillAuthor;
      case TutorialStep.fillAuthor:
        return TutorialStep.fillDescription;
      case TutorialStep.fillDescription:
        return TutorialStep.pressCreate;
      case TutorialStep.pressCreate:
        return TutorialStep.openQuestCard;
      case TutorialStep.openQuestCard:
        return TutorialStep.openEditor;
      case TutorialStep.openEditor:
        return TutorialStep.editorIntroModal;
      case TutorialStep.editorIntroModal:
        return TutorialStep.highlightCreateChapter;
      case TutorialStep.highlightCreateChapter:
        return TutorialStep.openChapterModal;
      case TutorialStep.openChapterModal:
        return TutorialStep.addNodeHighlight;
      case TutorialStep.addNodeHighlight:
        return TutorialStep.connectModeHighlight;
      case TutorialStep.connectModeHighlight:
        return TutorialStep.editTextModal;
      case TutorialStep.editTextModal:
        return TutorialStep.runQuestHighlight;
      case TutorialStep.runQuestHighlight:
        return TutorialStep.finished;
      case TutorialStep.finished:
        return null;
    }
  }

  /// Запомнить id только что созданного квеста — чтобы потом подсветить
  /// именно его карточку в библиотеке.
  void setLastCreatedQuestId(String id) {
    state = state.copyWith(lastCreatedQuestId: id, version: state.version + 1);
  }

  // ---------------------------------------------------------------------------
  //  Регистрация целевых виджетов
  // ---------------------------------------------------------------------------

  /// Экран сообщает контроллеру: «вот мой ключ для цели X».
  /// Можно вызывать многократно — контроллер пересоберёт state только если
  /// ключ действительно изменился.
  void registerTarget(String id, GlobalKey key) {
    final existing = state.targets[id];
    if (existing == key) return;
    final newTargets = Map<String, GlobalKey>.from(state.targets);
    newTargets[id] = key;
    state = state.copyWith(targets: newTargets, version: state.version + 1);
  }

  /// Когда экран уходит, лучше снимать регистрацию, чтобы не указывать
  /// на несуществующие виджеты.
  void unregisterTarget(String id, GlobalKey key) {
    final existing = state.targets[id];
    if (existing != key) return; // уже перетёрто новым ключом
    final newTargets = Map<String, GlobalKey>.from(state.targets);
    newTargets.remove(id);
    state = state.copyWith(targets: newTargets, version: state.version + 1);
  }

  /// Сообщает оверлею: «цель только что появилась/обновилась, перерисуй
  /// подсветку». Например, после `setState` в форме.
  void bumpVersion() {
    state = state.copyWith(version: state.version + 1);
  }

  /// Возвращает GlobalKey зарегистрированной цели либо null.
  GlobalKey? targetKey(String id) => state.targets[id];

  /// Идентификатор цели для текущего шага. null — значит шаг
  /// без подсветки конкретного виджета (модал).
  String? currentTargetId() {
    switch (state.step) {
      case TutorialStep.highlightCreateButton:
        return TutorialTargets.createQuestFab;
      case TutorialStep.fillTitle:
        return TutorialTargets.titleField;
      case TutorialStep.fillAuthor:
        return TutorialTargets.authorField;
      case TutorialStep.fillDescription:
        return TutorialTargets.descriptionField;
      case TutorialStep.pressCreate:
        return TutorialTargets.createSubmitButton;
      case TutorialStep.openQuestCard:
        return TutorialTargets.newQuestCard;
      case TutorialStep.openEditor:
        return TutorialTargets.openEditorTile;
      case TutorialStep.highlightCreateChapter:
        return TutorialTargets.tagsCreateFab;
      case TutorialStep.addNodeHighlight:
        return TutorialTargets.canvasAddNodeButton;
      case TutorialStep.connectModeHighlight:
        return TutorialTargets.canvasConnectButton;
      case TutorialStep.runQuestHighlight:
        return TutorialTargets.canvasPlayButton;
      // Модальные шаги — без подсветки конкретного виджета.
      case TutorialStep.welcome:
      case TutorialStep.editorIntroModal:
      case TutorialStep.openChapterModal:
      case TutorialStep.editTextModal:
      case TutorialStep.finished:
      case TutorialStep.inactive:
        return null;
    }
  }
}

/// Глобальный провайдер контроллера обучения.
final tutorialControllerProvider =
    StateNotifierProvider<TutorialController, TutorialState>((ref) {
      return TutorialController();
    });
