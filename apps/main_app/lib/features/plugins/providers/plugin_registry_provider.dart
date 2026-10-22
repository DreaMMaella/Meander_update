import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:canvas_app/features/plugins/models/plugin_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final pluginRegistryProvider =
    AsyncNotifierProvider<PluginRegistry, List<PluginEntry>>(
  PluginRegistry.new,
);

class PluginRegistry extends AsyncNotifier<List<PluginEntry>> {
  static const _prefsKey = 'installed_plugins_v1';

  @override
  Future<List<PluginEntry>> build() async {
    return _load();
  }

  Future<List<PluginEntry>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map<String, Object?>>()
          .map(PluginEntry.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<PluginEntry> plugins) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(plugins.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, payload);
  }

  Future<Directory> _ensurePluginsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'plugins'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _fallbackId(String fileName) {
    final base = fileName.replaceAll(RegExp(r'[^\w\-\.]+'), '_');
    return 'local.$base';
  }

  Future<PluginEntry> importPluginFile(File sourceFile) async {
    final pluginsDir = await _ensurePluginsDir();
    final fileName = p.basename(sourceFile.path);
    final extension = p.extension(fileName).toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final packageDir = Directory(
      p.join(pluginsDir.path, '${timestamp}_${p.basenameWithoutExtension(fileName)}'),
    );
    if (!await packageDir.exists()) {
      await packageDir.create(recursive: true);
    }

    String? manifestText;
    String? manifestPath;
    var manifestIsJson = false;

    if (extension == '.yaml' || extension == '.yml') {
      final manifestFile = File(p.join(packageDir.path, 'plugin.yaml'));
      await sourceFile.copy(manifestFile.path);
      manifestText = await manifestFile.readAsString();
      manifestPath = manifestFile.path;
    } else if (extension == '.json') {
      final manifestFile = File(p.join(packageDir.path, 'plugin.json'));
      await sourceFile.copy(manifestFile.path);
      manifestText = await manifestFile.readAsString();
      manifestPath = manifestFile.path;
      manifestIsJson = true;
    } else if (extension == '.zip' || extension == '.plugin') {
      final bytes = await sourceFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestRelPath = _findManifestPathInArchive(archive);
      for (final file in archive) {
        final name = file.name;
        if (name.isEmpty) continue;
        final targetPath = p.normalize(p.join(packageDir.path, name));
        if (!p.isWithin(packageDir.path, targetPath)) {
          continue;
        }
        if (file.isFile) {
          final output = File(targetPath);
          await output.parent.create(recursive: true);
          await output.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(targetPath).create(recursive: true);
        }
      }
      if (manifestRelPath != null) {
        final full = p.normalize(p.join(packageDir.path, manifestRelPath));
        final manifestFile = File(full);
        if (await manifestFile.exists()) {
          manifestText = await manifestFile.readAsString();
          manifestPath = manifestFile.path;
          manifestIsJson = manifestRelPath.endsWith('.json');
        }
      }
    } else {
      final copied = await sourceFile.copy(
        p.join(packageDir.path, fileName),
      );
      if (copied.path.endsWith('.yaml') || copied.path.endsWith('.yml')) {
        manifestText = await copied.readAsString();
        manifestPath = copied.path;
      } else if (copied.path.endsWith('.json')) {
        manifestText = await copied.readAsString();
        manifestPath = copied.path;
        manifestIsJson = true;
      }
    }

    final fallbackId = _fallbackId(fileName);
    final fallbackName = p.basenameWithoutExtension(fileName);
    final resolvedRoot =
        manifestPath == null ? packageDir.path : p.dirname(manifestPath);

    final entry = manifestText == null
        ? PluginEntry(
            id: fallbackId,
            name: fallbackName,
            version: '0.1.0',
            localPath: resolvedRoot,
            enabled: true,
            installedAt: DateTime.now(),
          )
        : manifestIsJson
        ? PluginEntry.fromManifestJson(
            manifestJson: manifestText,
            fallbackId: fallbackId,
            fallbackName: fallbackName,
            localPath: resolvedRoot,
          )
        : PluginEntry.fromManifestText(
            manifestText: manifestText,
            fallbackId: fallbackId,
            fallbackName: fallbackName,
            localPath: resolvedRoot,
          );

    final plugins = List<PluginEntry>.from(state.valueOrNull ?? []);
    final existingIndex = plugins.indexWhere((p) => p.id == entry.id);
    if (existingIndex >= 0) {
      plugins[existingIndex] = entry.copyWith(
        enabled: plugins[existingIndex].enabled,
        installedAt: DateTime.now(),
      );
    } else {
      plugins.add(entry);
    }

    state = AsyncData(plugins);
    await _save(plugins);
    return entry;
  }

  Future<void> togglePlugin(String id, bool enabled) async {
    final plugins = List<PluginEntry>.from(state.valueOrNull ?? []);
    final index = plugins.indexWhere((p) => p.id == id);
    if (index == -1) return;
    plugins[index] = plugins[index].copyWith(enabled: enabled);
    state = AsyncData(plugins);
    await _save(plugins);
  }

  Future<void> removePlugin(String id) async {
    final plugins = List<PluginEntry>.from(state.valueOrNull ?? []);
    final index = plugins.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final removed = plugins.removeAt(index);
    state = AsyncData(plugins);
    await _save(plugins);
    final root = Directory(removed.localPath);
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  String? _findManifestPathInArchive(Archive archive) {
    // Новый формат (plugin.json + Lua) важнее старого YAML-наследия:
    // пакет с обоими манифестами считается пакетом Rust-хоста.
    for (final file in archive) {
      final name = file.name;
      if (name.endsWith('plugin.json')) return name;
    }
    for (final file in archive) {
      final name = file.name;
      if (name.endsWith('plugin.yaml') || name.endsWith('plugin.yml')) {
        return name;
      }
    }
    return null;
  }
}
