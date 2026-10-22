import 'dart:isolate';

import 'package:canvas_app/plugin_host/plugin_runtime_isolate.dart';

class PluginRuntimeEvent {
  final String type;
  final String pluginId;
  final Map<String, dynamic> data;

  const PluginRuntimeEvent({
    required this.type,
    required this.pluginId,
    required this.data,
  });
}

class PluginRuntimeClient {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _starting = false;
  void Function(String message)? _logger;
  void Function(String pluginId, String callbackId)? _onEvent;
  void Function(PluginRuntimeEvent event)? _onPluginEvent;

  bool get isReady => _sendPort != null;

  Future<void> ensureStarted(void Function(String message) logger) async {
    _logger = logger;
    if (_sendPort != null || _starting) return;
    _starting = true;
    _receivePort = ReceivePort();
    _receivePort!.listen(_handleMessage);
    _isolate = await Isolate.spawn(
      pluginRuntimeIsolateEntry,
      _receivePort!.sendPort,
    );
  }

  void _handleMessage(dynamic message) {
    if (message is Map && message['type'] == 'ready') {
      _sendPort = message['port'] as SendPort?;
      _starting = false;
      _logger?.call('[PluginRuntime] ready');
      return;
    }
    if (message is Map && message['type'] == 'log') {
      final text = message['message']?.toString();
      if (text != null) {
        _logger?.call(text);
      }
    }
    if (message is Map && message['type'] == 'event') {
      final pluginId = message['pluginId']?.toString();
      final callbackId = message['callbackId']?.toString();
      if (pluginId != null && callbackId != null) {
        _onEvent?.call(pluginId, callbackId);
      }
    }
    if (message is Map) {
      final eventType = message['type']?.toString();
      if (eventType != null &&
          eventType != 'log' &&
          eventType != 'event' &&
          eventType != 'ready') {
        final pluginId = message['pluginId']?.toString() ?? '';
        _onPluginEvent?.call(
          PluginRuntimeEvent(
            type: eventType,
            pluginId: pluginId,
            data: Map<String, dynamic>.from(message),
          ),
        );
      }
    }
  }

  void loadScript(String pluginId, String scriptText) {
    _send({
      'type': 'load',
      'pluginId': pluginId,
      'scriptText': scriptText,
    });
  }

  void loadCanvasScript(String pluginId, String scriptText) {
    _send({
      'type': 'load_canvas',
      'pluginId': pluginId,
      'scriptText': scriptText,
    });
  }

  void call(
    String pluginId,
    String functionName, {
    List<Object?>? args,
  }) {
    _send({
      'type': 'call',
      'pluginId': pluginId,
      'function': functionName,
      'args': args ?? <Object?>[],
    });
  }

  void callWithQuestId(
    String pluginId,
    String functionName,
    String questId,
  ) {
    _send({
      'type': 'call_with_quest_id',
      'pluginId': pluginId,
      'function': functionName,
      'questId': questId,
    });
  }

  void registerCallback(String pluginId, String callbackId) {
    _send({
      'type': 'register_callback',
      'pluginId': pluginId,
      'callbackId': callbackId,
    });
  }

  void emitEvent(String pluginId, String callbackId) {
    _send({
      'type': 'event',
      'pluginId': pluginId,
      'callbackId': callbackId,
    });
  }

  void emitPluginEvent(
    String targetPluginId,
    String eventName,
    Map<String, dynamic> payload,
  ) {
    _send({
      'type': 'plugin_event',
      'pluginId': targetPluginId,
      'targetPluginId': targetPluginId,
      'eventName': eventName,
      'payload': payload,
    });
  }

  void disposePlugin(String pluginId) {
    _send({'type': 'dispose', 'pluginId': pluginId});
  }

  void flushStorage(String pluginId) {
    _send({'type': 'flush_storage', 'pluginId': pluginId});
  }

  void setEventHandler(void Function(String pluginId, String callbackId) handler) {
    _onEvent = handler;
  }

  void setPluginEventHandler(void Function(PluginRuntimeEvent event) handler) {
    _onPluginEvent = handler;
  }

  void _send(Map<String, Object?> message) {
    if (_sendPort == null) return;
    _sendPort!.send(message);
  }

  void dispose() {
    _send({'type': 'shutdown'});
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}
