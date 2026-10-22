import 'dart:isolate';

import 'package:canvas_app/plugin_host/lua_runtime_adapter.dart';

void pluginRuntimeIsolateEntry(SendPort mainPort) {
  final commandPort = ReceivePort();
  mainPort.send({'type': 'ready', 'port': commandPort.sendPort});

  void log(String message) {
    mainPort.send({'type': 'log', 'message': message});
  }

  final callbacks = <String, Set<String>>{};
  final runtime = LuaRuntimeAdapter(log);

  runtime.addToastCallback((pluginId, message) {
    mainPort.send({
      'type': 'toast',
      'pluginId': pluginId,
      'message': message,
    });
  });

  runtime.addScreenCallback((pluginId, screen) {
    mainPort.send({
      'type': 'screen_push',
      'pluginId': pluginId,
      'screenTitle': screen.title,
      'widgetCount': screen.widgets.length,
    });
  });

  runtime.addSlotInjectCallback((pluginId, slotId, widget) {
    mainPort.send({
      'type': 'slot_inject',
      'pluginId': pluginId,
      'slotId': slotId,
      'widgetType': widget.type.name,
      'text': widget.text,
    });
  });

  runtime.addContentTypeCallback((pluginId, type) {
    mainPort.send({
      'type': 'content_type',
      'pluginId': pluginId,
      'contentTypeId': type.id,
      'contentType': type.name,
      'fieldCount': type.fields.length,
    });
  });

  commandPort.listen((message) {
    if (message is! Map) return;
    final type = message['type'];
    if (type == 'shutdown') {
      log('[PluginRuntime] shutdown');
      commandPort.close();
      return;
    }

    final pluginId = message['pluginId']?.toString();
    if (pluginId == null) return;

    switch (type) {
      case 'load':
        final script = message['scriptText']?.toString() ?? '';
        callbacks[pluginId] = <String>{};
        runtime.load(pluginId, script);
        break;
      case 'load_canvas':
        final script = message['scriptText']?.toString() ?? '';
        callbacks[pluginId] = <String>{};
        runtime.load(pluginId, script);
        break;
      case 'dispose':
        callbacks.remove(pluginId);
        runtime.disposePlugin(pluginId);
        log('[PluginRuntime] disposed $pluginId');
        break;
      case 'register_callback':
        final id = message['callbackId']?.toString();
        if (id == null) return;
        callbacks.putIfAbsent(pluginId, () => <String>{}).add(id);
        log('[PluginRuntime] callback registered $pluginId:$id');
        break;
      case 'call':
        final fn = message['function']?.toString();
        if (fn == null) return;
        if (!runtime.hasFunction(pluginId, fn)) {
          log('[PluginRuntime] skip $pluginId.$fn (not defined)');
          return;
        }
        final args = message['args'] as List<Object?>?;
        runtime.call(pluginId, fn, args: args);
        break;
      case 'call_with_quest_id':
        final fn = message['function']?.toString();
        final questId = message['questId']?.toString();
        if (fn == null || questId == null) return;
        if (!runtime.hasFunction(pluginId, fn)) {
          log('[PluginRuntime] skip $pluginId.$fn (not defined)');
          return;
        }
        runtime.callWithQuestId(pluginId, fn, questId);
        break;
      case 'event':
        final id = message['callbackId']?.toString();
        if (id == null) return;
        final set = callbacks[pluginId] ?? <String>{};
        if (!set.contains(id)) {
          log('[PluginRuntime] unknown callback $pluginId:$id');
          return;
        }
        log('[PluginRuntime] event $pluginId:$id');
        mainPort.send({
          'type': 'event',
          'pluginId': pluginId,
          'callbackId': id,
        });
        break;
      case 'plugin_event':
        final targetPluginId = message['targetPluginId']?.toString();
        final eventName = message['eventName']?.toString();
        final payload = message['payload'] as Map<String, dynamic>?;
        if (targetPluginId == null || eventName == null) return;
        runtime.emitEvent(targetPluginId, eventName, payload ?? {});
        break;
      case 'flush_storage':
        runtime.flushStorage(pluginId);
        break;
    }
  });
}
