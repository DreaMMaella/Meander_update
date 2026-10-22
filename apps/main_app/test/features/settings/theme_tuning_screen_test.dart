// Экран ручной настройки темы: проверяем, что:UI-ручки превращаются ровно в те
// поля JSON v2, которые понимает движок, и что сохранение не затирает
// встроенный пресет (копия с тем же id не вступила бы в силу — ThemeRegistry
// ищет встроенные первым).
//
// GoogleFonts в тестах не гоняем в сеть, SharedPreferences — мокаем:
// addCustom пишет туда.

import 'package:canvas_app/core/theme/theme_engine.dart';
import 'package:canvas_app/core/theme/theme_preset.dart';
import 'package:canvas_app/core/theme/theme_preset_provider.dart';
import 'package:canvas_app/core/theme/theme_registry.dart';
import 'package:canvas_app/features/settings/screens/theme_tuning_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> open(
    WidgetTester tester,
    ThemePreset preset,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ThemeTuningScreen(preset: preset)),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  const custom = ThemePreset(id: 'mine', name: 'Моя', seed: Color(0xFF6750A4));

  testWidgets('экран собирается: вариант, seed, роли и живой предпросмотр', (
    tester,
  ) async {
    await open(tester, custom);
    expect(find.text('Вариант палитры'), findsOneWidget);
    expect(find.text('Опорный цвет'), findsOneWidget);
    expect(find.text('Цвета ролей'), findsOneWidget);
    // Предпросмотр строится реальной AppTheme — значит он должен показать
    // и текст, и карточки, и слои поверхности.
    expect(find.text('Мейандр'), findsOneWidget);
    expect(find.text('Карточка слоя'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
  });

  testWidgets('выбор варианта доезжает до сохранённой темы', (tester) async {
    final container = await open(tester, custom);

    await tester.tap(find.byKey(const Key('variant_fidelity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    final active = container.read(themePresetProvider).active;
    expect(active.variant, DynamicSchemeVariant.fidelity);
    expect(active.isCustomized, isTrue);
  });

  testWidgets('правка встроенной темы сохраняет копию, а не саму тему', (
    tester,
  ) async {
    final builtIn = ThemeRegistry.builtIn.first;
    final container = await open(tester, builtIn);

    await tester.tap(find.byKey(const Key('variant_monochrome')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить как свою'));
    await tester.pumpAndSettle();

    final state = container.read(themePresetProvider);
    expect(state.active.id, isNot(builtIn.id));
    expect(state.active.isBuiltIn, isFalse);
    expect(state.active.name, contains('(моя)'));
    // Оригинальная встроенная тема осталась нетронутой.
    expect(ThemeRegistry.byId(builtIn.id)!.variant, builtIn.variant);
  });

  testWidgets('пин роли: hex из диалога уходит в схему буквально', (
    tester,
  ) async {
    final container = await open(tester, custom);

    await tester.tap(find.byKey(const Key('role_primary')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), '#FF2E63');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ок'));
    await tester.pumpAndSettle();

    // Пин виден на плитке роли.
    expect(
      find.descendant(
        of: find.byKey(const Key('role_primary')),
        matching: find.byIcon(Icons.push_pin_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    final active = container.read(themePresetProvider).active;
    expect(active.lightOverrides['primary'], const Color(0xFFFF2E63));
    final scheme = active.schemeFor(Brightness.light);
    expect(scheme.primary, const Color(0xFFFF2E63));
    // Авто-подбранный текст читается — иначе «красиво» заканчивается здесь.
    expect(
      contrast(scheme.primary, scheme.onPrimary),
      greaterThanOrEqualTo(kMinContrast),
    );
    expect(scheme.onPrimaryContainer, isNotNull);
  });

  testWidgets('тёмная вкладка правит только тёмную схему', (tester) async {
    final container = await open(tester, custom);

    await tester.tap(
      find.widgetWithText(SegmentedButton<Brightness>, 'Тёмная'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role_surface')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), '#08080C');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ок'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    final active = container.read(themePresetProvider).active;
    expect(active.darkOverrides['surface'], const Color(0xFF08080C));
    expect(active.lightOverrides, isEmpty);
    expect(active.schemeFor(Brightness.dark).surface, const Color(0xFF08080C));
    expect(
      active.schemeFor(Brightness.light).surface,
      isNot(const Color(0xFF08080C)),
    );
  });

  testWidgets('«Авто» снимает пин, и роль снова считается из seed', (
    tester,
  ) async {
    final preset = custom.copyWith(
      lightOverrides: const {'primary': Color(0xFFFF2E63)},
    );
    final container = await open(tester, preset);
    expect(preset.schemeFor(Brightness.light).primary, const Color(0xFFFF2E63));

    await tester.tap(find.byKey(const Key('role_primary')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Авто'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    final active = container.read(themePresetProvider).active;
    expect(active.lightOverrides, isEmpty);
    expect(
      active.schemeFor(Brightness.light).primary,
      isNot(const Color(0xFFFF2E63)),
    );
  });
}
