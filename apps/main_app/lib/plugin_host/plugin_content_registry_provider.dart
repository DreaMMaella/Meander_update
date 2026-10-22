import 'package:canvas_app/features/plugins/providers/plugin_registry_provider.dart';
import 'package:canvas_app/plugin_host/plugin_content_type.dart';
import 'package:canvas_app/plugin_host/plugin_host_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pluginContentTypesProvider =
    Provider<List<PluginContentType>>((ref) {
  ref.watch(pluginRegistryProvider);
  final host = ref.read(pluginHostProvider);
  return host.contentTypes;
});
