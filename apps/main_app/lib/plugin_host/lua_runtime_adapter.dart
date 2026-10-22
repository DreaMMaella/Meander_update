import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/plugin_host/canvas/display_object.dart';
import 'package:canvas_app/plugin_host/canvas/lua_display_api.dart';
import 'package:canvas_app/plugin_host/plugin_content_type.dart';
import 'package:canvas_app/plugin_host/plugin_ui_spec.dart';
import 'package:lua_dardo/lua.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef LuaRuntimeLog = void Function(String message);

typedef PluginEventCallback = void Function(
  String pluginId,
  String eventName,
  Map<String, dynamic> payload,
);

typedef PluginScreenCallback = void Function(
  String pluginId,
  PluginScreenSpec screen,
);

typedef PluginSlotInjectCallback = void Function(
  String pluginId,
  String slotId,
  PluginWidgetSpec widget,
);

typedef PluginContentTypeCallback = void Function(
  String pluginId,
  PluginContentType type,
);

typedef PluginToastCallback = void Function(String pluginId, String message);

class PluginLuaState {
  final LuaState state;
  final Set<String> functions;
  final Map<String, List<PluginEventCallback>> eventHandlers;

  PluginLuaState({
    required this.state,
    required this.functions,
    Map<String, List<PluginEventCallback>>? eventHandlers,
  }) : eventHandlers = eventHandlers ?? {};
}

class LuaRuntimeAdapter {
  final LuaRuntimeLog log;
  final Map<String, PluginLuaState> _states = {};
  final Map<String, Map<String, dynamic>> _storage = {};
  final Map<String, Map<String, dynamic>> _questVars = {};
  final Map<String, Map<String, List<PluginEventCallback>>> _eventListeners = {};
  final List<PluginScreenCallback> _screenCallbacks = [];
  final List<PluginSlotInjectCallback> _slotInjectCallbacks = [];
  final List<PluginContentTypeCallback> _contentTypeCallbacks = [];
  final List<PluginToastCallback> _toastCallbacks = [];
  final Map<String, List<Map<String, dynamic>>> _pendingEvents = {};
  final Map<String, LuaDisplayAPI> _displayAPIs = {};

  LuaRuntimeAdapter(this.log);

  void addScreenCallback(PluginScreenCallback cb) => _screenCallbacks.add(cb);
  void addSlotInjectCallback(PluginSlotInjectCallback cb) =>
      _slotInjectCallbacks.add(cb);
  void addContentTypeCallback(PluginContentTypeCallback cb) =>
      _contentTypeCallbacks.add(cb);
  void addToastCallback(PluginToastCallback cb) => _toastCallbacks.add(cb);

  void load(String pluginId, String scriptText) {
    _loadInternal(pluginId, scriptText, null, null);
  }

  void loadWithCanvas(
    String pluginId,
    String scriptText,
    DisplayScene scene,
    dynamic canvasState,
  ) {
    _loadInternal(pluginId, scriptText, scene, canvasState);
  }

  void _loadInternal(
    String pluginId,
    String scriptText,
    DisplayScene? scene,
    dynamic canvasState,
  ) {
    final matches = RegExp(r'function\s+([A-Za-z0-9_]+)\s*\(')
        .allMatches(scriptText);
    final set = <String>{};
    for (final match in matches) {
      final name = match.group(1);
      if (name != null) set.add(name);
    }

    final state = LuaState.newState();
    state.openLibs();
    _stripDangerousGlobals(state);
    _registerApi(state, pluginId);

    if (scene != null) {
      final displayAPI = LuaDisplayAPI(
        log: log,
        scene: scene,
        canvasState: canvasState,
      );
      displayAPI.register(state);
      _displayAPIs[pluginId] = displayAPI;
    }

    final loadStatus = state.loadString(scriptText);
    if (loadStatus != ThreadStatus.luaOk) {
      log('[PluginRuntime] load error $pluginId ($loadStatus)');
      return;
    }

    final callStatus = state.pCall(0, 0, 0);
    if (callStatus != ThreadStatus.luaOk) {
      final msg = state.toStr(-1) ?? 'unknown error';
      log('[PluginRuntime] init error $pluginId: $msg');
      state.pop(1);
      return;
    }

    _storage.putIfAbsent(pluginId, () => {});
    _questVars.putIfAbsent(pluginId, () => {});

    _states[pluginId] = PluginLuaState(
      state: state,
      functions: set,
    );

    _flushPendingEvents(pluginId);

    log('[PluginRuntime] loaded $pluginId (${set.length} functions)');
  }

