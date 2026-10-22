import 'dart:convert';

import 'package:flutter/material.dart';

import 'theme_engine.dart';

/// Пресет темы — seed + вариант палитры + ручные цвета ролей.
///
/// Формат JSON версии 2:
/// ```json
/// {
///   "version": 2, "id": "grafit", "name": "Графит", "seed": "#101014",
///   "variant": "fidelity", "hct": {"tone": 40, "chroma": 30},
///   "deriveContainers": true,
///   "light": {"surface": "#FFFBF5", "primary": "#6A5B00"},
///   "dark":  {"primary": "#E7D06A"},
///   "bannerGradient": ["#3A3A44", "#101014"]
/// }
/// ```
/// `light`/`dark` — пины конкретных ролей: всё, что не перечислено, достраивает
/// M3. Версию 1 (только `seed`) парсим молча — сохранённые темы не ломаются.
@immutable
class ThemePreset {
  /// Уникальный id, например `beige`, `forest`, `user_custom_42`.
  final String id;

  /// Человекочитаемое имя, например «Бежевый», «Лесной».
  final String name;

  /// Опциональный автор (для пользовательских пресетов).
  final String? author;

  /// Главный «семя-цвет» для генерации M3 ColorScheme.
  final Color seed;

  /// Светлая / тёмная вариация. `null` означает «обе» —
  /// тогда мы строим обе из одного seed через `ColorScheme.fromSeed`.
  final Brightness? brightness;

  /// Цвета градиента для шапки профиля по умолчанию.
  /// Если `null` — берём `[primaryContainer, tertiaryContainer]` из темы.
  final List<Color>? bannerGradient;

  /// Это встроенный пресет? Встроенные нельзя удалять/редактировать.
  final bool isBuiltIn;

  /// Вариант палитры M3 — как из seed'а расходятся тона ролей.
  ///
  /// Дефолт — `vibrant`: из малонасыщенных seed (бежевый `#E2D9C9`)
  /// `tonalSpot` генерирует грязно-оливковые контейнеры. Кто хочет «мой цвет
  /// один в один», ставит `fidelity`, кто просит чёрный/серый — `monochrome`.
  final DynamicSchemeVariant variant;

  /// Ручки hue/chroma/tone поверх seed. Нужны, потому что у achromatic-цвета
  /// (чёрный, белый, серый) оттенка нет вовсе — и без этой правки тема из
  /// «чёрного» строится на hue по умолчанию.
  final SeedHct hct;

  /// true — контейнеры (`primaryContainer` и компания) пересчитываются от
  /// заколотого вручную базового цвета того же семейства.
  final bool deriveContainers;

