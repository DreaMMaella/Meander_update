import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/providers/game_screen_provider.dart';
import 'package:mnd_player/providers/game_session_scope.dart';
import 'package:mnd_player/providers/game_state_provider.dart';

/// Единый фасад для работы с поведением контент-айтемов.
///
/// Вся логика исполнения — в Rust-движке (`evaluateVisibility` +
/// `executeBehaviour`). Клиент тупой: передаёт сериализованный айтем, получает
/// результат.
///
/// Обратная совместимость: старые `scriptTriggers` автоматически преобразуются
/// в `ContentTrigger` через `ContentItem.resolvedBehaviours` (в движке).
class TriggerPipeline {
  final String questId;
  final GameStateNotifier gameState;
  final MeanderGameEngine engine;

  const TriggerPipeline({
    required this.questId,
    required this.gameState,
    required this.engine,
  });

  // ---------------------------------------------------------------------------
  // Видимость (onAppear condition)
  // ---------------------------------------------------------------------------

  /// Проверить, должен ли айтем быть видимым.
  ///
  /// - [allowMutation]=true — первый проход: разрешает `set_variable` внутри
  ///   condition-блоков (паритет `evaluateCondition(allowStateMutation: true)`).
  /// - [allowMutation]=false — реактивная переоценка без side-effects.
  Future<bool> evaluateVisibility(
    ContentItem item, {
    bool allowMutation = false,
  }) async {
    return engine.evaluateVisibility(
      item.toJson(),
      allowMutation: allowMutation,
    );
  }

  /// Синхронная проверка видимости (для перестроек UI без await).
  ///
  /// Вызывает синхронный FFI. Без mutation (реактивная переоценка).
  bool evaluateVisibilitySync(ContentItem item) {
    return engine.evaluateVisibility(item.toJson(), allowMutation: false);
  }

  // ---------------------------------------------------------------------------
  // Исполнение (onPress / onSubmit / onReveal)
  // ---------------------------------------------------------------------------

  /// Выполнить поведение айтема для события.
  ///
  /// - `event`: `"onPress"`, `"onSubmit"`, `"onReveal"`.
  /// - Возвращает id ноды для перехода, либо null.
  Future<String?> execute(ContentItem item, String event) async {
    return engine.executeBehaviour(item.toJson(), event);
  }

  /// Слить из движка всё, что осталось после поведения, запущенного виджетом,
  /// и опубликовать новые значения.
  ///
  /// `executeBehaviour` вызывается не только из `next_item`: скрипт слоя стека,
  /// ребёнок ряда/колонки и конец видео запускают его сами. Ядро при этом
  /// переменные кладёт в dirty-дельту, звуки — в `_internal_audio_queue`,
  /// `open_link` — в очередь внешних команд, а `wait` — в pacing-шаги. Одной
  /// дельты мало: не слитый звук доживает до следующего слива и играет уже в
  /// другой сцене, а чужие pacing-кадры накладываются на новую ноду.
  ///
  /// Играет и пейсит экран ([GameScreenNotifier.syncEngineState]) — к нему
  /// идем по [GameSessionScope]. Вне экрана (превью редактора, тест) играть
  /// нечем, но очереди всё равно опустошаем.
  static Future<void> syncAfterWidgetBehaviour({
    required WidgetRef ref,
    required BuildContext context,
    required MeanderGameEngine engine,
  }) async {
    final sessionKey = GameSessionScope.maybeOf(context);
    final notifier = sessionKey == null
        ? null
        : ref.read(gameScreenProvider(sessionKey).notifier);
    if (notifier != null && identical(notifier.engine, engine)) {
      await notifier.syncEngineState();
      return;
    }
    await engine.drainDelaySteps();
    await engine.drainAudio();
    await engine.drainExternal();
    final delta = await engine.drainStateDelta();
    ref
        .read(gameStateProvider.notifier)
        .applyDelta(
          variables: delta['variables'] as Map<String, dynamic>? ?? const {},
          tablesJson: delta['tables'] as Map<String, dynamic>? ?? const {},
        );
  }

  // ---------------------------------------------------------------------------
  // Определение события для interaction
  // ---------------------------------------------------------------------------

  /// Получить приоритетное событие для interaction (нажатия на айтем).
  ///
  /// - `input` → ищет `onSubmit`, затем `onPress`
  /// - `button` с onAppear → пробует onAppear как onPress
  /// - остальное → `onPress`
  ///
  /// Возвращает наиболее подходящее событие, либо null (нет behaviours).
  static String? resolveInteractionEvent(ContentItem item) {
    final behs = item.resolvedBehaviours;
    if (behs.isEmpty) return null;

    if (item.type == 'input') {
      if (behs.any((b) => b.event == 'onSubmit')) return 'onSubmit';
      if (behs.any((b) => b.event == 'onPress')) return 'onPress';
    }

    // Кнопка с onAppear: пробуем onAppear как onPress
    if (item.type == 'button') {
      final hasOnPress = behs.any((b) => b.event == 'onPress');
      if (!hasOnPress && behs.any((b) => b.event == 'onAppear')) {
        return 'onAppear';
      }
      if (hasOnPress) return 'onPress';
    }

    if (behs.any((b) => b.event == 'onPress')) return 'onPress';
    return null;
  }

  static bool itemHasInteraction(ContentItem item) {
    final behs = item.resolvedBehaviours;
    return behs.any(
      (b) =>
          (b.event == 'onPress' || b.event == 'onSubmit') &&
          b.script.trim().isNotEmpty,
    );
  }

  /// Нажатие по айтему должен забрать скрипт/переход, а не собственное действие
  /// виджета (картинка иначе открывает полноэкранный просмотр вместо движка).
  static bool takesPressOverOwnAction(ContentItem item) =>
      itemHasInteraction(item) ||
      (item.targetNodeId?.trim().isNotEmpty ?? false);
}