  bool hasFunction(String pluginId, String functionName) {
    return _states[pluginId]?.functions.contains(functionName) ?? false;
  }

  void call(String pluginId, String functionName, {List<Object?>? args}) {
    final pluginState = _states[pluginId];
    if (pluginState == null) {
      log('[PluginRuntime] call skipped (no state) $pluginId.$functionName');
      return;
    }
    final state = pluginState.state;
    state.getGlobal(functionName);
    if (state.type(-1) != LuaType.luaFunction) {
      state.pop(1);
      log('[PluginRuntime] skip $pluginId.$functionName (not callable)');
      return;
    }

    final argCount = args?.length ?? 0;
    if (args != null) {
      for (final arg in args) {
        _pushValue(state, arg);
      }
    }

    final status = state.pCall(argCount, 0, 0);
    if (status != ThreadStatus.luaOk) {
      final msg = state.toStr(-1) ?? 'unknown error';
      log('[PluginRuntime] call error $pluginId.$functionName: $msg');
      state.pop(1);
    } else {
      log('[PluginRuntime] call $pluginId.$functionName($argCount args)');
    }
  }

  void callWithQuestId(String pluginId, String functionName, String questId) {
    call(pluginId, functionName, args: [questId]);
  }

  void disposePlugin(String pluginId) {
    _states.remove(pluginId);
    _storage.remove(pluginId);
    _questVars.remove(pluginId);
    _eventListeners.remove(pluginId);
    _pendingEvents.remove(pluginId);
    _displayAPIs.remove(pluginId);
  }

  void emitEvent(
    String targetPluginId,
    String eventName,
    Map<String, dynamic> payload,
  ) {
    log('[PluginRuntime] event $targetPluginId:$eventName');
    final listeners = _eventListeners[targetPluginId]?[eventName];
    if (listeners != null && listeners.isNotEmpty) {
      for (final cb in listeners) {
        cb(targetPluginId, eventName, payload);
      }
      return;
    }

    _pendingEvents.putIfAbsent(targetPluginId, () => []).add({
      'event': eventName,
      'payload': payload,
    });
  }

  void onEvent(
    String pluginId,
    String eventName,
    PluginEventCallback callback,
  ) {
    _eventListeners
        .putIfAbsent(pluginId, () => {})
        .putIfAbsent(eventName, () => [])
        .add(callback);
  }

  Map<String, dynamic>? getStorage(String pluginId, String key) {
    return _storage[pluginId]?[key];
  }

  void setStorage(String pluginId, String key, dynamic value) {
    _storage.putIfAbsent(pluginId, () => {})[key] = value;
  }

  void flushStorage(String pluginId) async {
    final data = _storage[pluginId];
    if (data == null || data.isEmpty) return;
    final dir = await _getPluginStorageDir();
    final file = File(p.join(dir.path, '$pluginId.json'));
    await file.writeAsString(jsonEncode(data));
    log('[PluginRuntime] storage flushed for $pluginId');
  }

