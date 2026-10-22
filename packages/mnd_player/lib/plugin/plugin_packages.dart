/// Установка Lua-плагинов: читает пакеты с диска, загоняет их в Rust-хост и
/// хранит снапшоты плагинных хранилищ в файлах.
///
/// Пакет — каталог с `plugin.json` и точкой входа из манифеста (`main.lua`).
/// Сама валидация манифеста, прав и лимитов живёт в ядре ([`MeanderPluginHost`]):
/// сюда доходит только «прочитать файлы и не выйти за каталог пакета».
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mnd_core/engine/plugin_host.dart';
import 'package:path/path.dart' as p;

import 'package:mnd_player/utils/file_storage.dart';

/// Итог синхронизации каталога активных пакетов с хостом.
class PluginSyncReport {
  final List<String> loaded;

  /// `путь: причина` — пакеты, которые не удалось поставить.
  final List<String> failed;
  const PluginSyncReport({this.loaded = const [], this.failed = const []});

  bool get isEmpty => loaded.isEmpty && failed.isEmpty;
}

/// Пакет, разобранный насколько удалось: манифест ещё может отвергнуть ядро.
class _PackageOnDisk {
  final String directory;
  final String id;
  final String manifestJson;
  final String source;
  const _PackageOnDisk({
    required this.directory,
    required this.id,
    required this.manifestJson,
    required this.source,
  });
}

/// Каталог переписываемых хранилищ (тот же, что у прежнего Dart-хоста).
Future<Directory> pluginStorageDir() async {
  final root = await FileStorage.getAppDirectory();
  final dir = Directory(p.join(root.path, 'plugins_storage'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

File _storageFile(Directory dir, String pluginId) =>
    File(p.join(dir.path, '$pluginId.json'));

/// Прочитать хранилище плагина с диска (пусто — если файла нет/он битый).
Future<Map<String, dynamic>> readPluginStorage(String pluginId) async {
  try {
    final dir = await pluginStorageDir();
    final file = _storageFile(dir, pluginId);
    if (!await file.exists()) return const {};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (e) {
    debugPrint('[Plugins] storage read failed for $pluginId: $e');
  }
  return const {};
}

Future<void> writePluginStorage(String pluginId, Map<String, dynamic> storage) async {
  try {
    final dir = await pluginStorageDir();
    await _storageFile(dir, pluginId).writeAsString(
      const JsonEncoder.withIndent('  ').convert(storage),
      flush: true,
    );
  } catch (e) {
    debugPrint('[Plugins] storage write failed for $pluginId: $e');
  }
}

/// Удалить плагин из хоста и стёреть его хранилище.
Future<void> uninstallPlugin(String pluginId) async {
  MeanderPluginHost.unregister(pluginId);
  try {
    final dir = await pluginStorageDir();
    final file = _storageFile(dir, pluginId);
    if (await file.exists()) await file.delete();
  } catch (e) {
    debugPrint('[Plugins] storage delete failed for $pluginId: $e');
  }
}

/// Пакет валиден достаточно, чтобы попытаться его зарегистрировать.
/// Возвращает причину отказа вместо броска — экран должен показать список
/// битых установок, а не упасть.
Future<Object> _readPackage(String directory) async {
  final dir = Directory(directory);
  if (!await dir.exists()) return 'каталога нет';

  final manifestFile = File(p.join(dir.path, 'plugin.json'));
  if (!await manifestFile.exists()) return 'нет plugin.json';
  final String manifestJson;
  final dynamic decoded;
  try {
    manifestJson = await manifestFile.readAsString();
    decoded = jsonDecode(manifestJson);
  } catch (e) {
    return 'plugin.json не читается: $e';
  }
  if (decoded is! Map) return 'plugin.json — не объект';
  final map = Map<String, dynamic>.from(decoded);
  final id = map['id'] as String?;
  final entry = map['entry'] as String?;
  if (id == null || id.trim().isEmpty) return 'манифест без id';
  if (entry == null || entry.trim().isEmpty) return 'манифест без entry';

  // entry — относительный путь внутри пакета; «..» и абсолютные пути
  // отсекает ядро, но и здесь не читаем ничего за пределами каталога.
  final entryPath = p.normalize(p.join(dir.path, entry));
  if (!p.isWithin(dir.path, entryPath)) return 'entry вне каталога пакета';
  final entryFile = File(entryPath);
  if (!await entryFile.exists()) return 'точки входа $entry нет';
  final String source;
  try {
    source = await entryFile.readAsString();
  } catch (e) {
    return 'скрипт не читается: $e';
  }

  return _PackageOnDisk(
    directory: directory,
    id: id,
    manifestJson: manifestJson,
    source: source,
  );
}

/// Пакеты standalone-сборки: `<документы>/plugins/<что-угодно>/plugin.json`.
/// main_app свои каталоги отдаёт через хук, а здесь — путь для ручной
/// установки («-skинул папку плагина — и он заработал»).
Future<List<String>> standalonePluginPackages() async {
  final root = await FileStorage.getAppDirectory();
  final dir = Directory(p.join(root.path, 'plugins'));
  if (!await dir.exists()) return const [];
  final found = <String>[];
  try {
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      if (await File(p.join(entity.path, 'plugin.json')).exists()) {
        found.add(entity.path);
      }
    }
  } catch (e) {
    debugPrint('[Plugins] список пакетов не прочитан: $e');
  }
  found.sort();
  return found;
}

/// Синхронизировать хост со списком активных пакетов.
///
/// Лишние (снятые/отключённые) плагины выгружаются, новые ставятся вместе с
/// их хранилищем с диска. Идемпотентно: повторный вызов с тем же списком
/// перезаливает скрипты (правку плагина видно сразу) и не трогает остальных.
Future<PluginSyncReport> syncPluginPackages(List<String> packageDirs) async {
  final loaded = <String>[];
  final failed = <String>[];

  final packages = <_PackageOnDisk>[];
  for (final directory in packageDirs) {
    final read = await _readPackage(directory);
    if (read is _PackageOnDisk) {
      packages.add(read);
    } else {
      failed.add('$directory: $read');
    }
  }

  // Хост отвергает дубликат id, поэтому перед установкой снимаем всё,
  // что в списке отсутствует (плагин отключили), и что переустанавливается
  // (правку скрипта должно быть видно сразу, без перезапуска приложения).
  final installed = <String>{
    for (final manifest in await MeanderPluginHost.manifests())
      if (manifest['id'] is String) manifest['id'] as String,
  };
  final wanted = packages.map((package) => package.id).toSet();
  for (final id in installed.difference(wanted)) {
    MeanderPluginHost.unregister(id);
  }

  for (final package in packages) {
    try {
      MeanderPluginHost.unregister(package.id);
      final result = await MeanderPluginHost.register(
        manifestJson: package.manifestJson,
        source: package.source,
        storage: await readPluginStorage(package.id),
      );
      if (result.ok) {
        loaded.add(package.id);
      } else {
        failed.add('${package.directory}: ${result.errors.join('; ')}');
      }
    } catch (e) {
      failed.add('${package.directory}: $e');
    }
  }

  return PluginSyncReport(loaded: loaded, failed: failed);
}
