// Дефолтная тема — «Нуар», и дефолт не должен зависеть от порядка витрины.
//
// `ThemeRegistry.defaultPreset` был `builtIn.first`, то есть бежевым. Первый
// запуск (и сброс после удаления своего пресета) выдавал светлую бежевую
// палитру, хотя режим по умолчанию — тёмный: получалась тема, которую никто
// не выбирал. Поэтому дефолт ищется по id, а список остаётся только порядком
// отображения в настройках.

import 'dart:io';

import 'package:canvas_app/core/theme/theme_preset_provider.dart';
import 'package:canvas_app/core/theme/theme_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('дефолтный пресет — нуар', () {
    expect(ThemeRegistry.defaultPresetId, 'noir');
    expect(ThemeRegistry.defaultPreset.name, 'Нуар');
    // Порядок витрины нарочно другой: если дефолт снова заберёт `first`,
    // тест упадёт именно на этом равенстве.
    expect(ThemeRegistry.builtIn.first.id, 'beige');
    expect(
      ThemeRegistry.defaultPreset.id,
      isNot(ThemeRegistry.builtIn.first.id),
    );
  });

  test('приложение стартует с нуаром, пока ничего не выбрано', () {
    // `load()` здесь не вызывался — это и есть состояние до prefs.
    expect(ThemePresetNotifier().state.active.id, 'noir');
  });

  test('нуар встроенный и его нельзя потерять из-за переименования id', () {
    final noir = ThemeRegistry.byId(ThemeRegistry.defaultPresetId);
    expect(noir, isNotNull);
    expect(noir!.isBuiltIn, isTrue);
    // Идентичен дефолту: провайдер ищет по строке, а не держит копию.
    expect(noir.id, ThemeRegistry.defaultPreset.id);
  });

  test('дефолт нигде не берётся первым элементом списка', () {
    for (final path in const [
      'lib/core/theme/theme_registry.dart',
      'lib/core/theme/theme_preset_provider.dart',
      'lib/core/theme/app_theme.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('defaultPreset => builtIn.first')),
        reason: '$path снова привязал дефолт к порядку витрины',
      );
    }
  });
}
