/// Dart-обёртка над Rust-хостом плагинов (L3B).
///
/// Хост живёт в Rust (`crates/mnd-plugin`): он держит песочницу Lua, политики
/// разрешений и порядок обхода хуков. Здесь только транспорт: JSON внутрь,
/// типизированный результат наружу.
///
/// Ключевое свойство границы — плагин **никогда** не присылает код. Результат
/// его работы — список команд фиксированного набора (`toast`/`render`/
/// `gotoNode`/…) и дифферент переменных; рисует всё клиент своим рендерером
/// (`mnd_player` → `PluginSpecView`).
library;

import 'dart:convert';

import 'package:mnd_core/src/gen/api/plugin.dart' as gen;

/// Маркер: мьютекс хоста отравлен паникой — поможет только [reset].
const String _kPoisonedMarker = '{"error":"plugin_host_poisoned"}';

/// Хост непригоден после паники в Rust.
class PluginHostPoisonedException implements Exception {
  final String method;

  const PluginHostPoisonedException(this.method);

  @override
  String toString() =>
      'PluginHostPoisonedException: plugin host poisoned after a Rust panic '
      '(method: $method)';
}

void _throwIfPoisoned(String raw, String method) {
  if (raw == _kPoisonedMarker) throw PluginHostPoisonedException(method);
}

Map<String, dynamic> _asMap(Object? value) =>
    (value as Map?)?.cast<String, dynamic>() ?? const {};

List<Map<String, dynamic>> _mapList(Object? value) =>
    (value as List?)?.map(_asMap).toList(growable: false) ?? const [];

List<String> _stringList(Object? value) =>
    (value as List?)?.map((item) => '$item').toList(growable: false) ?? const [];

/// Одна команда плагина: `{kind: toast|render|close|gotoNode|playSound|stopAudio, …}`.
class PluginCommand {
  final String kind;
  final Map<String, dynamic> raw;

  const PluginCommand(this.kind, this.raw);

  factory PluginCommand.fromJson(Map<String, dynamic> json) =>
      PluginCommand(json['kind'] as String? ?? '', json);

  String? get target => raw['target'] as String?;
  String? get text => raw['text'] as String?;
  Map<String, dynamic> get spec => _asMap(raw['spec']);

  @override
  String toString() => 'PluginCommand($kind, $raw)';
}

/// Запись из `mnd.log.*` — идёт в отладочную консоль плагинов, не в UI.
class PluginLogEntry {
  final String pluginId;
  final String level;
  final String text;

  const PluginLogEntry(this.pluginId, this.level, this.text);

  factory PluginLogEntry.fromJson(Map<String, dynamic> json) => PluginLogEntry(
    json['pluginId'] as String? ?? '',
    json['level'] as String? ?? 'info',
    json['text'] as String? ?? '',
  );
}

/// Исход одного плагина за проход.
class PluginOutcome {
  final String pluginId;
  final List<PluginCommand> commands;
  final Map<String, dynamic> varWrites;
  final List<PluginLogEntry> logs;
  final bool cancel;
  final String? error;
  final bool storageDirty;

  const PluginOutcome({
    required this.pluginId,
    required this.commands,
    required this.varWrites,
    required this.logs,
    required this.cancel,
    required this.error,
    required this.storageDirty,
  });

  factory PluginOutcome.fromJson(Map<String, dynamic> json) => PluginOutcome(
    pluginId: json['pluginId'] as String? ?? '',
    commands: _mapList(json['commands']).map(PluginCommand.fromJson).toList(growable: false),
    varWrites: _asMap(json['varWrites']),
    logs: _mapList(json['logs']).map(PluginLogEntry.fromJson).toList(growable: false),
    cancel: json['cancel'] as bool? ?? false,
    error: json['error'] as String?,
    storageDirty: json['storageDirty'] as bool? ?? false,
  );
}

/// Итог прохода события (или `plugin_call`) по всем подписчикам.
class PluginDispatch {
  final String event;
  final List<PluginOutcome> outcomes;
  final List<String> notes;

  /// Снимки хранилищ только «грязных» в этом проходе плагинов — их клиент
  /// обязан записать на диск.
  final Map<String, Map<String, dynamic>> storages;
  final bool failed;

  const PluginDispatch({
    required this.event,
    required this.outcomes,
    required this.notes,
    required this.storages,
    this.failed = false,
  });

  const PluginDispatch.empty(this.event)
    : outcomes = const [],
      notes = const [],
      storages = const {},
      failed = false;

  factory PluginDispatch.fromJson(Map<String, dynamic> json) {
    final storages = <String, Map<String, dynamic>>{};
    _asMap(json['storages']).forEach((id, snapshot) {
      storages[id] = _asMap(snapshot);
    });
    return PluginDispatch(
      event: json['event'] as String? ?? '',
      outcomes: _mapList(json['outcomes']).map(PluginOutcome.fromJson).toList(growable: false),
      notes: _stringList(json['notes']),
      storages: storages,
    );
  }

  /// Команды всех плагинов в детерминированном порядке обхода.
  List<PluginCommand> get commands => [
    for (final outcome in outcomes)
      ...outcome.commands,
  ];

  /// Объединённый дифферент переменных: поздний плагин перекрывает раннего.
  Map<String, dynamic> get varWrites => {
    for (final outcome in outcomes) ...outcome.varWrites,
  };

  List<PluginLogEntry> get logs => [
    for (final outcome in outcomes)
      ...outcome.logs,
  ];

