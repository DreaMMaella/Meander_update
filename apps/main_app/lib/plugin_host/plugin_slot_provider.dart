import 'package:canvas_app/features/plugins/providers/plugin_registry_provider.dart';
import 'package:canvas_app/plugin_host/plugin_host_provider.dart';
import 'package:canvas_app/plugin_host/plugin_ui_spec.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pluginSlotWidgetsProvider = Provider.family<List<PluginWidgetSpec>, String>(
  (ref, slotId) {
    // Recompute when plugin registry changes.
    ref.watch(pluginRegistryProvider);
    final host = ref.read(pluginHostProvider);
    return host.getSlotWidgets(slotId);
  },
);