  /// Пины ролей для светлой и тёмной схем.
  final RoleOverrides lightOverrides;
  final RoleOverrides darkOverrides;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.seed,
    this.author,
    this.brightness,
    this.bannerGradient,
    this.isBuiltIn = false,
    this.variant = DynamicSchemeVariant.vibrant,
    this.hct = SeedHct.none,
    this.deriveContainers = true,
    this.lightOverrides = const {},
    this.darkOverrides = const {},
  });

  /// Seed с учётом hue/chroma/tone-ручек — то, что реально уходит в M3.
  Color get effectiveSeed => hct.apply(seed);

  /// Полная палитра для конкретной яркости.
  ColorScheme schemeFor(Brightness b) {
    final base = ColorScheme.fromSeed(
      seedColor: effectiveSeed,
      brightness: b,
      dynamicSchemeVariant: variant,
    );
    return applyRoleOverrides(
      base,
      brightness: b,
      overrides: b == Brightness.dark ? darkOverrides : lightOverrides,
      deriveContainers: deriveContainers,
    ).scheme;
  }

  /// Пины этой яркости — для редактора ролей.
  RoleOverrides overridesFor(Brightness b) =>
      b == Brightness.dark ? darkOverrides : lightOverrides;

  /// Заменить пины одной яркости.
  ThemePreset withOverrides(Brightness b, RoleOverrides overrides) =>
      b == Brightness.dark
      ? copyWith(darkOverrides: overrides)
      : copyWith(lightOverrides: overrides);

  bool get isCustomized =>
      variant != DynamicSchemeVariant.vibrant ||
      !hct.isIdentity ||
      lightOverrides.isNotEmpty ||
      darkOverrides.isNotEmpty;

  // --- Сериализация ---

  Map<String, dynamic> toJson() => {
    'version': 2,
    'id': id,
    'name': name,
    if (author != null) 'author': author,
    'seed': _colorToHex(seed),
    if (brightness != null) 'brightness': brightness!.name,
    if (variant != DynamicSchemeVariant.vibrant) 'variant': variant.name,
    if (!hct.isIdentity) 'hct': hct.toJson(),
    if (!deriveContainers) 'deriveContainers': false,
    if (lightOverrides.isNotEmpty) 'light': _overridesToJson(lightOverrides),
    if (darkOverrides.isNotEmpty) 'dark': _overridesToJson(darkOverrides),
    if (bannerGradient != null)
      'bannerGradient': bannerGradient!.map(_colorToHex).toList(),
    'isBuiltIn': isBuiltIn,
  };

  String toJsonString() => jsonEncode(toJson());

  factory ThemePreset.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? 'Custom';
    final seedHex = json['seed'] as String? ?? '#FF6750A4';
    Brightness? brightness;
    final brightnessRaw = json['brightness'] as String?;
    if (brightnessRaw == 'light') brightness = Brightness.light;
    if (brightnessRaw == 'dark') brightness = Brightness.dark;
    final gradientRaw = json['bannerGradient'] as List?;
    List<Color>? gradient;
    if (gradientRaw != null) {
      gradient = gradientRaw
          .whereType<String>()
          .map(_hexToColor)
          .toList(growable: false);
    }
    return ThemePreset(
      id: id,
      name: name,
      author: json['author'] as String?,
      seed: _hexToColor(seedHex),
      brightness: brightness,
      bannerGradient: gradient,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      variant:
          variantFromKey(json['variant'] as String?) ??
          DynamicSchemeVariant.vibrant,
      hct: SeedHct.fromJson(json['hct'] as Map<String, dynamic>?),
      deriveContainers: json['deriveContainers'] as bool? ?? true,
      lightOverrides: _overridesFromJson(json['light']),
      darkOverrides: _overridesFromJson(json['dark']),
    );
  }

  factory ThemePreset.fromJsonString(String raw) =>
      ThemePreset.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  ThemePreset copyWith({
    String? id,
    String? name,
    String? author,
    Color? seed,
    Brightness? brightness,
    List<Color>? bannerGradient,
    bool? isBuiltIn,
    DynamicSchemeVariant? variant,
    SeedHct? hct,
    bool? deriveContainers,
    RoleOverrides? lightOverrides,
    RoleOverrides? darkOverrides,
  }) {
    return ThemePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      author: author ?? this.author,
      seed: seed ?? this.seed,
      brightness: brightness ?? this.brightness,
      bannerGradient: bannerGradient ?? this.bannerGradient,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      variant: variant ?? this.variant,
      hct: hct ?? this.hct,
      deriveContainers: deriveContainers ?? this.deriveContainers,
      lightOverrides: lightOverrides ?? this.lightOverrides,
      darkOverrides: darkOverrides ?? this.darkOverrides,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ThemePreset && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

Map<String, String> _overridesToJson(RoleOverrides overrides) => {
  for (final entry in overrides.entries) entry.key: _colorToHex(entry.value),
};

RoleOverrides _overridesFromJson(Object? raw) {
  if (raw is! Map) return const {};
  final result = <String, Color>{};
  raw.forEach((key, value) {
    if (key is! String) return;
    final color = parseHexColor(value as String?);
    if (color != null && themeRoleKeys.contains(key)) result[key] = color;
  });
  return result;
}

String _colorToHex(Color c) => hexOf(c);

Color _hexToColor(String input) =>
    parseHexColor(input) ?? const Color(0xFF6750A4);