  List<String> get errors => [
    for (final outcome in outcomes)
      if (outcome.error != null) '${outcome.pluginId}: ${outcome.error}',
    if (failed) 'plugin host unavailable',
  ];

  /// Отмена дефолтного поведения (смысл имеет для `node_enter`).
  bool get canceled => outcomes.any((outcome) => outcome.cancel);

  bool get hasWork =>
      failed ||
      notes.isNotEmpty ||
      commands.isNotEmpty ||
      varWrites.isNotEmpty ||
      storages.isNotEmpty ||
      outcomes.any((outcome) => outcome.logs.isNotEmpty || outcome.error != null);

  @override
  String toString() =>
      'PluginDispatch($event, commands: ${commands.length}, writes: ${varWrites.length}, errors: ${errors.length})';
}

/// Результат установки плагина.
class PluginRegisterResult {
  final bool ok;
  final String? id;
  final List<String> errors;

  const PluginRegisterResult({required this.ok, this.id, this.errors = const []});

  factory PluginRegisterResult.fromJson(Map<String, dynamic> json) => PluginRegisterResult(
    ok: json['ok'] as bool? ?? false,
    id: json['id'] as String?,
    errors: _stringList(json['errors']),
  );

  @override
  String toString() => ok ? 'PluginRegisterResult($id)' : 'PluginRegisterResult.failed($errors)';
}

/// Контекст вызова: что плагин видит в `mnd.questId` / `mnd.nodeId` / `mnd.vars`.
class PluginCallContext {
  final String questId;
  final String nodeId;
  final Map<String, dynamic> vars;

  /// null — «сейчас» подставляется на момент вызова.
  final int? nowMs;

  const PluginCallContext({
    this.questId = '',
    this.nodeId = '',
    this.vars = const {},
    this.nowMs,
  });

  Map<String, dynamic> toJson() => {
    'questId': questId,
    'nodeId': nodeId,
    'vars': vars,
    'nowMs': nowMs ?? DateTime.now().millisecondsSinceEpoch,
  };
}

/// Точка входа клиента к хосту плагинов. Один на процесс — плагины это
/// установка, а не сессия квеста.
class MeanderPluginHost {
  const MeanderPluginHost();

  static const MeanderPluginHost instance = MeanderPluginHost();

  /// Установить плагин: `plugin.json` + содержимое точки входа + снимок хранилища.
  static Future<PluginRegisterResult> register({
    required String manifestJson,
    required String source,
    Map<String, dynamic> storage = const {},
  }) async {
    final raw = await gen.pluginRegister(
      manifestJson: manifestJson,
      source: source,
      storageJson: jsonEncode(storage),
    );
    _throwIfPoisoned(raw, 'register');
    return PluginRegisterResult.fromJson(_asMap(jsonDecode(raw)));
  }

  static bool unregister(String pluginId) => gen.pluginUnregister(pluginId: pluginId);

  /// Снять все плагины. Нужен после [PluginHostPoisonedException].
  static bool reset() => gen.pluginReset();

  static Future<List<Map<String, dynamic>>> manifests() async {
    final raw = await gen.pluginList();
    _throwIfPoisoned(raw, 'list');
    return _mapList(jsonDecode(raw));
  }

  /// Типы контента плагинов: `{pluginId, type, name, fields, preview}`.
  static Future<List<Map<String, dynamic>>> contentTypes() async {
    final raw = await gen.pluginContentTypes();
    _throwIfPoisoned(raw, 'contentTypes');
    return _mapList(jsonDecode(raw));
  }

  /// Слоты UI: `{pluginId, id, area, priority}`.
  static Future<List<Map<String, dynamic>>> slots() async {
    final raw = await gen.pluginSlots();
    _throwIfPoisoned(raw, 'slots');
    return _mapList(jsonDecode(raw));
  }

  static Future<List<String>> activeHooks() async {
    final raw = await gen.pluginActiveHooks();
    _throwIfPoisoned(raw, 'activeHooks');
    return _stringList(jsonDecode(raw));
  }

  static Future<List<String>> permissions(String pluginId) async {
    final raw = await gen.pluginPermissions(pluginId: pluginId);
    _throwIfPoisoned(raw, 'permissions');
    return _stringList(jsonDecode(raw));
  }

  static Future<Map<String, dynamic>?> storage(String pluginId) async {
    final raw = await gen.pluginStorage(pluginId: pluginId);
    _throwIfPoisoned(raw, 'storage');
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }

  /// Проход события EventContract по подписанным плагинам.
  static Future<PluginDispatch> invokeEvent({
    required String event,
    Map<String, dynamic> payload = const {},
    PluginCallContext context = const PluginCallContext(),
  }) async {
    final raw = await gen.pluginInvokeEvent(
      event: event,
      payloadJson: jsonEncode(payload),
      contextJson: jsonEncode(context.toJson()),
    );
    return _decodeDispatch(raw, 'invokeEvent');
  }

  /// Вызов функции плагина по имени (кнопка из UI-спека, пункт меню).
  static Future<PluginDispatch> call({
    required String pluginId,
    required String function,
    Object? args,
    PluginCallContext context = const PluginCallContext(),
  }) async {
    final raw = await gen.pluginCall(
      pluginId: pluginId,
      function: function,
      argsJson: jsonEncode(args),
      contextJson: jsonEncode(context.toJson()),
    );
    return _decodeDispatch(raw, 'call');
  }

  static PluginDispatch _decodeDispatch(String raw, String method) {
    _throwIfPoisoned(raw, method);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const PluginDispatch.empty('');
    return PluginDispatch.fromJson(decoded.cast<String, dynamic>());
  }
}
