import 'dart:io';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/services/talker_service.dart';
import 'package:canvas_app/core/services/deep_link_service.dart';
import 'package:canvas_app/features/plugins/models/plugin_entry.dart';
import 'package:canvas_app/plugin_host/canvas/display_object.dart';
import 'package:canvas_app/plugin_host/canvas/plugin_canvas_screen.dart';
import 'package:canvas_app/plugin_host/plugin_content_type.dart';
import 'package:canvas_app/plugin_host/plugin_manifest.dart';
import 'package:canvas_app/plugin_host/plugin_runtime_client.dart';
import 'package:canvas_app/plugin_host/plugin_policy.dart';
import 'package:canvas_app/plugin_host/plugin_screen.dart';
import 'package:canvas_app/plugin_host/plugin_ui_spec.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class PluginHostService {
  PluginHostService();

  final List<PluginEntry> _activePlugins = [];
  final Map<String, PluginManifest> _manifests = {};
  final Map<String, Set<String>> _scriptFunctions = {};
  final Map<String, _ScriptIntents> _scriptIntents = {};
  final Map<String, List<PluginWidgetSpec>> _slotWidgets = {};
  final Map<String, PluginContentType> _contentTypes = {};
  final PluginRuntimeClient _runtime = PluginRuntimeClient();
  int _callbackSeq = 0;
  final Map<String, String> _currentQuestIds = {};

  bool get isRuntimeActive => _runtime.isReady;

  List<PluginEntry> get activePlugins => List.unmodifiable(_activePlugins);

  List<PluginWidgetSpec> getSlotWidgets(String slotId) {
    return List.unmodifiable(_slotWidgets[slotId] ?? const []);
  }

  List<PluginContentType> get contentTypes =>
      List.unmodifiable(_contentTypes.values);

  void _log(String message) {
    debugPrint(message);
    talker.log(message);
  }

  void updateActivePlugins(List<PluginEntry> next) {
    _runtime.ensureStarted(_log);
    _runtime.setEventHandler(_handleRuntimeEvent);
    _runtime.setPluginEventHandler(_handlePluginEvent);

    final previousIds = _activePlugins.map((plugin) => plugin.id).toSet();
    final nextIds = next.map((plugin) => plugin.id).toSet();

    final added = next.where((plugin) => !previousIds.contains(plugin.id));
    final removed =
        _activePlugins.where((plugin) => !nextIds.contains(plugin.id));

    _activePlugins
      ..clear()
      ..addAll(next);

    if (added.isNotEmpty) {
      for (final plugin in added) {
        _log('[PluginHost] enabled: ${plugin.id}');
      }
    }
    if (removed.isNotEmpty) {
      for (final plugin in removed) {
        _log('[PluginHost] disabled: ${plugin.id}');
        _runtime.disposePlugin(plugin.id);
      }
    }
    if (added.isEmpty && removed.isEmpty) {
      _log('[PluginHost] active plugins unchanged (${next.length})');
    }

    _loadManifests();
  }

  void logBootstrap() {
    _runtime.ensureStarted(_log);
    _runtime.setEventHandler(_handleRuntimeEvent);
    _runtime.setPluginEventHandler(_handlePluginEvent);
    _log('[PluginHost] bootstrap (runtime inactive)');
  }

  void onQuestStart(String questId, {bool fromSave = false}) {
    final source = fromSave ? 'resume' : 'new';
    _log('[PluginHost] onQuestStart: $questId ($source)');
    _currentQuestIds['current'] = questId;

    if (_manifests.isEmpty) return;
    for (final manifest in _manifests.values) {
      if (_scriptFunctions[manifest.id]?.contains('onQuestStart') == true) {
        _runtime.callWithQuestId(manifest.id, 'onQuestStart', questId);
      }
    }
  }

  void onQuestEnd(String questId) {
    _log('[PluginHost] onQuestEnd: $questId');
    _currentQuestIds.remove('current');

    if (_manifests.isEmpty) return;
    for (final manifest in _manifests.values) {
      if (_scriptFunctions[manifest.id]?.contains('onQuestEnd') == true) {
        _runtime.call(manifest.id, 'onQuestEnd', args: <Object?>[questId]);
      }
    }
  }

  void _loadManifests() {
    _manifests.clear();
    _scriptFunctions.clear();
    _scriptIntents.clear();
    _slotWidgets.clear();
    _contentTypes.clear();

    for (final plugin in _activePlugins) {
      final manifestFile = _resolveManifestFile(plugin.localPath);
      if (manifestFile == null) {
        _log('[PluginHost] manifest not found for ${plugin.id}');
        continue;
      }
      final text = _safeRead(manifestFile);
      if (text == null) {
        _log('[PluginHost] manifest read failed for ${plugin.id}');
        continue;
      }
      final manifest = PluginManifest.parse(text);
      if (manifest == null) {
        _log('[PluginHost] manifest parse failed for ${plugin.id}');
        continue;
      }
      final validation = PluginPolicy.validatePermissions(manifest.permissions);
      if (validation.hasInvalid) {
        _log(
          '[PluginHost] invalid permissions for ${manifest.id}: ${validation.invalid.join(', ')}',
        );
      }
      final sanitized = manifest.copyWith(permissions: validation.valid);

      _manifests[sanitized.id] = sanitized;
      _log('[PluginHost] manifest loaded: ${sanitized.id}');

      final entryPath = _resolveEntryPath(manifestFile, manifest.entry);
      if (entryPath == null) {
        _log('[PluginHost] entry missing: ${manifest.entry}');
        _log('[PluginHost] hint: импортируй .plugin архив со скриптом');
        continue;
      }

      _log('[PluginHost] entry ready: ${p.basename(entryPath)}');
      _loadLuaFunctions(manifest.id, entryPath);
      final scriptText = _safeRead(File(entryPath));
      if (scriptText != null) {
        _runtime.loadScript(manifest.id, scriptText);

        if (sanitized.permissions.contains('ui')) {
          _parseAndInjectSlotWidgets(scriptText, manifest.id);
        } else {
          _log('[PluginHost] skip slots (no ui permission): ${manifest.id}');
        }
        if (sanitized.permissions.contains('quest')) {
          _parseAndRegisterContentTypes(scriptText, manifest.id);
        } else {
          _log(
            '[PluginHost] skip content types (no quest permission): ${manifest.id}',
          );
        }
      }
      _loadScriptIntents(manifest.id, entryPath);
      _invokeIfExists(manifest.id, 'onInit');
      _simulateOnInit(manifest.id);
    }
  }

  File? _resolveManifestFile(String localPath) {
    final file = File(localPath);
    if (file.existsSync() &&
        (localPath.endsWith('.yaml') || localPath.endsWith('.yml'))) {
      return file;
    }
    final dir = Directory(localPath);
    if (!dir.existsSync()) return null;
    final yaml = File(p.join(localPath, 'plugin.yaml'));
    if (yaml.existsSync()) return yaml;
    final yml = File(p.join(localPath, 'plugin.yml'));
    if (yml.existsSync()) return yml;
    return null;
  }

  String? _safeRead(File file) {
    try {
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  String? _resolveEntryPath(File manifestFile, String entry) {
    final entryFile = File(
      p.normalize(p.join(p.dirname(manifestFile.path), entry)),
    );
    if (entryFile.existsSync()) {
      return entryFile.path;
    }
    return null;
  }

  void _loadLuaFunctions(String pluginId, String entryPath) {
    final text = _safeRead(File(entryPath));
    if (text == null) {
      _log('[PluginHost] entry read failed: $entryPath');
      return;
    }
    final matches = RegExp(r'function\s+([A-Za-z0-9_]+)\s*\(')
        .allMatches(text);
    final functions = <String>{};
    for (final match in matches) {
      final name = match.group(1);
      if (name != null && name.isNotEmpty) {
        functions.add(name);
      }
    }
    _scriptFunctions[pluginId] = functions;
    if (functions.isEmpty) {
      _log('[PluginHost] no Lua functions found');
    } else {
      _log('[PluginHost] Lua functions: ${functions.join(', ')}');
    }
  }

  void _loadScriptIntents(String pluginId, String entryPath) {
    final text = _safeRead(File(entryPath));
    if (text == null) {
      return;
    }
    final intents = _ScriptIntents(
      onInitToast: _extractToastFromFunction(text, 'onInit'),
      onQuestStartToast: _extractToastFromFunction(text, 'onQuestStart'),
      questStartScreen: _parseScreenSpec(text, pluginId),
      hasQuestStartNavigation: _extractFunctionBody(text, 'onQuestStart')
              ?.contains('navigation.push') ==
          true,
    );
    _scriptIntents[pluginId] = intents;
  }

  void _invokeIfExists(String pluginId, String functionName) {
    final functions = _scriptFunctions[pluginId];
    if (functions == null) {
      _log('[PluginHost] skip $functionName (no entry)');
      return;
    }
    if (!functions.contains(functionName)) {
      _log('[PluginHost] skip $functionName (not defined)');
      return;
    }
    _log('[PluginHost] call $functionName for $pluginId');
    _runtime.call(pluginId, functionName);
  }

  void _simulateOnInit(String pluginId) {
    final intents = _scriptIntents[pluginId];
    if (intents == null) return;
    if (intents.onInitToast != null) {
      _showToast('[${pluginId.split('.').last}] ${intents.onInitToast!}');
    }
  }

  void _simulateQuestStart(String pluginId, String questId) {
    final intents = _scriptIntents[pluginId];
    if (intents == null) return;
    if (intents.onQuestStartToast != null) {
      _showToast('[${pluginId.split('.').last}] ${intents.onQuestStartToast!}');
    }
    if (intents.hasQuestStartNavigation && intents.questStartScreen != null) {
      _pushPluginScreen(pluginId, intents.questStartScreen!, questId);
      return;
    }
    if (intents.hasQuestStartNavigation) {
      _log('[PluginHost] navigation.push simulated for $pluginId');
    }
  }

  void _showToast(String message) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      _log('[PluginHost] toast skipped (no context)');
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      _log('[PluginHost] toast skipped (no messenger)');
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF2A2A2A),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleRuntimeEvent(String pluginId, String callbackId) {
    _log('[PluginHost] runtime event $pluginId:$callbackId');
  }

  void _handlePluginEvent(PluginRuntimeEvent event) {
    switch (event.type) {
      case 'toast':
        final message = event.data['message']?.toString() ?? '';
        if (message.isNotEmpty) {
          _showToast(message);
        }
        break;
      case 'screen_push':
        final screenTitle = event.data['screenTitle']?.toString() ?? '';
        final questId = _currentQuestIds['current'] ?? '';
        if (screenTitle.isNotEmpty && questId.isNotEmpty) {
          final spec = PluginScreenSpec(
            title: screenTitle,
            widgets: const [],
          );
          _pushPluginScreen(event.pluginId, spec, questId);
        }
        break;
      case 'slot_inject':
        final slotId = event.data['slotId']?.toString() ?? '';
        final widgetType = event.data['widgetType']?.toString() ?? 'text';
        final text = event.data['text']?.toString();
        if (slotId.isNotEmpty) {
          final type = _parseWidgetType(widgetType);
          if (type != null) {
            final spec = PluginWidgetSpec(type: type, text: text);
            _slotWidgets.putIfAbsent(slotId, () => []).add(spec);
            _log('[PluginHost] slot injected: $slotId ($widgetType)');
          }
        }
        break;
      case 'content_type':
        final contentTypeId = event.data['contentTypeId']?.toString() ?? '';
        final contentTypeName = event.data['contentType']?.toString() ?? '';
        if (contentTypeId.isNotEmpty) {
          final type = PluginContentType(
            id: contentTypeId,
            name: contentTypeName,
            pluginId: event.pluginId,
          );
          if (!_contentTypes.containsKey(type.id)) {
            _contentTypes[type.id] = type;
            _log('[PluginHost] content type registered: ${type.id}');
          }
        }
        break;
    }
  }

  String? _extractToastFromFunction(String text, String functionName) {
    final body = _extractFunctionBody(text, functionName);
    if (body == null) return null;
    final toastMatch = RegExp(
      r'''ui\.toast\(\s*(['"])(.*?)\1''',
      dotAll: true,
    ).firstMatch(body);
    return toastMatch?.group(2);
  }

  String? _extractFunctionBody(String text, String functionName) {
    final regex = RegExp(
      'function\\s+$functionName\\b([\\s\\S]*?)\\nend',
      dotAll: true,
    );
    final match = regex.firstMatch(text);
    return match?.group(1);
  }

  PluginScreenSpec? _parseScreenSpec(String text, String pluginId) {
    final body = _extractFunctionBody(text, 'onQuestStart');
    if (body == null) return null;

    final screenIdMatch = RegExp(
      r'''ui\.createScreen\(\s*(['"])(.*?)\1''',
    ).firstMatch(body);
    final screenId = screenIdMatch?.group(2);
    final title = screenId == null || screenId.isEmpty
        ? trf('Плагин: {p0}', {'p0': pluginId})
        : trf('Плагин: {p0}', {'p0': screenId});

    final widgetMatches = RegExp(
      r'''screen\.addWidget\(\s*(['"])(\w+)\1\s*,\s*\{([\s\S]*?)\}\s*\)''',
      dotAll: true,
    ).allMatches(body);

    final widgets = <PluginWidgetSpec>[];
    for (final match in widgetMatches) {
      final typeRaw = match.group(2) ?? '';
      final props = match.group(3) ?? '';
      final type = _parseWidgetType(typeRaw);
      if (type == null) continue;

      final textMatch = RegExp(
        r'''text\s*=\s*(['"])(.*?)\1''',
        dotAll: true,
      ).firstMatch(props);
      final textValue = textMatch?.group(2);
      final appendQuestId = props.contains('questId');

      final action = _parseButtonAction(props);
      final spacerHeight = _parseSpacerHeight(props);
      final callbackId = _parseCallbackId(pluginId, props);

      widgets.add(
        PluginWidgetSpec(
          type: type,
          text: textValue,
          appendQuestId: appendQuestId,
          action: action,
          spacerHeight: spacerHeight,
          callbackId: callbackId,
        ),
      );
    }

    if (widgets.isEmpty) return null;
    return PluginScreenSpec(title: title, widgets: widgets);
  }

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

  PluginButtonAction _parseButtonAction(String props) {
    if (props.contains('navigation.pop')) {
      return PluginButtonAction.pop;
    }
    return PluginButtonAction.none;
  }

  String? _parseCallbackId(String pluginId, String props) {
    if (!props.contains('onClick')) {
      return null;
    }
    final id = '${pluginId}_cb_${_callbackSeq++}';
    _runtime.registerCallback(pluginId, id);
    return id;
  }

  double? _parseSpacerHeight(String props) {
    final match = RegExp(r'height\\s*=\\s*(\\d+)').firstMatch(props) ??
        RegExp(r'size\\s*=\\s*(\\d+)').firstMatch(props);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
  }

  void _pushPluginScreen(
    String pluginId,
    PluginScreenSpec spec,
    String questId,
  ) {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      _log('[PluginHost] navigation.push skipped (no navigator)');
      return;
    }
    nav.push(
      MaterialPageRoute(
        builder: (context) => PluginScreen(
          spec: spec,
          questId: questId,
          pluginId: pluginId,
          onCallback: (callbackId) {
            _runtime.emitEvent(pluginId, callbackId);
          },
        ),
      ),
    );
  }

  void _parseAndInjectSlotWidgets(String text, String pluginId) {
    final matches = RegExp(
      r'''plugin\.injectUI\(\s*(['"])(.*?)\1\s*,\s*\{([\s\S]*?)\}\s*\)''',
      dotAll: true,
    ).allMatches(text);

    for (final match in matches) {
      final slotId = match.group(2);
      final props = match.group(3) ?? '';
      if (slotId == null || slotId.isEmpty) continue;
      final slotRule = PluginPolicy.slotRule(slotId);
      if (slotRule == null) {
        _log('[PluginHost] slot not allowed: $slotId (plugin $pluginId)');
        continue;
      }

      final typeMatch = RegExp(
        r'''type\s*=\s*(['"])(\w+)\1''',
      ).firstMatch(props);
      final typeRaw = typeMatch?.group(2) ?? 'text';
      final type = _parseWidgetType(typeRaw);
      if (type == null) continue;

      final textMatch = RegExp(
        r'''text\s*=\s*(['"])(.*?)\1''',
        dotAll: true,
      ).firstMatch(props);
      var textValue = textMatch?.group(2);
      if (textValue != null && textValue.length > slotRule.maxTextLength) {
        textValue = '${textValue.substring(0, slotRule.maxTextLength)}…';
      }
      final spacerHeight = _parseSpacerHeight(props);
      final safeSpacer = spacerHeight?.clamp(4, 32).toDouble();

      final bucket = _slotWidgets.putIfAbsent(slotId, () => []);
      if (bucket.length >= slotRule.maxWidgets) {
        _log('[PluginHost] slot limit reached: $slotId (plugin $pluginId)');
        continue;
      }
      bucket.add(
        PluginWidgetSpec(
          type: type,
          text: textValue,
          spacerHeight: safeSpacer,
        ),
      );
    }
  }

  void _parseAndRegisterContentTypes(String text, String pluginId) {
    final matches = RegExp(
      r'''plugin\.registerContentType\(\s*(['"])(.*?)\1\s*,\s*\{([\s\S]*?)\}\s*\)''',
      dotAll: true,
    ).allMatches(text);

    for (final match in matches) {
      final typeId = match.group(2);
      final body = match.group(3) ?? '';
      if (typeId == null || typeId.isEmpty) continue;

      final nameMatch = RegExp(
        r'''name\s*=\s*(['"])(.*?)\1''',
      ).firstMatch(body);
      final colorMatch = RegExp(
        r'''color\s*=\s*(['"])(.*?)\1''',
      ).firstMatch(body);
      final isCanvasMatch = body.contains('isCanvas') && body.contains('true');
      final renderAsMatch = RegExp(
        r'''renderAs\s*=\s*(['"])(.*?)\1''',
      ).firstMatch(body);
      final isCanvas = isCanvasMatch || renderAsMatch?.group(2) == 'canvas';

      final typeName = nameMatch?.group(2) ?? typeId;
      final color = colorMatch?.group(2);

      final fields = <PluginContentField>[];
      final fieldsBody = _extractLuaTableBody(body, 'fields');
      if (fieldsBody != null) {
        final fieldBlocks = _extractTopLevelBlocks(fieldsBody);
        for (final fieldRaw in fieldBlocks) {
          final fieldName = RegExp(
            r'''name\s*=\s*(['"])(.*?)\1''',
          ).firstMatch(fieldRaw)?.group(2);
          if (fieldName == null || fieldName.isEmpty) continue;
          final fieldType = RegExp(
            r'''type\s*=\s*(['"])(.*?)\1''',
          ).firstMatch(fieldRaw)?.group(2) ??
              'string';
          final fieldLabel = RegExp(
            r'''label\s*=\s*(['"])(.*?)\1''',
          ).firstMatch(fieldRaw)?.group(2) ??
              fieldName;
          fields.add(
            PluginContentField(
              name: fieldName,
              type: fieldType,
              label: fieldLabel,
            ),
          );
        }
      }

      final canvasConfig = <String, dynamic>{};
      final canvasBody = _extractLuaTableBody(body, 'canvas');
      if (canvasBody != null) {
        final widthMatch = RegExp(r'''width\s*=\s*(\d+)''').firstMatch(canvasBody);
        final heightMatch = RegExp(r'''height\s*=\s*(\d+)''').firstMatch(canvasBody);
        final bgMatch = RegExp(r'''backgroundColor\s*=\s*(['"])(.*?)\1''').firstMatch(canvasBody);
        if (widthMatch != null) canvasConfig['width'] = int.parse(widthMatch.group(1)!);
        if (heightMatch != null) canvasConfig['height'] = int.parse(heightMatch.group(1)!);
        if (bgMatch != null) canvasConfig['backgroundColor'] = bgMatch.group(2);
      }

      final type = PluginContentType(
        id: typeId,
        name: typeName,
        pluginId: pluginId,
        color: color,
        fields: fields,
        isCanvas: isCanvas,
        canvasConfig: canvasConfig,
      );
      if (!_contentTypes.containsKey(type.id)) {
        _contentTypes[type.id] = type;
        _log('[PluginHost] content type registered: ${type.id}');
      } else {
        _log('[PluginHost] content type duplicate: ${type.id}');
      }
    }
  }

  String? _extractLuaTableBody(String body, String key) {
    final keyIndex = body.indexOf(key);
    if (keyIndex == -1) return null;
    final braceIndex = body.indexOf('{', keyIndex);
    if (braceIndex == -1) return null;
    var depth = 0;
    for (var i = braceIndex; i < body.length; i++) {
      final char = body[i];
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) {
          return body.substring(braceIndex + 1, i);
        }
      }
    }
    return null;
  }

  List<String> _extractTopLevelBlocks(String body) {
    final blocks = <String>[];
    var depth = 0;
    var start = -1;
    for (var i = 0; i < body.length; i++) {
      final char = body[i];
      if (char == '{') {
        depth++;
        if (depth == 1) {
          start = i + 1;
        }
      } else if (char == '}') {
        if (depth == 1 && start != -1) {
          blocks.add(body.substring(start, i));
          start = -1;
        }
        depth--;
      }
    }
    return blocks;
  }

  void launchCanvas(String pluginId, {double width = 800, double height = 600}) {
    final manifest = _manifests[pluginId];
    if (manifest == null) {
      _log('[PluginHost] canvas launch failed: manifest not found for $pluginId');
      return;
    }

    final plugin = _activePlugins.where((p) => p.id == pluginId).firstOrNull;
    if (plugin == null) {
      _log('[PluginHost] canvas launch failed: plugin not found');
      return;
    }

    final manifestFile = _resolveManifestFile(plugin.localPath);
    if (manifestFile == null) {
      _log('[PluginHost] canvas launch failed: manifest file not found');
      return;
    }

    final entryPath = _resolveEntryPath(manifestFile, manifest.entry);
    if (entryPath == null) {
      _log('[PluginHost] canvas launch failed: entry not found');
      return;
    }

    final entryFile = File(entryPath);
    final scriptText = _safeRead(entryFile);
    if (scriptText == null) {
      _log('[PluginHost] canvas launch failed: script read failed');
      return;
    }

    final scene = DisplayScene(
      id: '${pluginId}_canvas',
      pluginId: pluginId,
    )..width = width
      ..height = height
      ..backgroundColor = const Color(0xFF1A1A2E);

    _runtime.loadCanvasScript(pluginId, scriptText);

    final nav = navigatorKey.currentState;
    if (nav == null) {
      _log('[PluginHost] canvas launch failed: no navigator');
      return;
    }

    nav.push(
      MaterialPageRoute(
        builder: (context) => PluginCanvasScreen(
          scene: scene,
          pluginId: pluginId,
          onClose: () {
            onQuestEnd('canvas_session');
          },
        ),
      ),
    );

    _log('[PluginHost] canvas launched for $pluginId');
  }

  void emitPluginEvent(
    String targetPluginId,
    String eventName,
    Map<String, dynamic> payload,
  ) {
    _runtime.emitPluginEvent(targetPluginId, eventName, payload);
  }
}

class _ScriptIntents {
  final String? onInitToast;
  final String? onQuestStartToast;
  final bool hasQuestStartNavigation;
  final PluginScreenSpec? questStartScreen;

  const _ScriptIntents({
    required this.onInitToast,
    required this.onQuestStartToast,
    required this.hasQuestStartNavigation,
    this.questStartScreen,
  });
}
