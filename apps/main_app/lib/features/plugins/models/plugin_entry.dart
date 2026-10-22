import 'dart:convert';

class PluginEntry {
  final String id;
  final String name;
  final String version;
  final String localPath;
  final bool enabled;
  final DateTime installedAt;
  final String? description;
  final String? author;
  final String? icon;
  final List<String> tags;

  const PluginEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.localPath,
    required this.enabled,
    required this.installedAt,
    this.description,
    this.author,
    this.icon,
    this.tags = const [],
  });

  PluginEntry copyWith({
    String? id,
    String? name,
    String? version,
    String? localPath,
    bool? enabled,
    DateTime? installedAt,
    String? description,
    String? author,
    String? icon,
    List<String>? tags,
  }) {
    return PluginEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      localPath: localPath ?? this.localPath,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      description: description ?? this.description,
      author: author ?? this.author,
      icon: icon ?? this.icon,
      tags: tags ?? this.tags,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'localPath': localPath,
      'enabled': enabled,
      'installedAt': installedAt.toIso8601String(),
      'description': description,
      'author': author,
      'icon': icon,
      'tags': tags,
    };
  }

  static PluginEntry fromJson(Map<String, Object?> json) {
    return PluginEntry(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      version: (json['version'] ?? '0.0.0') as String,
      localPath: (json['localPath'] ?? '') as String,
      enabled: (json['enabled'] ?? true) as bool,
      installedAt: DateTime.tryParse(
            (json['installedAt'] ?? '').toString(),
          ) ??
          DateTime.now(),
      description: json['description'] as String?,
      author: json['author'] as String?,
      icon: json['icon'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  static String normalizeManifestValue(String value) {
    var cleaned = value.trim();
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    return cleaned.trim();
  }

  /// Манифест нового Rust-хоста (`plugin.json`). Здесь берутся только поля
  /// для списка установленных: сам манифест, права и Lua проверяет ядро при
  /// установке пакета в игровую сессию.
  static PluginEntry fromManifestJson({
    required String manifestJson,
    required String fallbackId,
    required String fallbackName,
    required String localPath,
  }) {
    final decoded = jsonDecode(manifestJson);
    final map = decoded is Map
        ? decoded.cast<String, Object?>()
        : const <String, Object?>{};
    String text(String key) => (map[key] as String?)?.trim() ?? '';
    String? optional(String key) {
      final value = text(key);
      return value.isEmpty ? null : value;
    }

    return PluginEntry(
      id: text('id').isEmpty ? fallbackId : text('id'),
      name: text('name').isEmpty ? fallbackName : text('name'),
      version: text('version').isEmpty ? '0.1.0' : text('version'),
      localPath: localPath,
      enabled: true,
      installedAt: DateTime.now(),
      description: optional('description'),
      author: optional('author'),
      icon: optional('icon'),
      tags: (map['tags'] as List?)?.map((tag) => '$tag').toList() ?? const [],
    );
  }

  static PluginEntry fromManifestText({
    required String manifestText,
    required String fallbackId,
    required String fallbackName,
    required String localPath,
  }) {
    final lines = const LineSplitter().convert(manifestText);
    String? id;
    String? name;
    String? version;
    String? description;
    String? author;
    String? icon;
    final tags = <String>[];

    String? currentList;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final isIndented = rawLine.startsWith(' ') || rawLine.startsWith('\t');
      if (isIndented && line.startsWith('-')) {
        final value = normalizeManifestValue(line.substring(1).trim());
        if (currentList == 'tags' && value.isNotEmpty) {
          tags.add(value);
        }
        continue;
      }

      currentList = null;

      final match = RegExp(r'^([A-Za-z0-9_\-]+)\s*:\s*(.+)$').firstMatch(line);
      if (match == null) {
        continue;
      }
      final key = match.group(1);
      final value = normalizeManifestValue(match.group(2) ?? '');

      switch (key) {
        case 'id':
          id = value;
          break;
        case 'name':
          name = value;
          break;
        case 'version':
          version = value;
          break;
        case 'description':
          description = value.isEmpty ? null : value;
          break;
        case 'author':
          author = value.isEmpty ? null : value;
          break;
        case 'icon':
          icon = value.isEmpty ? null : value;
          break;
        case 'tags':
          currentList = 'tags';
          if (value.isNotEmpty) {
            tags.add(value);
          }
          break;
      }
    }

    return PluginEntry(
      id: (id == null || id.isEmpty) ? fallbackId : id,
      name: (name == null || name.isEmpty) ? fallbackName : name,
      version: (version == null || version.isEmpty) ? '0.1.0' : version,
      localPath: localPath,
      enabled: true,
      installedAt: DateTime.now(),
      description: description,
      author: author,
      icon: icon,
      tags: tags,
    );
  }
}
