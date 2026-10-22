/// Прокладка между Rust-хостом плагинов и игровым экраном.
///
/// Держит то, что плагин «нарисовал» в текущей сессии: surface'ы по целям
/// (`slot:…`, `item:…`, `screen`) и очередь тостов, а также исполняет команды
/// движка: переход по ноде, звук, записи переменных, снимки хранилищ.
///
/// Всё взаимодействие с ядром идёт через [PluginBackend] — в тестах его
/// подменяет подделка, поэтому проверять можно без `.so`.
library;

import 'package:flutter/foundation.dart';
import 'package:mnd_core/engine/plugin_host.dart';

/// Узел, который нарисовал плагин, и кто его автор.
class PluginSurface {
  final String pluginId;

  /// `slot:<id>` | `item:<id>` | `screen`
  final String target;
  final Map<String, dynamic> spec;

  const PluginSurface(this.pluginId, this.target, this.spec);

  String get slotId => target.startsWith('slot:') ? target.substring(5) : target;
}

/// Тост от `mnd.ui.toast`.
class PluginToast {
  final String pluginId;
  final String text;
  final Duration duration;

  const PluginToast(this.pluginId, this.text, this.duration);
}

typedef PluginReadVars = Map<String, dynamic> Function();
typedef PluginVarWrites = void Function(Map<String, dynamic> writes);
typedef PluginNavigate = void Function(String nodeId);
typedef PluginToastCallback = void Function(PluginToast toast);
typedef PluginSound = void Function(String asset, double volume);
typedef PluginStorageWrite = void Function(String pluginId, Map<String, dynamic> storage);

/// Абстракция FFI-хоста: то же, что [MeanderPluginHost], но подменяемо в тестах.
abstract class PluginBackend {
  Future<PluginDispatch> invokeEvent({
    required String event,
    Map<String, dynamic> payload = const {},
    PluginCallContext context = const PluginCallContext(),
  });

  Future<PluginDispatch> call({
    required String pluginId,
    required String function,
    Object? args,
    PluginCallContext context = const PluginCallContext(),
  });

  Future<List<Map<String, dynamic>>> slots();

  Future<List<String>> activeHooks();
}

/// Реальный бэкенд — мост в Rust.
class FfiPluginBackend implements PluginBackend {
  const FfiPluginBackend();

  @override
  Future<PluginDispatch> invokeEvent({
    required String event,
    Map<String, dynamic> payload = const {},
    PluginCallContext context = const PluginCallContext(),
  }) => MeanderPluginHost.invokeEvent(event: event, payload: payload, context: context);

  @override
  Future<PluginDispatch> call({
    required String pluginId,
    required String function,
    Object? args,
    PluginCallContext context = const PluginCallContext(),
  }) => MeanderPluginHost.call(
    pluginId: pluginId,
    function: function,
    args: args,
    context: context,
  );

  @override
  Future<List<Map<String, dynamic>>> slots() => MeanderPluginHost.slots();

  @override
  Future<List<String>> activeHooks() => MeanderPluginHost.activeHooks();
}

/// Состояние UI плагинов одной игровой сессии.
class PluginRuntime extends ChangeNotifier {
  final PluginBackend backend;
  final String questId;
  final PluginReadVars readVars;
  final PluginVarWrites? onVarWrites;
  final PluginNavigate? onNavigate;
  final PluginToastCallback? onToast;
  final PluginSound? onPlaySound;
  final void Function(String? asset)? onStopSound;
  final PluginStorageWrite? onStorage;

  final Map<String, PluginSurface> _surfaces = {};
  List<String> _notices = [];

  /// Подписки ядра: пока пуст, экран не дёргает хост на каждом шаге геймлупа.
  Set<String> _hooks = {};
  List<Map<String, dynamic>> _slots = const [];

  /// Отменил ли последний `node_enter` переход (плагин перехватил ноду).
  bool _canceled = false;

  PluginRuntime({
    required this.backend,
    required this.questId,
    required this.readVars,
    this.onVarWrites,
    this.onNavigate,
    this.onToast,
    this.onPlaySound,
    this.onStopSound,
    this.onStorage,
  });

  List<PluginSurface> get surfaces => _surfaces.values.toList(growable: false);

  /// Сообщения хоста (отброшенные рассылки, ошибки Lua) — для отладочной
  /// панели, не для игрока.
  List<String> get notices => List.unmodifiable(_notices);

  bool get hasPlugins => _hooks.isNotEmpty || _slots.isNotEmpty;

  bool get lastEventCanceled => _canceled;

  Map<String, dynamic>? specFor(String target) => _surfaces[target]?.spec;

  /// Surface цели целиком — нужен, чтобы знать, чей это UI (автор surface'а
  /// получает нажатия, а не тот, кто объявил слот).
  PluginSurface? surfaceFor(String target) => _surfaces[target];

