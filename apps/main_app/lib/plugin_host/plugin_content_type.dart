class PluginContentField {
  final String name;
  final String type;
  final String label;

  const PluginContentField({
    required this.name,
    required this.type,
    required this.label,
  });
}

class PluginContentType {
  final String id;
  final String name;
  final String pluginId;
  final String? color;
  final List<PluginContentField> fields;
  final bool isCanvas;
  final Map<String, dynamic> canvasConfig;

  const PluginContentType({
    required this.id,
    required this.name,
    required this.pluginId,
    this.color,
    this.fields = const [],
    this.isCanvas = false,
    this.canvasConfig = const {},
  });

  PluginContentType copyWith({
    String? id,
    String? name,
    String? pluginId,
    String? color,
    List<PluginContentField>? fields,
    bool? isCanvas,
    Map<String, dynamic>? canvasConfig,
  }) {
    return PluginContentType(
      id: id ?? this.id,
      name: name ?? this.name,
      pluginId: pluginId ?? this.pluginId,
      color: color ?? this.color,
      fields: fields ?? this.fields,
      isCanvas: isCanvas ?? this.isCanvas,
      canvasConfig: canvasConfig ?? this.canvasConfig,
    );
  }
}
