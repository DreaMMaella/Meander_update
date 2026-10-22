class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String sdkVersion;
  final String entry;
  final List<String> permissions;
  final String? description;
  final String? author;
  final String? icon;
  final String? homepage;
  final List<String> tags;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.sdkVersion,
    required this.entry,
    required this.permissions,
    this.description,
    this.author,
    this.icon,
    this.homepage,
    this.tags = const [],
  });

  PluginManifest copyWith({
    String? id,
    String? name,
    String? version,
    String? sdkVersion,
    String? entry,
    List<String>? permissions,
    String? description,
    String? author,
    String? icon,
    String? homepage,
    List<String>? tags,
  }) {
    return PluginManifest(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      sdkVersion: sdkVersion ?? this.sdkVersion,
      entry: entry ?? this.entry,
      permissions: permissions ?? this.permissions,
      description: description ?? this.description,
      author: author ?? this.author,
      icon: icon ?? this.icon,
      homepage: homepage ?? this.homepage,
      tags: tags ?? this.tags,
    );
  }

  static PluginManifest? parse(String text) {
    String? id;
    String? name;
    String? version;
    String? sdkVersion;
    String? entry;
    String? description;
    String? author;
    String? icon;
    String? homepage;
    final permissions = <String>[];
    final tags = <String>[];

    String? currentList;

    for (final rawLine in text.split('\n')) {
      if (rawLine.trim().isEmpty || rawLine.trimLeft().startsWith('#')) {
        continue;
      }

      final isIndented = rawLine.startsWith(' ') || rawLine.startsWith('\t');
      final trimmed = rawLine.trim();

      if (isIndented) {
        if (trimmed.startsWith('-')) {
          final value = trimmed.substring(1).trim();
          if (value.isNotEmpty) {
            final stripped = _stripQuotes(value);
            if (currentList == 'permissions') {
              permissions.add(stripped);
            } else if (currentList == 'tags') {
              tags.add(stripped);
            }
          }
        }
        continue;
      }

      currentList = null;

      final parts = trimmed.split(':');
      if (parts.length < 2) continue;

      final key = parts.first.trim();
      final value = _stripQuotes(trimmed.substring(key.length + 1).trim());

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
        case 'meander_sdk':
          sdkVersion = value;
          break;
        case 'entry':
          entry = value;
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
        case 'homepage':
          homepage = value.isEmpty ? null : value;
          break;
        case 'permissions':
          currentList = 'permissions';
          if (value.isNotEmpty) {
            permissions.add(value);
          }
          break;
        case 'tags':
          currentList = 'tags';
          if (value.isNotEmpty) {
            tags.add(value);
          }
          break;
      }
    }

    if (id == null || name == null || version == null || entry == null) {
      return null;
    }

    return PluginManifest(
      id: id,
      name: name,
      version: version,
      sdkVersion: sdkVersion ?? '0.0.0',
      entry: entry,
      permissions: permissions,
      description: description,
      author: author,
      icon: icon,
      homepage: homepage,
      tags: tags,
    );
  }

  static String _stripQuotes(String value) {
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') ||
          (first == '\'' && last == '\'')) {
        return value.substring(1, value.length - 1).trim();
      }
    }
    return value.trim();
  }
}