  /// Surface'ы области в порядке приоритета слотов.
  List<PluginSurface> surfacesIn(String area) {
    final ordered = _slots
        .where((slot) => slot['area'] == area)
        .map((slot) => _surfaces['slot:${slot['id']}'])
        .nonNulls
        .toList(growable: false);
    if (ordered.isNotEmpty) return ordered;
    // Плейсхолдеры слотов не рисуются: область пуста, если никто не рендернул.
    return const [];
  }

  /// Все surface'ы, не привязанные к слоту (цели `item:`).
  List<PluginSurface> get freeSurfaces => _surfaces.values
      .where((surface) => !surface.target.startsWith('slot:'))
      .toList(growable: false);

  /// Полноэкранный surface: цель `screen` одна на приложение, последний
  /// отрендеривший плагин выигрывает.
  List<PluginSurface> get screenSurfaces => _surfaces.values
      .where((surface) => surface.target == 'screen')
      .toList(growable: false);

  /// Обновить knowledge о плагинах после установки/снятия.
  Future<void> refresh() async {
    _hooks = (await backend.activeHooks()).toSet();
    _slots = await backend.slots();
    notifyListeners();
  }

  bool listensTo(String event) => _hooks.contains(event);

  /// Пройти событие по плагинам и применить результат.
  Future<bool> dispatchEvent(
    String event, {
    Map<String, dynamic> payload = const {},
    String nodeId = '',
  }) async {
    _canceled = false;
    if (!_hooks.contains(event)) return false;
    final dispatch = await backend.invokeEvent(
      event: event,
      payload: payload,
      context: PluginCallContext(questId: questId, nodeId: nodeId, vars: readVars()),
    );
    _canceled = dispatch.canceled;
    _apply(dispatch);
    return _canceled;
  }

  /// Нажатие в UI плагина: `onPress: 'имя_функции'`.
  Future<void> invokeHandler(
    String pluginId,
    String function, {
    Object? argument,
    String nodeId = '',
  }) async {
    final dispatch = await backend.call(
      pluginId: pluginId,
      function: function,
      args: argument,
      context: PluginCallContext(questId: questId, nodeId: nodeId, vars: readVars()),
    );
    _apply(dispatch);
  }

  void _apply(PluginDispatch dispatch) {
    _notices = [...dispatch.notes, ...dispatch.errors];
    var changed = false;

    for (final outcome in dispatch.outcomes) {
      for (final command in outcome.commands) {
        switch (command.kind) {
          case 'toast':
            onToast?.call(
              PluginToast(
                outcome.pluginId,
                command.text ?? '',
                Duration(
                  milliseconds:
                      (command.raw['durationMs'] as num?)?.toInt() ?? 3000,
                ),
              ),
            );
          case 'render':
            final target = command.target;
            final spec = command.spec;
            if (target == null || spec.isEmpty) continue;
            _surfaces[target] = PluginSurface(outcome.pluginId, target, spec);
            changed = true;
          case 'close':
            final target = command.target;
            if (target != null && _surfaces.remove(target) != null) changed = true;
          case 'goto_node':
            final node = command.raw['node'] as String?;
            if (node != null && node.isNotEmpty) onNavigate?.call(node);
          case 'play_sound':
            onPlaySound?.call(
              command.raw['asset'] as String? ?? '',
              (command.raw['volume'] as num?)?.toDouble() ?? 1.0,
            );
          case 'stop_audio':
            onStopSound?.call(command.raw['asset'] as String?);
        }
      }
    }

    final writes = dispatch.varWrites;
    if (writes.isNotEmpty) onVarWrites?.call(writes);
    dispatch.storages.forEach((pluginId, storage) {
      onStorage?.call(pluginId, storage);
    });

    if (changed) notifyListeners();
  }

  /// Снять все surface'ы плагина (при удалении плагина из сессии).
  void forgetPlugin(String pluginId) {
    final before = _surfaces.length;
    _surfaces.removeWhere((_, surface) => surface.pluginId == pluginId);
    if (_surfaces.length != before) notifyListeners();
  }

  /// Забыть UI, привязанный к айтемам: они живут ровно одну ноду, и при
  /// переходе прошлые картинки/кнопки обязаны исчезнуть, иначе «инвентарь»
  /// из старой сцены останется висеть в новой.
  ///
  /// `screen` под другую семантику: это модальное «захвати экран», оно
  /// переживает смену ноды и снимается плагином (`mnd.ui.close('screen')`)
  /// или игрока — крестиком на [PluginScreenLayer].
  void clearItemSurfaces() {
    final before = _surfaces.length;
    _surfaces.removeWhere((target, _) => target.startsWith('item:'));
    if (_surfaces.length != before) notifyListeners();
  }

  /// Закрыть полноэкранный surface по действию игрока: экранный UI плагина не
  /// должен оказываться ловушкой без выхода.
  void closeScreen() {
    if (_surfaces.remove('screen') != null) notifyListeners();
  }

  /// Очистить состояние при выходе из квеста.
  void reset() {
    _surfaces.clear();
    _notices = [];
    notifyListeners();
  }
}
