import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_engine.dart';
import 'theme_preset.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Реестр всех тем — встроенных и пользовательских.
class ThemeRegistry {
  ThemeRegistry._();

  static const String _customPresetsKey = 'theme_presets_custom_v1';
  static const String _selectedPresetIdKey = 'theme_preset_selected_v1';

  /// Встроенные пресеты тем (нельзя удалить).
  ///
  /// Геттер, а не `static final`: `name` витрины берётся под текущий язык,
  /// застывший список держал бы русские названия после смены языка. Ищут
  /// пресеты по `id`, так что пересоздание списка безвредно.
  static List<ThemePreset> get builtIn => [
    ThemePreset(
      id: 'beige',
      name: tr('Бежевый'),
      seed: Color(0xFFE2D9C9),
      bannerGradient: [Color(0xFFE2D9C9), Color(0xFFB8A88A)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'forest',
      name: tr('Лесной'),
      seed: Color(0xFF4CAF50),
      bannerGradient: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'royal_purple',
      name: tr('Королевский пурпур'),
      seed: Color(0xFF6750A4),
      bannerGradient: [Color(0xFF6750A4), Color(0xFF21005D)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'sunset',
      name: tr('Закат'),
      seed: Color(0xFFFF7043),
      bannerGradient: [Color(0xFFFF7043), Color(0xFFFFB300)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'ocean',
      name: tr('Океан'),
      seed: Color(0xFF0288D1),
      bannerGradient: [Color(0xFF0288D1), Color(0xFF00ACC1)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'rose',
      name: tr('Роза'),
      seed: Color(0xFFE91E63),
      bannerGradient: [Color(0xFFE91E63), Color(0xFFAD1457)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'cyber',
      name: tr('Кибер'),
      seed: Color(0xFF00E5FF),
      bannerGradient: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'mono',
      name: tr('Монохром'),
      seed: Color(0xFF607D8B),
      bannerGradient: [Color(0xFF455A64), Color(0xFF263238)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'aurora',
      name: tr('Аврора'),
      seed: Color(0xFF26A69A),
      bannerGradient: [Color(0xFF26A69A), Color(0xFF7E57C2)],
      isBuiltIn: true,
    ),

    // Ниже — образцы новых возможностей формата v2: вариант палитры,
    // HCT-правки seed'а и пины отдельных ролей.
    ThemePreset(
      id: 'grafit',
      name: tr('Графит'),
      seed: Color(0xFF101014),
      variant: DynamicSchemeVariant.monochrome,
      bannerGradient: [Color(0xFF3A3A44), Color(0xFF101014)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'noir',
      name: tr('Нуар'),
      // Чёрный сам по себе акцентом быть не может (тон 0, chroma 0) —
      // поэтому seed поднят ручками до тёплого графита тона 42.
      seed: Color(0xFF000000),
      variant: DynamicSchemeVariant.fidelity,
      hct: SeedHct(hue: 40, chroma: 8, tone: 42),
      bannerGradient: [Color(0xFF4A423A), Color(0xFF0A0A0A)],
      isBuiltIn: true,
    ),
    ThemePreset(
      id: 'precision_cyan',
      name: tr('Точный циан'),
      seed: Color(0xFF00B8D4),
      variant: DynamicSchemeVariant.fidelity,
      lightOverrides: {
        'surface': Color(0xFFFAFCFD),
        'primary': Color(0xFF006978),
      },
      darkOverrides: {
        'surface': Color(0xFF0A1214),
        'primary': Color(0xFF67E1FF),
      },
      bannerGradient: [Color(0xFF00B8D4), Color(0xFF004D5A)],
      isBuiltIn: true,
    ),
  ];

  /// Дефолтный пресет, если ничего не выбрано (первый запуск, удалённый
  /// пользовательский пресет, битая запись в prefs).
  ///
  /// Ищем по id, а не берём `builtIn.first`: порядок списка задаёт витрину
  /// настроек, и дефолт не должен меняться вместе с ним.
  static const String defaultPresetId = 'noir';

  static ThemePreset get defaultPreset =>
      byId(defaultPresetId) ?? builtIn.first;

  static ThemePreset? byId(String id, {List<ThemePreset>? extra}) {
    for (final p in builtIn) {
      if (p.id == id) return p;
    }
    if (extra != null) {
      for (final p in extra) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  // --- Пользовательские пресеты ---

  static Future<List<ThemePreset>> loadCustomPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_customPresetsKey) ?? const [];
    final list = <ThemePreset>[];
    for (final s in raw) {
      try {
        final preset = ThemePreset.fromJsonString(s);
        list.add(preset.copyWith(isBuiltIn: false));
      } catch (_) {
        // ignore malformed
      }
    }
    return list;
  }

  static Future<void> saveCustomPresets(List<ThemePreset> list) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = list
        .where((p) => !p.isBuiltIn)
        .map((p) => p.toJsonString())
        .toList();
    await prefs.setStringList(_customPresetsKey, encoded);
  }

  // --- Выбор активного пресета ---

  static Future<String?> loadSelectedPresetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedPresetIdKey);
  }

  static Future<void> saveSelectedPresetId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedPresetIdKey, id);
  }

  // --- Импорт / экспорт ---

  /// Импорт одной темы из JSON-строки. Возвращает добавленный пресет,
  /// либо бросает [FormatException] при ошибке.
  static ThemePreset importFromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return ThemePreset.fromJson(decoded).copyWith(isBuiltIn: false);
    }
    throw FormatException(tr('Ожидался JSON-объект пресета темы.'));
  }

  /// Импорт нескольких тем (массив JSON-объектов).
  static List<ThemePreset> importManyFromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((json) => ThemePreset.fromJson(json).copyWith(isBuiltIn: false))
          .toList();
    }
    if (decoded is Map<String, dynamic>) {
      return [ThemePreset.fromJson(decoded).copyWith(isBuiltIn: false)];
    }
    throw FormatException(tr('Ожидался JSON-объект или массив пресетов тем.'));
  }
}