  Future<void> loadStorage(String pluginId) async {
    final dir = await _getPluginStorageDir();
    final file = File(p.join(dir.path, '$pluginId.json'));
    if (!file.existsSync()) return;
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      _storage[pluginId] = decoded;
      log('[PluginRuntime] storage loaded for $pluginId (${decoded.length} keys)');
    } catch (e) {
      log('[PluginRuntime] storage load failed for $pluginId: $e');
    }
  }

  Future<Directory> _getPluginStorageDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'plugins_storage'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void _flushPendingEvents(String pluginId) {
    final events = _pendingEvents.remove(pluginId);
    if (events == null) return;
    final pluginListeners = _eventListeners[pluginId];
    if (pluginListeners == null) return;
    for (final event in events) {
      final eventName = event['event'] as String;
      final payload = event['payload'] as Map<String, dynamic>;
      final listeners = pluginListeners[eventName];
      if (listeners != null) {
        for (final cb in listeners) {
          cb(pluginId, eventName, payload);
        }
      }
    }
  }

  void _pushValue(LuaState state, Object? value) {
    if (value == null) {
      state.pushNil();
    } else if (value is String) {
      state.pushString(value);
    } else if (value is num) {
      state.pushNumber(value.toDouble());
    } else if (value is bool) {
      state.pushBoolean(value);
    } else {
      state.pushString(value.toString());
    }
  }

  void _stripDangerousGlobals(LuaState state) {
    for (final name in ['os', 'io', 'package', 'debug']) {
      state.pushNil();
      state.setGlobal(name);
    }
    for (final name in ['dofile', 'loadfile']) {
      state.pushNil();
      state.setGlobal(name);
    }
  }

  void _registerApi(LuaState state, String pluginId) {
    _registerTable(
      state,
      'ui',
      {
        'toast': (ls) => _uiToast(ls, pluginId),
        'alert': (ls) => _uiAlert(ls, pluginId),
        'createScreen': (ls) => _uiCreateScreen(ls, pluginId),
      },
    );
    _registerTable(
      state,
      'navigation',
      {
        'push': (ls) => _navigationPush(ls, pluginId),
        'pop': (ls) => _navigationPop(ls, pluginId),
      },
    );
    _registerTable(
      state,
      'plugin',
      {
        'injectUI': (ls) => _pluginInjectUI(ls, pluginId),
        'registerContentType':
            (ls) => _pluginRegisterContentType(ls, pluginId),
        'registerSlot': (ls) => _pluginRegisterSlot(ls, pluginId),
      },
    );
    _registerTable(
      state,
      'quest',
      {
        'setVar': (ls) => _questSetVar(ls, pluginId),
        'getVar': (ls) => _questGetVar(ls, pluginId),
        'giveItem': (ls) => _questGiveItem(ls, pluginId),
        'playSound': (ls) => _questPlaySound(ls, pluginId),
      },
    );
    _registerTable(
      state,
      'storage',
      {
        'set': (ls) => _storageSet(ls, pluginId),
        'get': (ls) => _storageGet(ls, pluginId),
        'remove': (ls) => _storageRemove(ls, pluginId),
        'clear': (ls) => _storageClear(ls, pluginId),
      },
    );
    _registerTable(
      state,
      'events',
      {
        'emit': (ls) => _eventsEmit(ls, pluginId),
        'on': (ls) => _eventsOn(ls, pluginId),
      },
    );
    _registerTable(
      state,
      'logger',
      {
        'debug': (ls) => _loggerDebug(ls, pluginId),
        'info': (ls) => _loggerInfo(ls, pluginId),
        'warn': (ls) => _loggerWarn(ls, pluginId),
        'error': (ls) => _loggerError(ls, pluginId),
      },
    );
  }

  void _registerTable(
    LuaState state,
    String name,
    Map<String, DartFunction> functions,
  ) {
    state.newTable();
    functions.forEach((key, fn) {
      state.pushString(key);
      state.pushDartFunction(fn);
      state.setTable(-3);
    });
    state.setGlobal(name);
  }

  // ========== UI API ==========

  int _uiToast(LuaState ls, String pluginId) {
    final message = ls.optString(1, '') ?? '';
    log('[Lua][$pluginId] ui.toast("$message")');
    for (final cb in _toastCallbacks) {
      cb(pluginId, message);
    }
    return 0;
  }

  int _uiAlert(LuaState ls, String pluginId) {
    final title = ls.optString(1, 'Alert') ?? 'Alert';
    final message = ls.optString(2, '') ?? '';
    log('[Lua][$pluginId] ui.alert("$title", "$message")');
    for (final cb in _toastCallbacks) {
      cb(pluginId, '$title: $message');
    }
    return 0;
  }

  int _uiCreateScreen(LuaState ls, String pluginId) {
    final screenId = ls.optString(1, 'screen') ?? 'screen';
    log('[Lua][$pluginId] ui.createScreen("$screenId")');

    final widgets = <PluginWidgetSpec>[];

    DartFunction addWidgetFn = (LuaState inner) {
      final widgetType = inner.optString(1, '') ?? '';
      final props = _readLuaTable(inner, 2);

      log('[Lua][$pluginId] screen.addWidget("$widgetType")');

      final type = _parseWidgetType(widgetType);
      if (type == null) {
        log('[Lua][$pluginId] unknown widget type: $widgetType');
        return 0;
      }

      final text = props['text'] as String?;
      final spacerHeight = _parseDouble(props['height'] ?? props['size']);

      PluginButtonAction action = PluginButtonAction.none;
      if (props['action'] == 'pop') {
        action = PluginButtonAction.pop;
      }

      final spec = PluginWidgetSpec(
        type: type,
        text: text,
        action: action,
        spacerHeight: spacerHeight,
      );
      widgets.add(spec);
      return 0;
    };

    ls.newTable();
    ls.pushString('addWidget');
    ls.pushDartFunction(addWidgetFn);
    ls.setTable(-3);

    ls.pushString('getId');
    ls.pushDartFunction((inner) {
      inner.pushString(screenId);
      return 1;
    });
    ls.setTable(-3);

    return 1;
  }

  // ========== NAVIGATION API ==========

  int _navigationPush(LuaState ls, String pluginId) {
    log('[Lua][$pluginId] navigation.push()');
    return 0;
  }

  int _navigationPop(LuaState ls, String pluginId) {
    log('[Lua][$pluginId] navigation.pop()');
    return 0;
  }

  // ========== PLUGIN API ==========

  int _pluginInjectUI(LuaState ls, String pluginId) {
    final slotId = ls.optString(1, '') ?? '';
    final props = _readLuaTable(ls, 2);

    if (slotId.isEmpty) {
      log('[Lua][$pluginId] plugin.injectUI: empty slotId');
      return 0;
    }

    final typeRaw = props['type'] as String? ?? 'text';
    final type = _parseWidgetType(typeRaw);
    if (type == null) {
      log('[Lua][$pluginId] plugin.injectUI: unknown type $typeRaw');
      return 0;
    }

    final text = props['text'] as String?;
    final spacerHeight = _parseDouble(props['height'] ?? props['size']);

    final spec = PluginWidgetSpec(
      type: type,
      text: text,
      spacerHeight: spacerHeight,
    );

    log('[Lua][$pluginId] plugin.injectUI("$slotId", $typeRaw)');
    for (final cb in _slotInjectCallbacks) {
      cb(pluginId, slotId, spec);
    }
    return 0;
  }

  int _pluginRegisterContentType(LuaState ls, String pluginId) {
    final typeId = ls.optString(1, '') ?? '';
    if (typeId.isEmpty) {
      log('[Lua][$pluginId] plugin.registerContentType: empty id');
      return 0;
    }

    final props = _readLuaTable(ls, 2);
    final name = props['name'] as String? ?? typeId;
    final color = props['color'] as String?;
    final isCanvas = props['isCanvas'] == true || props['renderAs'] == 'canvas';
    final canvasConfig = <String, dynamic>{};
    final canvasRaw = props['canvas'];
    if (canvasRaw is Map) {
      canvasRaw.forEach((key, value) {
        canvasConfig[key.toString()] = value;
      });
    }

    final fields = <PluginContentField>[];
    final fieldsRaw = props['fields'];
    if (fieldsRaw is List) {
      for (final fieldRaw in fieldsRaw) {
        if (fieldRaw is Map) {
          final fieldName = fieldRaw['name'] as String?;
          if (fieldName == null || fieldName.isEmpty) continue;
          final fieldType = fieldRaw['type'] as String? ?? 'string';
          final fieldLabel = fieldRaw['label'] as String? ?? fieldName;
          fields.add(
            PluginContentField(
              name: fieldName,
              type: fieldType,
              label: fieldLabel,
            ),
          );
        }
      }
    }

    final contentType = PluginContentType(
      id: typeId,
      name: name,
      pluginId: pluginId,
      color: color,
      fields: fields,
      isCanvas: isCanvas,
      canvasConfig: canvasConfig,
    );

    log('[Lua][$pluginId] plugin.registerContentType("$typeId", ${fields.length} fields${isCanvas ? ', canvas' : ''})');
    for (final cb in _contentTypeCallbacks) {
      cb(pluginId, contentType);
    }
    return 0;
  }

  int _pluginRegisterSlot(LuaState ls, String pluginId) {
    final slotId = ls.optString(1, '') ?? '';
    final props = _readLuaTable(ls, 2);
    final maxWidgets = _parseInt(props['maxWidgets']) ?? 2;

    log('[Lua][$pluginId] plugin.registerSlot("$slotId", maxWidgets=$maxWidgets)');
    return 0;
  }

  // ========== QUEST API ==========

  int _questSetVar(LuaState ls, String pluginId) {
    final name = ls.optString(1, '') ?? '';
    final value = _luaValueToString(ls, 2);
    if (name.isNotEmpty) {
      _questVars.putIfAbsent(pluginId, () => {})[name] = value;
      log('[Lua][$pluginId] quest.setVar("$name", $value)');
    }
    return 0;
  }

  int _questGetVar(LuaState ls, String pluginId) {
    final name = ls.optString(1, '') ?? '';
    final value = _questVars[pluginId]?[name];
    if (value != null) {
      _pushValue(ls, value);
      log('[Lua][$pluginId] quest.getVar("$name") = $value');
    } else {
      ls.pushNil();
      log('[Lua][$pluginId] quest.getVar("$name") = nil');
    }
    return 1;
  }

  int _questGiveItem(LuaState ls, String pluginId) {
    final itemId = ls.optString(1, '') ?? '';
    log('[Lua][$pluginId] quest.giveItem("$itemId")');
    return 0;
  }

  int _questPlaySound(LuaState ls, String pluginId) {
    final assetId = ls.optString(1, '') ?? '';
    log('[Lua][$pluginId] quest.playSound("$assetId")');
    return 0;
  }

  // ========== STORAGE API ==========

  int _storageSet(LuaState ls, String pluginId) {
    final key = ls.optString(1, '') ?? '';
    final value = _luaValueToString(ls, 2);
    if (key.isNotEmpty) {
      _storage.putIfAbsent(pluginId, () => {})[key] = value;
      log('[Lua][$pluginId] storage.set("$key", $value)');
    }
    return 0;
  }

  int _storageGet(LuaState ls, String pluginId) {
    final key = ls.optString(1, '') ?? '';
    final value = _storage[pluginId]?[key];
    if (value != null) {
      _pushValue(ls, value);
      log('[Lua][$pluginId] storage.get("$key") = $value');
    } else {
      ls.pushNil();
      log('[Lua][$pluginId] storage.get("$key") = nil');
    }
    return 1;
  }

  int _storageRemove(LuaState ls, String pluginId) {
    final key = ls.optString(1, '') ?? '';
    if (key.isNotEmpty) {
      _storage[pluginId]?.remove(key);
      log('[Lua][$pluginId] storage.remove("$key")');
    }
    return 0;
  }

  int _storageClear(LuaState ls, String pluginId) {
    _storage[pluginId]?.clear();
    log('[Lua][$pluginId] storage.clear()');
    return 0;
  }

  // ========== EVENTS API ==========

  int _eventsEmit(LuaState ls, String pluginId) {
    final targetPluginId = ls.optString(1, '') ?? '';
    final eventName = ls.optString(2, '') ?? '';
    final payload = _readLuaTable(ls, 3);

    if (targetPluginId.isEmpty || eventName.isEmpty) {
      log('[Lua][$pluginId] events.emit: missing args');
      return 0;
    }

    final payloadMap = <String, dynamic>{};
    payload.forEach((key, value) {
      payloadMap[key.toString()] = value;
    });

    log('[Lua][$pluginId] events.emit("$targetPluginId", "$eventName")');
    emitEvent(targetPluginId, eventName, payloadMap);
    return 0;
  }

  int _eventsOn(LuaState ls, String pluginId) {
    final eventName = ls.optString(1, '') ?? '';
    if (eventName.isEmpty) {
      log('[Lua][$pluginId] events.on: missing event name');
      return 0;
    }

    if (ls.type(2) == LuaType.luaFunction) {
      log('[Lua][$pluginId] events.on("$eventName")');

      onEvent(pluginId, eventName, (pid, ename, payload) {
        log('[Lua][$pluginId] event handler called: $ename');
      });
    }
    return 0;
  }

  // ========== LOGGER API ==========

  int _loggerDebug(LuaState ls, String pluginId) {
    final msg = ls.optString(1, '') ?? '';
    log('[Lua][$pluginId][DEBUG] $msg');
    return 0;
  }

  int _loggerInfo(LuaState ls, String pluginId) {
    final msg = ls.optString(1, '') ?? '';
    log('[Lua][$pluginId][INFO] $msg');
    return 0;
  }

  int _loggerWarn(LuaState ls, String pluginId) {
    final msg = ls.optString(1, '') ?? '';
    log('[Lua][$pluginId][WARN] $msg');
    return 0;
  }

  int _loggerError(LuaState ls, String pluginId) {
    final msg = ls.optString(1, '') ?? '';
    final err = ls.optString(2, '') ?? '';
    log('[Lua][$pluginId][ERROR] $msg $err');
    return 0;
  }

  // ========== HELPERS ==========

  PluginWidgetType? _parseWidgetType(String raw) {
    switch (raw) {
      case 'text':
        return PluginWidgetType.text;
      case 'button':
        return PluginWidgetType.button;
      case 'spacer':
        return PluginWidgetType.spacer;
      default:
        return null;
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String? _luaValueToString(LuaState ls, int index) {
    final t = ls.type(index);
    switch (t) {
      case LuaType.luaString:
        return ls.optString(index, '');
      case LuaType.luaNumber:
        return ls.optNumber(index, 0).toString();
      case LuaType.luaBoolean:
        return ls.toBoolean(-1).toString();
      default:
        return null;
    }
  }

  Map<String, dynamic> _readLuaTable(LuaState ls, int index) {
    final result = <String, dynamic>{};
    if (ls.type(index) != LuaType.luaTable) {
      return result;
    }

    // Индекс нормализуем ДО pushNil(): next() читает слот по абсолютному
    // номеру, а pushNil сдвигает вершину — относительный индекс уехал бы.
    final tableIndex = ls.absIndex(index);
    ls.pushNil();
    while (ls.next(tableIndex)) {
      final key = ls.toStr(-2);
      final t = ls.type(-1);
      dynamic value;
      switch (t) {
        case LuaType.luaString:
          value = ls.toStr(-1);
          break;
        case LuaType.luaNumber:
          value = ls.toNumber(-1);
          break;
        case LuaType.luaBoolean:
          value = ls.toBoolean(-1);
          break;
        case LuaType.luaTable:
          value = _readLuaTable(ls, -1);
          break;
        default:
          value = null;
      }
      if (key != null) {
        result[key] = value;
      }
      ls.pop(1);
    }
    return result;
  }
}
