/// Какие плагины реально поставлены и что они добавляют в редактор.
///
/// Rust-хост один на процесс и знает только то, что в него поставили, а
/// ставит его игровая сессия. Редактор к сессии отношения не имеет, поэтому
/// список типов контента приходится готовить здесь: сначала синхронизировать
/// активные пакеты ([syncPluginPackages] идемпотентен), затем спросить хост.
/// Без этого шага «Лавка» и «Замок» появились бы в меню контента только после
/// первого запуска любого квеста.
library;

import 'dart:io';

import 'package:canvas_app/features/plugins/models/plugin_content_type.dart';
import 'package:canvas_app/features/plugins/models/plugin_entry.dart';
import 'package:canvas_app/features/plugins/providers/plugin_registry_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/engine/plugin_host.dart';
import 'package:mnd_player/plugin/plugin_packages.dart';
import 'package:path/path.dart' as p;

/// Каталоги включённых пакетов нового формата (`plugin.json` + Lua).
///
/// Отключённый плагин в список не попадает — переключатель на экране
/// «Плагины» значит что-то реальное.
Future<List<String>> enabledPluginPackageDirs(List<PluginEntry> registry) async {
  final dirs = <String>[];
  for (final entry in registry.where((entry) => entry.enabled)) {
    if (entry.localPath.isEmpty) continue;
    if (await File(p.join(entry.localPath, 'plugin.json')).exists()) {
      dirs.add(entry.localPath);
    }
  }
  return dirs;
}

/// Типы контента установленных плагинов для меню «добавить контент».
final pluginContentTypesProvider =
    FutureProvider<List<PluginContentType>>((ref) async {
      final registry = ref.watch(pluginRegistryProvider).valueOrNull;
      // Реестр ещё читается — пустой список, watch пересоберёт провайдер.
      if (registry == null) return const [];
      try {
        final dirs = await enabledPluginPackageDirs(registry);
        if (dirs.isEmpty) return const [];
        await syncPluginPackages(dirs);
        return [
          for (final type in await MeanderPluginHost.contentTypes())
            PluginContentType.fromHostJson(type),
        ];
      } catch (error) {
        // Нет нативной библиотеки или битый пакет: редактор обязан жить и
        // без плагинных типов, а не падать на открытии меню контента.
        debugPrint('[Plugins] content types не прочитаны: $error');
        return const [];
      }
    });

/// Тип контента по полному имени (`<pluginId>:<тип>`) из уже прочитанного
/// списка — значения ждут в кэше провайдера, синхронно.
///
/// Экран, который им пользуется, обязан следить за [pluginContentTypesProvider]
/// в `build`, иначе карточка айтема останется без подписи.
PluginContentType? findPluginContentType(WidgetRef ref, String? typeId) {
  if (typeId == null || typeId.isEmpty) return null;
  for (final type
      in ref.read(pluginContentTypesProvider).valueOrNull ?? const []) {
    if (type.id == typeId) return type;
  }
  return null;
}
