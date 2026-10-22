import 'package:canvas_app/plugin_host/plugin_host_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pluginHostProvider = Provider<PluginHostService>((ref) {
  return PluginHostService();
});
