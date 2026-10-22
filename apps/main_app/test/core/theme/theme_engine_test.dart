import 'dart:convert';

import 'package:canvas_app/core/theme/theme_engine.dart';
import 'package:canvas_app/core/theme/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Движок тем проверяется без приложения: на входе числа и hex, на выходе
/// `ColorScheme`. Всё остальное — виджеты.
void main() {
  ColorScheme schemeFor(
    Brightness b, {
    Color seed = const Color(0xFF6750A4),
    RoleOverrides overrides = const {},
    bool derive = true,
    DynamicSchemeVariant variant = DynamicSchemeVariant.vibrant,
  }) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: b,
      dynamicSchemeVariant: variant,
    );
    return applyRoleOverrides(
      base,
      brightness: b,
      overrides: overrides,
      deriveContainers: derive,
    ).scheme;
  }

  group('hex', () {
    test('принимает #RGB, #RRGGBB и #AARRGGBB', () {
      expect(parseHexColor('#0A0')?.toARGB32(), 0xFF00AA00);
      expect(parseHexColor('F472B6')?.toARGB32(), 0xFFF472B6);
      expect(parseHexColor('#80F472B6')?.toARGB32(), 0x80F472B6);
    });

    test('мусор — null, а не исключение', () {
      expect(parseHexColor(null), isNull);
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
      expect(parseHexColor('#12345'), isNull);
    });

    test('hexOf круговая, прозрачность сохраняется', () {
      expect(hexOf(const Color(0xFFF472B6)), '#F472B6');
      expect(hexOf(const Color(0x80F472B6)), '#80F472B6');
      expect(
        parseHexColor(hexOf(const Color(0xFF0A0A0A)))?.toARGB32(),
        0xFF0A0A0A,
      );
    });
  });

  group('HCT', () {
    test('тон читается и переставляется', () {
      // Хрома у идеального серого в HCT не ноль: белая точка sRGB даёт ~2–3.
      final black = hctOf(const Color(0xFF000000));
      expect(black.tone, closeTo(0, 0.6));
      expect(black.chroma, lessThan(4));
      expect(hctOf(const Color(0xFFFFFFFF)).tone, closeTo(100, 0.6));
      expect(hctOf(const Color(0xFFFFFFFF)).chroma, lessThan(4));
    });

    test('тон-ручка делает из чёрного видимый акцент', () {
      final made = hctColor(265, 30, 40);
      expect(hctOf(made).tone, closeTo(40, 1.5));
      expect(hctOf(made).chroma, greaterThan(20));
    });

    test('SeedHct.none не трогает цвет, частичная правка — только её', () {
      const purple = Color(0xFF6750A4);
      expect(SeedHct.none.apply(purple), purple);
      final lifted = const SeedHct(tone: 70).apply(purple);
      expect(hctOf(lifted).tone, closeTo(70, 1.5));
      expect(hctOf(lifted).hue, closeTo(hctOf(purple).hue, 1.5));
    });

    test('у achromatic-seed оттенка нет — хромой seed остаётся серым', () {
      final gray = hctOf(const Color(0xFF808080));
      expect(gray.chroma, lessThan(4));
      // Именно поэтому «чёрный seed → не чёрная тема»: нужен chroma/tone.
      final colored = const SeedHct(
        hue: 20,
        chroma: 40,
        tone: 40,
      ).apply(const Color(0xFF000000));
      expect(hctOf(colored).chroma, greaterThan(20));
    });
  });

  group('onFor', () {
    test('даёт AA-контраст и на тёмном, и на светлом фоне', () {
      for (final background in [
        const Color(0xFF101014),
        const Color(0xFFFFFFFF),
        const Color(0xFF6750A4),
        const Color(0xFFF472B6),
      ]) {
        final on = onFor(background);
        expect(
          contrast(background, on),
          greaterThanOrEqualTo(kMinContrast),
          reason: 'текст на ${hexOf(background)} нечитаем',
        );
      }
    });

    test('на среднем тоне берёт максимум, что есть', () {
      final mid = hctColor(265, 30, 50);
      final on = onFor(mid);
      expect(contrast(mid, on), greaterThanOrEqualTo(kMinContrast));
    });

    test('тон текста светлее фона, если фон тёмный', () {
      final on = onFor(const Color(0xFF101014));
      expect(hctOf(on).tone, greaterThan(80));
    });
  });

  group('оверрайды ролей', () {
    test('заколотый цвет уходит в схему буквально', () {
      const wanted = Color(0xFF0A0A0A);
      final scheme = schemeFor(
        Brightness.light,
        overrides: const {'primary': wanted},
      );
      expect(scheme.primary, wanted);
      // Дефолтный fromSeed так не умеет — это и есть ответ на «не мой цвет».
      final auto = ColorScheme.fromSeed(
        seedColor: wanted,
        brightness: Brightness.light,
      );
      expect(auto.primary, isNot(wanted));
    });

    test('onPrimary подбирается автоматически и читается', () {
      final scheme = schemeFor(
        Brightness.light,
        overrides: const {'primary': Color(0xFF0A0A0A)},
      );
      expect(contrast(scheme.primary, scheme.onPrimary), greaterThan(10));
    });

    test('вручную заколотый on* не переезжается', () {
      final scheme = schemeFor(
        Brightness.dark,
        overrides: const {
          'primary': Color(0xFFE8C86A),
          'onPrimary': Color(0xFF000000),
        },
      );
      expect(scheme.onPrimary, const Color(0xFF000000));
    });

    test('контейнер пересчитывается из моего primary, пока включён derive', () {
      const pinned = Color(0xFFE8590C);
      final derived = schemeFor(
        Brightness.light,
        overrides: const {'primary': pinned},
      );
      expect(hctOf(derived.primaryContainer).tone, closeTo(80, 2));
      expect(
        hctOf(derived.primaryContainer).hue,
        closeTo(hctOf(pinned).hue, 2),
      );

      final kept = schemeFor(
        Brightness.light,
        overrides: const {'primary': pinned},
        derive: false,
      );
      expect(kept.primaryContainer, isNot(derived.primaryContainer));
    });

    test('тёмная тема берёт тон контейнера 30', () {
      final scheme = schemeFor(
        Brightness.dark,
        overrides: const {'primary': Color(0xFFE8590C)},
      );
      expect(hctOf(scheme.primaryContainer).tone, closeTo(30, 2));
    });

    test('ни одной пары не осталось нечитаемой после авто-подбора', () {
      final build = applyRoleOverrides(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A86FF),
          brightness: Brightness.light,
        ),
        brightness: Brightness.light,
        overrides: const {
          'primary': Color(0xFFFFD60A),
          'surface': Color(0xFFFFF8E7),
          'tertiary': Color(0xFF065A63),
        },
      );
      expect(build.weakContrast, isEmpty);
    });

    test('contrastIssues ругается, когда текст заколот руками плохо', () {
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4))
          .copyWith(
            primary: const Color(0xFFFFFFFF),
            onPrimary: const Color(0xFFEFEFEF),
          );
      final issues = contrastIssues(scheme);
      expect(
        issues,
        contains('onPrimary → primary: ${issues.first.split(': ').last}'),
      );
      expect(issues.any((e) => e.startsWith('onPrimary → primary')), isTrue);
    });

    test('каждая роль из списка действительно применима', () {
      // Ловит опечатку в имени роли: сверяем запись с чтением.
      for (final key in themeRoleKeys) {
        final pinned = Color(0xFF123456);
        final scheme = schemeFor(Brightness.light, overrides: {key: pinned});
        expect(
          readRole(scheme, key),
          pinned,
          reason: 'роль $key записывается, но не читается (розыск имён)',
        );
      }
    });

    test('неизвестная роль игнорируется, а не роняет тему', () {
      expect(
        schemeFor(
          Brightness.light,
          overrides: const {'unicorn': Color(0xFF000000)},
        ),
        isA<ColorScheme>(),
      );
    });
  });

  group('варианты палитры', () {
    test('fidelity сохраняет насыщенность seed, vibrant — усиливает', () {
      const seed = Color(0xFFB36AE0);
      ColorScheme build(DynamicSchemeVariant v) => ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        dynamicSchemeVariant: v,
      );
      final faithful = hctOf(build(DynamicSchemeVariant.fidelity).primary);
      final loud = hctOf(build(DynamicSchemeVariant.vibrant).primary);
      expect(
        faithful.chroma,
        lessThan(loud.chroma),
        reason: 'fidelity должен быть ближе к seed, чем vibrant',
      );
      expect(
        faithful.hue,
        closeTo(hctOf(seed).hue, 3),
        reason: 'fidelity не уводит оттенок',
      );
    });

    test('monochrome игнорирует оттенок seed', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFFE91E63),
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      );
      expect(hctOf(scheme.primary).chroma, lessThan(12));
    });

    test('ключ варианта круговой, неизвестный — null', () {
      expect(variantFromKey('fidelity'), DynamicSchemeVariant.fidelity);
      expect(variantKey(DynamicSchemeVariant.neutral), 'neutral');
      expect(variantFromKey('unicorn'), isNull);
      expect(variantFromKey(null), isNull);
    });
  });

  group('JSON-совместимость', () {
    test('версия 1 (только seed) даёт ровно то, что давала', () {
      final v1 = ThemePreset.fromJsonString(
        '{"version":1,"id":"x","name":"X","seed":"#6750A4"}',
      );
      final expected = ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: Brightness.light,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      );
      final actual = v1.schemeFor(Brightness.light);
      expect(actual.primary, expected.primary);
      expect(actual.surfaceContainerHigh, expected.surfaceContainerHigh);
      expect(v1.variant, DynamicSchemeVariant.vibrant);
      expect(v1.hct, SeedHct.none);
      expect(v1.lightOverrides, isEmpty);
    });

    test('версия 2 переживает round-trip целиком', () {
      final preset = ThemePreset(
        id: 'grafit',
        name: 'Графит',
        seed: const Color(0xFF101014),
        variant: DynamicSchemeVariant.fidelity,
        hct: const SeedHct(tone: 42, chroma: 18),
        deriveContainers: false,
        lightOverrides: const {'surface': Color(0xFFFFFBF5)},
        darkOverrides: const {'primary': Color(0xFFE7D06A)},
        bannerGradient: const [Color(0xFF3A3A44), Color(0xFF101014)],
      );
      final restored = ThemePreset.fromJsonString(preset.toJsonString());
      expect(restored.variant, DynamicSchemeVariant.fidelity);
      expect(restored.hct, const SeedHct(tone: 42, chroma: 18));
      expect(restored.deriveContainers, isFalse);
      expect(restored.lightOverrides['surface'], const Color(0xFFFFFBF5));
      expect(restored.darkOverrides['primary'], const Color(0xFFE7D06A));
      expect(
        restored.schemeFor(Brightness.dark).primary,
        const Color(0xFFE7D06A),
      );
      expect(restored.isCustomized, isTrue);
    });

    test('неизвестные роли и битые hex в overrides отбрасываются', () {
      final preset = ThemePreset.fromJson({
        'id': 'x',
        'name': 'X',
        'seed': '#6750A4',
        'light': {
          'unicorn': '#000000',
          'surface': 'не цвет',
          'outline': '#101014',
        },
      });
      expect(preset.lightOverrides.keys, ['outline']);
    });

    test('экспорт встраивает только отклонения от дефолта', () {
      final json =
          jsonDecode(
                const ThemePreset(
                  id: 'plain',
                  name: 'Plain',
                  seed: Color(0xFF6750A4),
                ).toJsonString(),
              )
              as Map<String, dynamic>;
      expect(json['version'], 2);
      expect(json.containsKey('variant'), isFalse);
      expect(json.containsKey('hct'), isFalse);
      expect(json.containsKey('light'), isFalse);
    });
  });
}
