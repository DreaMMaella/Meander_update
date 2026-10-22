import 'package:canvas_app/features/plugins/providers/plugin_registry_provider.dart';
import 'package:canvas_app/plugin_host/plugin_host_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PluginHostRunner extends ConsumerStatefulWidget {
  final Widget child;

  const PluginHostRunner({super.key, required this.child});

  @override
  ConsumerState<PluginHostRunner> createState() => _PluginHostRunnerState();
}

class _PluginHostRunnerState extends ConsumerState<PluginHostRunner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pluginHostProvider).logBootstrap();
      _syncActivePlugins();
    });
  }

  void _syncActivePlugins() {
    final plugins = ref.read(pluginRegistryProvider).valueOrNull ?? [];
    final active = plugins.where((plugin) => plugin.enabled).toList();
    ref.read(pluginHostProvider).updateActivePlugins(active);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pluginRegistryProvider, (previous, next) {
      final active = next.valueOrNull
              ?.where((plugin) => plugin.enabled)
              .toList() ??
          [];
      ref.read(pluginHostProvider).updateActivePlugins(active);
    });

    return widget.child;
  }
}
