/// Тип контента, который плагин добавляет в редактор: описание формы, а не код.
///
/// Источник — Rust-хост (`MeanderPluginHost.contentTypes()`), то есть поля
/// берутся из `plugin.json` и уже проверены ядром. [id] — полное имя
/// `<pluginId>:<тип>`: именно оно попадает в `ContentItem.pluginTypeId` и по
/// нему плагин узнаёт свои айтемы.
library;

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart' show Color, Colors, IconData;
import 'package:mnd_player/widgets/plugin_spec_view.dart' show kPluginIcons;

/// Тип поля: те же шесть значений, что валидирует манифест.
enum PluginFieldKind {
  text,
  number,
  bool,
  select,
  color,
  asset;

  static PluginFieldKind fromName(String? raw) => values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => PluginFieldKind.text,
  );
}

class PluginContentField {
  /// Ключ в `pluginData`.
  final String name;
  final String label;
  final PluginFieldKind kind;
  final Object? defaultValue;
  final List<String> options;
  final double? min;
  final double? max;
  final String? hint;

  const PluginContentField({
    required this.name,
    required this.label,
    required this.kind,
    this.defaultValue,
    this.options = const [],
    this.min,
    this.max,
    this.hint,
  });

  factory PluginContentField.fromHostJson(Map<String, dynamic> json) {
    final options = (json['options'] as List?) ?? const [];
    return PluginContentField(
      name: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      kind: PluginFieldKind.fromName(json['type'] as String?),
      defaultValue: json['default'],
      options: [for (final option in options) '$option'],
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      hint: json['hint'] as String?,
    );
  }

  /// Выпадающий список имеет смысл только с опциями; пустой `select`
  /// редактор показывает как обычное текстовое поле.
  bool get isChoice => kind == PluginFieldKind.select && options.isNotEmpty;

  /// Границы числа для подсказки под полем; null — ограничений нет.
  String? get rangeHint {
    if (min == null && max == null) return null;
    if (min != null && max != null) return trf('от {p0} до {p1}', {'p0': _trim(min!), 'p1': _trim(max!)});
    if (min != null) return trf('не меньше {p0}', {'p0': _trim(min!)});
    return trf('не больше {p0}', {'p0': _trim(max!)});
  }
}

/// `12.0` → `12`, `12.5` → `12.5` — подсказка не должна пугать нулями.
String _trim(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

/// Цвет из поля формы: `#RGB`, `#RRGGBB` или `#AARRGGBB`; null — не цвет.
Color? tryParsePluginColor(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  var hex = value.replaceFirst('#', '');
  if (hex.length == 3) {
    hex = hex.split('').map((digit) => '$digit$digit').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

class PluginContentType {
  /// Полное имя типа: `<pluginId>:<id>` из манифеста.
  final String id;
  final String name;
  final String pluginId;
  final String? description;
  final String? icon;
  final List<PluginContentField> fields;

  const PluginContentType({
    required this.id,
    required this.name,
    required this.pluginId,
    this.description,
    this.icon,
    this.fields = const [],
  });

  factory PluginContentType.fromHostJson(Map<String, dynamic> json) {
    final rawFields = (json['fields'] as List?) ?? const [];
    return PluginContentType(
      id: json['type'] as String? ?? '',
      name: json['name'] as String? ?? '',
      pluginId: json['pluginId'] as String? ?? '',
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      fields: [
        for (final field in rawFields)
          if (field is Map)
            PluginContentField.fromHostJson(field.cast<String, dynamic>()),
      ],
    );
  }

  /// Значения по умолчанию — старточка формы при добавлении айтема.
  Map<String, dynamic> get defaults => {
    for (final field in fields)
      if (field.defaultValue != null) field.name: field.defaultValue,
  };

  /// Иконка из манифеста — те же имена, что понимает рендерер UI-спеков.
  /// Неизвестного имени нет — пункт меню рисуется иконкой по умолчанию.
  IconData? get iconData => icon == null ? null : kPluginIcons[icon];

  /// Акцент для карточки айтема и пункта меню. Манифест цвета не объявляет,
  /// поэтому оттенок берётся из стабильного хэша id плагина: один плагин —
  /// один цвет, и он не меняется между перезапусками.
  Color get accentColor =>
      _accents[_stableHash(pluginId) % _accents.length];
}

const List<Color> _accents = [
  Colors.deepPurpleAccent,
  Colors.tealAccent,
  Colors.orangeAccent,
  Colors.lightGreenAccent,
  Colors.blueAccent,
  Colors.amberAccent,
  Colors.redAccent,
  Colors.cyanAccent,
];

/// FNV-1a: [String.hashCode] не гарантированно стабилен между запусками,
/// а цвет подписи плагина должен быть одним и тем же всегда.
int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
