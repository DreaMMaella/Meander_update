import 'package:mnd_core/engine/quest_resource_index.dart';

/// Тип скрипта-ресурса (для визуального различения в библиотеке).
enum ScriptType { event, condition, generic }

/// Режим отображения списка ресурсов.
enum ViewType { grid, list }

/// Описание одного файла-ресурса квеста (картинка, аудио, шрифт или скрипт).
class ResourceFile {
  final String id;

  /// Stable metadata identity. [id] remains the filename for compatibility.
  final String? stableId;
  final String name; // Реальное имя файла на диске
  final String path;
  final String type; // image, audio, script, font
  final String friendlyName;
  final String folder;
  final ScriptType scriptType;

  /// Размер файла в байтах (0 — неизвестно).
  final int sizeBytes;

  /// Дата последнего изменения файла (null — неизвестно).
  final DateTime? modifiedAt;

  /// Количество блоков скрипта (только для type == 'script', иначе 0).
  final int blockCount;

  const ResourceFile({
    required this.id,
    this.stableId,
    required this.name,
    required this.path,
    required this.type,
    required this.friendlyName,
    this.folder = '/',
    this.scriptType = ScriptType.generic,
    this.sizeBytes = 0,
    this.modifiedAt,
    this.blockCount = 0,
  });

  /// Пустышка для безопасного `firstWhere(orElse: ...)`.
  static const ResourceFile empty = ResourceFile(
    id: '',
    name: '',
    path: '',
    type: '',
    friendlyName: '',
  );

  bool get isEmpty => id.isEmpty;

  /// Расширение файла без точки в верхнем регистре (напр. "PNG", "TTF").
  String get extensionLabel {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toUpperCase();
  }

  /// Короткий токен ресурса для полей источника: `cat.png` для картинок,
  /// аудио, видео и шрифтов (резолвер сам подставит `res/<каталог>/`), путь
  /// целиком для скриптов — они по одному имени не ищутся.
  String get reference => resourceReference(fileName: name, path: path);
}
