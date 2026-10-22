import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_preset.dart';
import 'theme_registry.dart';

class ThemePresetState {
  final ThemePreset active;
  final List<ThemePreset> custom;
  final bool isLoaded;

  const ThemePresetState({
    required this.active,
    required this.custom,
    this.isLoaded = false,
  });

  /// Все доступные пресеты (built-in + custom).
  List<ThemePreset> get all => [...ThemeRegistry.builtIn, ...custom];

  ThemePresetState copyWith({
    ThemePreset? active,
    List<ThemePreset>? custom,
    bool? isLoaded,
  }) {
    return ThemePresetState(
      active: active ?? this.active,
      custom: custom ?? this.custom,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class ThemePresetNotifier extends StateNotifier<ThemePresetState> {
  ThemePresetNotifier()
    : super(
        ThemePresetState(active: ThemeRegistry.defaultPreset, custom: const []),
      );

  /// Загрузка из SharedPreferences (вызывается на старте, из initThemeProvider).
  Future<void> load() async {
    final custom = await ThemeRegistry.loadCustomPresets();
    final selectedId = await ThemeRegistry.loadSelectedPresetId();
    final active =
        ThemeRegistry.byId(selectedId ?? '', extra: custom) ??
        ThemeRegistry.defaultPreset;
    state = ThemePresetState(active: active, custom: custom, isLoaded: true);
  }

  /// Выбрать активный пресет.
  Future<void> setActive(String id) async {
    final found = ThemeRegistry.byId(id, extra: state.custom);
    if (found == null) return;
    state = state.copyWith(active: found);
    await ThemeRegistry.saveSelectedPresetId(id);
  }

  /// Добавить пользовательский пресет (или обновить существующий с тем же id).
  Future<void> addCustom(ThemePreset preset) async {
    final p = preset.copyWith(isBuiltIn: false);
    final existing = List<ThemePreset>.from(state.custom)
      ..removeWhere((e) => e.id == p.id);
    existing.add(p);
    state = state.copyWith(custom: existing);
    await ThemeRegistry.saveCustomPresets(existing);
  }

  Future<void> removeCustom(String id) async {
    final next = state.custom.where((p) => p.id != id).toList();
    state = state.copyWith(custom: next);
    await ThemeRegistry.saveCustomPresets(next);
    // Если удалили активный — переключаемся на дефолт.
    if (state.active.id == id) {
      await setActive(ThemeRegistry.defaultPreset.id);
    }
  }

  /// Импорт пресета (или нескольких) из JSON-строки.
  /// Активирует первый импортированный пресет.
  Future<List<ThemePreset>> importFromJson(String raw) async {
    final imported = ThemeRegistry.importManyFromJson(raw);
    for (final p in imported) {
      await addCustom(p);
    }
    if (imported.isNotEmpty) {
      await setActive(imported.first.id);
    }
    return imported;
  }

  /// Экспорт активного пресета.
  String exportActive() => state.active.toJsonString();
}

final themePresetProvider =
    StateNotifierProvider<ThemePresetNotifier, ThemePresetState>(
      (ref) => ThemePresetNotifier(),
    );
