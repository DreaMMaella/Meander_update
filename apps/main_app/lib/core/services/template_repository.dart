import 'dart:async';
import 'dart:convert';

import 'package:canvas_app/core/services/template_bundler.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/models/template_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mnd_core/utils/quest_paths.dart';

/// Локальный репозиторий шаблонов.
///
/// Хранит шаблоны в JSON-индексах через [FileStorage]:
/// * глобальные: `app/templates/templates.json` + `app/templates/assets/<sha>`
/// * квест-локальные: `quests/<questId>/res/templates.json`
///
/// Формат файла-индекса:
/// ```jsonc
/// {
///   "schemaVersion": 1,
///   "templates": [ /* массив TemplateItem.toJson() */ ]
/// }
/// ```
///
/// Формат экспорта `.mndtpl` (наружу) — ZIP-архив (см. [TemplateBundler]).
class TemplateRepository {
  static const String _globalDir = 'app/templates';
  static const String _globalFile = 'app/templates/templates.json';
  static const String _questFileRelative = 'res/templates.json';

  static const int _currentFileVersion = 1;

  /// Расширение для экспорта шаблона в виде отдельного файла.
  static const String exportExtension = 'mndtpl';

  TemplateRepository();

  /// =================== ЧТЕНИЕ ===================

  /// Список глобальных шаблонов (общих для всех квестов).
  Future<List<TemplateItem>> loadGlobal() {
    return FileStorage.synchronized('templates_global', () async {
      await _ensureGlobalDir();
      if (!await FileStorage.exists(_globalFile)) return <TemplateItem>[];
      try {
        final json = await FileStorage.readJsonFile(_globalFile);
        return _parseTemplatesList(json);
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[TemplateRepository] failed to read global templates: $e');
        }
        return <TemplateItem>[];
      }
    });
  }

  /// Список шаблонов конкретного квеста.
  Future<List<TemplateItem>> loadForQuest(String questId) {
    final path = _questPath(questId);
    return FileStorage.synchronized('templates_quest_$questId', () async {
      if (!await FileStorage.exists(path)) return <TemplateItem>[];
      try {
        final json = await FileStorage.readJsonFile(path);
        return _parseTemplatesList(json);
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[TemplateRepository] failed to read quest templates: $e');
        }
        return <TemplateItem>[];
      }
    });
  }

  /// Объединённый список «глобальные + квест-локальные» (квестовые в начале).
  Future<List<TemplateItem>> loadCombined(String questId) async {
    final results = await Future.wait([loadForQuest(questId), loadGlobal()]);
    return [...results[0], ...results[1]];
  }

  /// =================== ЗАПИСЬ ===================

  /// Добавить (или обновить) шаблон в глобальный список.
  ///
  /// Если у шаблона есть упакованные `assets[]` и в [bytesBySha] передано
  /// содержимое, ассеты будут также записаны в `app/templates/assets/`
  /// (с дедупликацией по sha256).
  Future<void> upsertGlobal(
    TemplateItem template, {
    Map<String, Uint8List>? bytesBySha,
  }) {
    return FileStorage.synchronized('templates_global', () async {
      await _ensureGlobalDir();

      if (template.assets.isNotEmpty && bytesBySha != null) {
        await TemplateBundler.writeAssetsToGlobalStore(
          assets: template.assets,
          bytesBySha: bytesBySha,
        );
      }

      final current = await _readListLocked(_globalFile);
      _upsert(current, template);
      await _writeList(_globalFile, current);
    });
  }

  /// Добавить (или обновить) шаблон в квест.
  Future<void> upsertToQuest(String questId, TemplateItem template) {
    final path = _questPath(questId);
    return FileStorage.synchronized('templates_quest_$questId', () async {
      final current = await _readListLocked(path);
      _upsert(current, template);
      await _writeList(path, current);
    });
  }

  /// Удалить шаблон по id из глобального списка.
  /// Связанные ассеты в `app/templates/assets/` не трогаются — они могут
  /// использоваться другими шаблонами (sha-дедупликация).
  Future<bool> deleteGlobal(String id) {
    return FileStorage.synchronized('templates_global', () async {
      if (!await FileStorage.exists(_globalFile)) return false;
      final current = await _readListLocked(_globalFile);
      final lengthBefore = current.length;
      current.removeWhere((t) => t.id == id);
      if (current.length == lengthBefore) return false;
      await _writeList(_globalFile, current);
      return true;
    });
  }

  /// Удалить шаблон по id из квеста.
  Future<bool> deleteFromQuest(String questId, String id) {
    final path = _questPath(questId);
    return FileStorage.synchronized('templates_quest_$questId', () async {
      if (!await FileStorage.exists(path)) return false;
      final current = await _readListLocked(path);
      final lengthBefore = current.length;
      current.removeWhere((t) => t.id == id);
      if (current.length == lengthBefore) return false;
      await _writeList(path, current);
      return true;
    });
  }

  /// Перенести шаблон между scope.
  Future<TemplateItem?> moveScope({
    required TemplateItem template,
    required TemplateScope from,
    required TemplateScope to,
    String? questId,
  }) async {
    if (from == to) return template;
    if (from == TemplateScope.global) {
      await deleteGlobal(template.id);
    } else {
      if (questId == null) {
        throw ArgumentError('questId required for quest scope');
      }
      await deleteFromQuest(questId, template.id);
    }
    if (to == TemplateScope.global) {
      // При переносе в global вытащим ассеты из квеста, если они есть и
      // ещё не упакованы.
      if (template.assets.isEmpty && questId != null) {
        final collected = await TemplateBundler.collectAssetsForTemplate(
          template: template,
          questId: questId,
        );
        await upsertGlobal(
          collected.template,
          bytesBySha: collected.bytesBySha,
        );
      } else {
        await upsertGlobal(template);
      }
    } else {
      if (questId == null) {
        throw ArgumentError('questId required for quest scope');
      }
      await upsertToQuest(questId, template);
    }
    return template;
  }

  /// =================== ИМПОРТ / ЭКСПОРТ ===================

  /// Экспорт шаблона в `.mndtpl` (ZIP с ассетами).
  ///
  /// [questId] — откуда подтягивать ассеты, если их нет в самом шаблоне.
  /// Если [includeAssets] = false, ZIP всё равно будет создан, но без
  /// файлов ресурсов (только `template.json` и `manifest.json`).
  Future<String?> exportToFile(
    TemplateItem template, {
    String? questId,
    bool includeAssets = true,
  }) async {
    final List<int> bytes;
    if (includeAssets) {
      bytes = await TemplateBundler.buildBundle(
        template: template,
        questId: questId,
      );
    } else {
      // Чистый ZIP без ассетов: убираем assets из template.json.
      final naked = template.copyWith(assets: const []);
      bytes = await TemplateBundler.buildBundle(template: naked, questId: null);
    }
    if (bytes.isEmpty) return null;

    final safeName = _sanitizeFileName(template.name);
    final suggestedName = '$safeName.$exportExtension';

    final saveAsUri = await FilePicker.saveFile(
      dialogTitle: tr('Сохранить шаблон'),
      fileName: suggestedName,
      bytes: Uint8List.fromList(bytes),
      type: FileType.custom,
      allowedExtensions: [exportExtension],
    );
    if (saveAsUri == null) return null;

    // file_picker 12 сам записывает переданные bytes. Возвращаем путь для
    // file:// URI; для content:// и т.п. — строку URI.
    final saveAsPath = saveAsUri.scheme == 'file'
        ? saveAsUri.toFilePath()
        : saveAsUri.toString();
    return saveAsPath;
  }

  /// Импорт шаблона из файла (FilePicker).
  ///
  /// Поддерживает оба формата:
  /// 1. `.mndtpl` как ZIP (новый, с ассетами).
  /// 2. `.mndtpl`/`.json` как чистый JSON (старый формат) — для обратной
  ///    совместимости.
  Future<TemplateImportResult?> importFromFile() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: tr('Импорт шаблона'),
      type: FileType.custom,
      allowedExtensions: [exportExtension, 'json', 'zip'],
    );
    if (files.isEmpty) return null;

    final picked = files.single;
    Uint8List? bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      return null;
    }

    // 1. Сначала пробуем как ZIP.
    final asBundle = await TemplateBundler.readBundle(bytes);
    if (asBundle != null) {
      return TemplateImportResult(
        template: asBundle.template,
        bytesBySha: asBundle.bytesBySha,
      );
    }

    // 2. Fallback — чистый JSON.
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final tpl = _tryParseLegacyJsonImport(text);
      if (tpl != null) {
        return TemplateImportResult(template: tpl, bytesBySha: const {});
      }
    } catch (_) {}

    return null;
  }

  /// Парсит «голый» JSON (legacy) вида:
  /// ```jsonc
  /// {"format":"meander.template","fileVersion":1,"template":{...}}
  /// ```
  TemplateItem? _tryParseLegacyJsonImport(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      final tpl = decoded['template'];
      if (tpl is! Map) return null;
      return TemplateItem.fromJson(Map<String, dynamic>.from(tpl));
    } catch (_) {
      return null;
    }
  }

  /// =================== ВНУТРЕННЕЕ ===================

  Future<void> _ensureGlobalDir() async {
    await FileStorage.createFolder(_globalDir);
  }

  String _questPath(String questId) =>
      QuestPaths.questFile(questId, _questFileRelative);

  void _upsert(List<TemplateItem> list, TemplateItem item) {
    final idx = list.indexWhere((t) => t.id == item.id);
    if (idx >= 0) {
      // Обновляем существующий шаблон: инкрементируем contentVersion, если
      // payload изменился (по сравнению с тем, что лежит в файле). Это
      // позволяет linked-инстансам распознавать «мастер обновился» и
      // ре-рендериться через `TemplateInstanceResolver`.
      final previous = list[idx];
      final payloadChanged = !_payloadEquals(previous.payload, item.payload);
      final assetsChanged = !_assetsEquals(previous.assets, item.assets);
      final nextVersion = (payloadChanged || assetsChanged)
          ? previous.contentVersion + 1
          : previous.contentVersion;
      list[idx] = item.copyWith(
        updatedAt: DateTime.now(),
        contentVersion: nextVersion,
      );
    } else {
      // Новый шаблон. Если contentVersion не задан явно — стартует с 1
      // (default в конструкторе).
      list.add(item.copyWith(updatedAt: DateTime.now()));
    }
  }

  /// Глубокое сравнение payload через JSON-канонизацию.
  /// Дорого, но вызывается только на запись, а шаблоны не гигантские.
  bool _payloadEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (identical(a, b)) return true;
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }

  bool _assetsEquals(List<TemplateAsset> a, List<TemplateAsset> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.relativePath != y.relativePath ||
          x.sha256 != y.sha256 ||
          x.size != y.size ||
          x.storageFileName != y.storageFileName) {
        return false;
      }
    }
    return true;
  }

  Future<List<TemplateItem>> _readListLocked(String path) async {
    if (!await FileStorage.exists(path)) return <TemplateItem>[];
    try {
      final json = await FileStorage.readJsonFile(path);
      return _parseTemplatesList(json);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[TemplateRepository] read failed at $path: $e');
      }
      return <TemplateItem>[];
    }
  }

  List<TemplateItem> _parseTemplatesList(Map<String, dynamic> raw) {
    final list = raw['templates'];
    if (list is! List) return <TemplateItem>[];
    final result = <TemplateItem>[];
    for (final entry in list) {
      if (entry is Map<String, dynamic>) {
        try {
          result.add(TemplateItem.fromJson(entry));
        } catch (_) {
          /* пропускаем битый */
        }
      } else if (entry is Map) {
        try {
          result.add(TemplateItem.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {}
      }
    }
    return result;
  }

  Future<void> _writeList(String path, List<TemplateItem> list) async {
    final data = <String, dynamic>{
      'schemaVersion': _currentFileVersion,
      'templates': list.map((t) => t.toJson()).toList(),
    };
    await FileStorage.writeJsonFile(path, data);
  }

  String _sanitizeFileName(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    if (cleaned.isEmpty) return 'template';
    if (cleaned.length > 64) return cleaned.substring(0, 64);
    return cleaned;
  }
}

/// Результат импорта `.mndtpl` (шаблон + опционально его ассеты в памяти).
class TemplateImportResult {
  final TemplateItem template;

  /// Содержимое ассетов по sha256.
  /// Пустой Map, если шаблон импортирован из legacy-JSON или без ассетов.
  final Map<String, Uint8List> bytesBySha;

  const TemplateImportResult({
    required this.template,
    required this.bytesBySha,
  });
}
