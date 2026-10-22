/// Расчёт темы: seed → палитра M3 → ручные цвета ролей.
///
/// Здесь нет виджетов: только чистые функции, которые превращают набор чисел
/// (hue/chroma/tone, вариант палитры, pin'ы ролей) в `ColorScheme`. Экран
/// настройки тем рисует этим же, поэтому предпросмотр и реальная тема
/// приложения совпадают до пикселя.
///
/// Зачем это нужно: `ColorScheme.fromSeed` берёт из seed-цвета только
/// [hue + chroma], а тон каждой роли назначает сам. Поэтому «чёрный» seed
/// физически не может дать чёрный `primary` — у него нет ни тона для роли 40,
/// ни оттенка. Здесь это честно вытаскивается наружу: [SeedHct] показывает
/// hue/chroma/tone как три отдельных ручки, а оверрайды ролей позволяют
/// сказать «вот этот цвет — точный, не трогай».
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/material.dart'
    show Brightness, ColorScheme, DynamicSchemeVariant;
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Минимальный контраст текста к фону — WCAG AA для обычного кегля.
const double kMinContrast = 4.5;

/// Seed-цвет в HCT: оттенок, насыщенность, светлота.
///
/// `null`-поле означает «взять из самого цвета». Так один и тот же hex даёт
/// и «ничего не менять», и «сделай из этого серого акцент»: чёрный — это
/// T0 C0, и чтобы он стал видимым акцентом, игроку нужно поднять тон.
class SeedHct {
  final double? hue;
  final double? chroma;
  final double? tone;

  const SeedHct({this.hue, this.chroma, this.tone});

  static const SeedHct none = SeedHct();

  bool get isIdentity => hue == null && chroma == null && tone == null;

  /// Применить ручки к [base]: пропущенные значения берутся из него.
  Color apply(Color base) {
    if (isIdentity) return base;
    final src = Hct.fromInt(base.toARGB32());
    return hctColor(
      hue ?? src.hue,
      chroma ?? src.chroma,
      tone ?? src.tone,
      alpha: aOf(base),
    );
  }

  SeedHct copyWith({double? hue, double? chroma, double? tone}) => SeedHct(
    hue: hue ?? this.hue,
    chroma: chroma ?? this.chroma,
    tone: tone ?? this.tone,
  );

  Map<String, dynamic> toJson() => {
    if (hue != null) 'hue': _round(hue!),
    if (chroma != null) 'chroma': _round(chroma!),
    if (tone != null) 'tone': _round(tone!),
  };

  static SeedHct fromJson(Map<String, dynamic>? json) {
    if (json == null) return none;
    return SeedHct(
      hue: (json['hue'] as num?)?.toDouble(),
      chroma: (json['chroma'] as num?)?.toDouble(),
      tone: (json['tone'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeedHct &&
      other.hue == hue &&
      other.chroma == chroma &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(hue, chroma, tone);
}

double _round(double v) => (v * 10).roundToDouble() / 10;

/// Цвет из HCT-трёх. Тон и хрома clamp'ятся самой моделью — гамиут срезается
/// честно, без «грязи», которую даёт наивная подмена lightness в HSL.
Color hctColor(double hue, double chroma, double tone, {int alpha = 255}) {
  final argb = Hct.from(
    hue,
    chroma.clamp(0.0, 150.0),
    tone.clamp(0.0, 100.0),
  ).toInt();
  return Color((alpha << 24) | (argb & 0x00FFFFFF));
}

({double hue, double chroma, double tone}) hctOf(Color color) {
  final hct = Hct.fromInt(color.toARGB32());
  return (hue: hct.hue, chroma: hct.chroma, tone: hct.tone);
}

/// Новый цвет с тем же оттенком и насыщенностью, но другим тоном.
Color toneOf(Color color, double tone) {
  final src = Hct.fromInt(color.toARGB32());
  return hctColor(src.hue, src.chroma, tone, alpha: aOf(color));
}

/// WCAG-контраст двух цветов (1..21).
double contrast(Color a, Color b) => Contrast.ratioOfTones(
  Hct.fromInt(a.toARGB32()).tone,
  Hct.fromInt(b.toARGB32()).tone,
);

/// Текст поверх [background]: тот же оттенок, почти нейтральной насыщенности.
///
/// Тон берётся не «минимально допустимый», а из стандартной лестницы M3
/// (90/95/100 по тёмному, 10/6/0 по светлому) — иначе AA-минимум дал бы серую
/// кашу вместо белого по чёрному. Если на предпочтительной стороне контраста
/// не хватает, уходит на тёмную/светлую, а при недостижимом требовании —
/// на крайность с максимальным контрастом.
Color onFor(Color background, {double ratio = kMinContrast}) {
  final src = Hct.fromInt(background.toARGB32());
  const lightLadder = [90.0, 95.0, 100.0];
  const darkLadder = [10.0, 6.0, 0.0];
  final prefer = src.tone < 50 ? lightLadder : darkLadder;
  final fallback = src.tone < 50 ? darkLadder : lightLadder;
  for (final ladder in [prefer, fallback]) {
    for (final tone in ladder) {
      if (contrastWithTone(src.tone, tone) >= ratio) {
        return hctColor(src.hue, math.min(src.chroma, 12.0), tone);
      }
    }
  }
  final light = contrastWithTone(src.tone, 100) >= contrastWithTone(src.tone, 0)
      ? 100.0
      : 0.0;
  return hctColor(src.hue, math.min(src.chroma, 12.0), light);
}

double contrastWithTone(double toneA, double toneB) =>
    Contrast.ratioOfTones(toneA, toneB);

/// Тон контейнера из базового цвета: светлая тема — пастель, тёмная — глухо.
/// M3-константы: 80/30 для `*Container`, и текст по ним — 10/90.
double containerTone(Brightness brightness) =>
    brightness == Brightness.light ? 80 : 30;

Color containerFor(Color base, Brightness brightness) =>
    toneOf(base, containerTone(brightness));

int aOf(Color color) => (color.a * 255).round();

// ---------------------------------------------------------------------------
//  Роли схемы
// ---------------------------------------------------------------------------

/// Одна строка редактора ролей: базовый цвет и его текст, плюс контейнер.
///
/// Данные живут здесь, а не в виджетах, потому что движку нужен обход
/// «какой `on*` за кем закреплён» — и он же показывает это в UI.
class ThemeRoleRow {
  final String label;

  /// Роли-цвета этой строки в порядке «задаём → авто-пары».
  final List<String> slots;
  final String hint;

  const ThemeRoleRow({
    required this.label,
    required this.slots,
    this.hint = '',
  });
}

/// Строки ролей, которые видит человек. `on*` показаны, но по умолчанию
/// заполняются сами — см. [kOnPartnerOf].
// Геттер, а не final-таблица: список строится под текущий язык, иначе
// переключение языка не перекрасило бы эти подписи.
List<ThemeRoleRow> get themeRoleRows => [
  ThemeRoleRow(
    label: tr('Основной'),
    slots: ['primary', 'onPrimary', 'primaryContainer', 'onPrimaryContainer'],
    hint: tr('Кнопки, активные иконки, ссылки'),
  ),
  ThemeRoleRow(
    label: tr('Вторичный'),
    slots: [
      'secondary',
      'onSecondary',
      'secondaryContainer',
      'onSecondaryContainer',
    ],
    hint: tr('Чипы, индикатор выбора'),
  ),
  ThemeRoleRow(
    label: tr('Третичный'),
    slots: [
      'tertiary',
      'onTertiary',
      'tertiaryContainer',
      'onTertiaryContainer',
    ],
    hint: tr('Акценты второго плана, баннеры'),
  ),
  ThemeRoleRow(
    label: tr('Ошибка'),
    slots: ['error', 'onError', 'errorContainer', 'onErrorContainer'],
  ),
  ThemeRoleRow(
    label: tr('Фон и текст'),
    slots: ['background', 'onBackground', 'surface', 'onSurface'],
    hint: tr('Экран и обычный текст'),
  ),
  ThemeRoleRow(
    label: tr('Поверхности'),
    slots: [
      'surfaceVariant',
      'onSurfaceVariant',
      'surfaceDim',
      'surfaceBright',
    ],
  ),
  ThemeRoleRow(
    label: tr('Слои'),
    slots: [
      'surfaceContainerLowest',
      'surfaceContainerLow',
      'surfaceContainer',
      'surfaceContainerHigh',
      'surfaceContainerHighest',
    ],
    hint: tr('Карточки, панели, всплывашки'),
  ),
  ThemeRoleRow(
    label: tr('Границы и служебные'),
    slots: [
      'outline',
      'outlineVariant',
      'inverseSurface',
      'onInverseSurface',
      'inversePrimary',
      'surfaceTint',
      'scrim',
      'shadow',
    ],
  ),
];

/// Все роли в порядке объявления.
final List<String> themeRoleKeys = List.unmodifiable(
  themeRoleRows.expand((row) => row.slots),
);

/// «Кто читает поверх кого»: при ручном цвете базовой роли партнёр
/// пересчитывается сам, если его не закололи отдельно.
const Map<String, String> kOnPartnerOf = {
  'primary': 'onPrimary',
  'primaryContainer': 'onPrimaryContainer',
  'secondary': 'onSecondary',
  'secondaryContainer': 'onSecondaryContainer',
  'tertiary': 'onTertiary',
  'tertiaryContainer': 'onTertiaryContainer',
  'error': 'onError',
  'errorContainer': 'onErrorContainer',
  'background': 'onBackground',
  'surface': 'onSurface',
  'surfaceVariant': 'onSurfaceVariant',
  'inverseSurface': 'onInverseSurface',
};

/// Ручные правки: роль → цвет. Пустой map — «всё из seed-палитры».
typedef RoleOverrides = Map<String, Color>;

/// «На каком фоне читается этот on-роль» — реверс [kOnPartnerOf].
final Map<String, String> themeOnBackground = {
  for (final entry in kOnPartnerOf.entries) entry.value: entry.key,
};

/// Человеческие имена ролей для редактора.
Map<String, String> get themeRoleLabels => {
  'primary': tr('Основной'),
  'onPrimary': tr('Текст на основном'),
  'primaryContainer': tr('Основной контейнер'),
  'onPrimaryContainer': tr('Текст в основном контейнере'),
  'secondary': tr('Вторичный'),
  'onSecondary': tr('Текст на вторичном'),
  'secondaryContainer': tr('Вторичный контейнер'),
  'onSecondaryContainer': tr('Текст во вторичном контейнере'),
  'tertiary': tr('Третичный'),
  'onTertiary': tr('Текст на третичном'),
  'tertiaryContainer': tr('Третичный контейнер'),
  'onTertiaryContainer': tr('Текст в третичном контейнере'),
  'error': tr('Ошибка'),
  'onError': tr('Текст на ошибке'),
  'errorContainer': tr('Контейнер ошибки'),
  'onErrorContainer': tr('Текст в контейнере ошибки'),
  'background': tr('Фон'),
  'onBackground': tr('Текст на фоне'),
  'surface': tr('Поверхность'),
  'onSurface': tr('Текст'),
  'surfaceVariant': tr('Вариант поверхности'),
  'onSurfaceVariant': tr('Вторичный текст'),
  'surfaceDim': tr('Поверхность приглушённая'),
  'surfaceBright': tr('Поверхность светлая'),
  'surfaceContainerLowest': tr('Слой 0 (самый низкий)'),
  'surfaceContainerLow': tr('Слой 1'),
  'surfaceContainer': tr('Слой 2'),
  'surfaceContainerHigh': tr('Слой 3'),
  'surfaceContainerHighest': tr('Слой 4 (самый верхний)'),
  'inverseSurface': tr('Инверсная поверхность'),
  'onInverseSurface': tr('Текст в инверсной'),
  'inversePrimary': tr('Инверсный основной'),
  'surfaceTint': tr('Тонирование'),
  'scrim': tr('Затемнение'),
  'shadow': tr('Тень'),
  'outline': tr('Контур'),
  'outlineVariant': tr('Контур светлый'),

};

/// Итог применения оверрайдов — нужен для предпросмотра и диагностики.
class ThemeBuild {
  final ColorScheme scheme;

  /// Пары «цвет — текст», где контраст ниже [kMinContrast].
  final List<String> weakContrast;

  const ThemeBuild(this.scheme, this.weakContrast);
}

/// Собрать схему: [base] из seed, поверх — ручные [overrides].
///
/// [deriveContainers] — «семейство считать от моего primary»: если заколот
/// `primary`, то `primaryContainer` перекрашивается в его же оттенок (тон 80/30),
/// иначе тема распадается на «красная кнопка в зелёном контейнере».
ThemeBuild applyRoleOverrides(
  ColorScheme base, {
  required Brightness brightness,
  RoleOverrides overrides = const {},
  bool deriveContainers = true,
}) {
  if (overrides.isEmpty && !deriveContainers) {
    return ThemeBuild(base, contrastIssues(base));
  }
  final roles = <String, Color>{
    for (final key in themeRoleKeys) key: readRole(base, key),
  };
  overrides.forEach((key, value) {
    if (roles.containsKey(key)) roles[key] = value;
  });

  if (deriveContainers) {
    for (final entry in kFamilyContainers.entries) {
      final pinned = overrides[entry.value.$1];
      if (pinned == null) continue;
      if (!overrides.containsKey(entry.value.$2)) {
        roles[entry.value.$2] = containerFor(pinned, brightness);
      }
    }
  }

  // Авто-«on» для заколотых цветов, если партнёр не задан вручную.
  for (final entry in kOnPartnerOf.entries) {
    final background = entry.key;
    final on = entry.value;
    final wasPinned = overrides.containsKey(background);
    if (!wasPinned || overrides.containsKey(on)) continue;
    roles[on] = onFor(roles[background]!);
  }

  final scheme = _writeRoles(base, roles);
  return ThemeBuild(scheme, contrastIssues(scheme));
}

/// Семейства, чей контейнер пересчитывается от заколотой базы:
/// база → (база, контейнер).
const Map<String, (String, String)> kFamilyContainers = {
  'primary': ('primary', 'primaryContainer'),
  'secondary': ('secondary', 'secondaryContainer'),
  'tertiary': ('tertiary', 'tertiaryContainer'),
  'error': ('error', 'errorContainer'),
};

/// Проверка читаемости: возвращает описания пар вроде
/// `«onPrimary → primary: 2.9:1»`.
List<String> contrastIssues(ColorScheme scheme) {
  final issues = <String>[];
  for (final entry in kOnPartnerOf.entries) {
    final bg = readRole(scheme, entry.key);
    final fg = readRole(scheme, entry.value);
    final ratio = contrast(bg, fg);
    if (ratio < kMinContrast) {
      issues.add(
        '${entry.value} → ${entry.key}: ${ratio.toStringAsFixed(1)}:1',
      );
    }
  }
  return issues;
}

/// Текущее значение роли в схеме — нужно редактору ролей, чтобы показать
/// «что даст авто», и тестам, чтобы проверить, что имя роли не опечатка.
Color readRole(ColorScheme s, String key) => switch (key) {
  'primary' => s.primary,
  'onPrimary' => s.onPrimary,
  'primaryContainer' => s.primaryContainer,
  'onPrimaryContainer' => s.onPrimaryContainer,
  'secondary' => s.secondary,
  'onSecondary' => s.onSecondary,
  'secondaryContainer' => s.secondaryContainer,
  'onSecondaryContainer' => s.onSecondaryContainer,
  'tertiary' => s.tertiary,
  'onTertiary' => s.onTertiary,
  'tertiaryContainer' => s.tertiaryContainer,
  'onTertiaryContainer' => s.onTertiaryContainer,
  'error' => s.error,
  'onError' => s.onError,
  'errorContainer' => s.errorContainer,
  'onErrorContainer' => s.onErrorContainer,
  'background' => s.background,
  'onBackground' => s.onBackground,
  'surface' => s.surface,
  'onSurface' => s.onSurface,
  'surfaceVariant' => s.surfaceVariant,
  'onSurfaceVariant' => s.onSurfaceVariant,
  'surfaceDim' => s.surfaceDim,
  'surfaceBright' => s.surfaceBright,
  'surfaceContainerLowest' => s.surfaceContainerLowest,
  'surfaceContainerLow' => s.surfaceContainerLow,
  'surfaceContainer' => s.surfaceContainer,
  'surfaceContainerHigh' => s.surfaceContainerHigh,
  'surfaceContainerHighest' => s.surfaceContainerHighest,
  'inverseSurface' => s.inverseSurface,
  'onInverseSurface' => s.onInverseSurface,
  'inversePrimary' => s.inversePrimary,
  'surfaceTint' => s.surfaceTint,
  'scrim' => s.scrim,
  'shadow' => s.shadow,
  'outline' => s.outline,
  'outlineVariant' => s.outlineVariant,
  _ => s.surface,
};

ColorScheme _writeRoles(ColorScheme s, Map<String, Color> r) => s.copyWith(
  primary: r['primary'],
  onPrimary: r['onPrimary'],
  primaryContainer: r['primaryContainer'],
  onPrimaryContainer: r['onPrimaryContainer'],
  secondary: r['secondary'],
  onSecondary: r['onSecondary'],
  secondaryContainer: r['secondaryContainer'],
  onSecondaryContainer: r['onSecondaryContainer'],
  tertiary: r['tertiary'],
  onTertiary: r['onTertiary'],
  tertiaryContainer: r['tertiaryContainer'],
  onTertiaryContainer: r['onTertiaryContainer'],
  error: r['error'],
  onError: r['onError'],
  errorContainer: r['errorContainer'],
  onErrorContainer: r['onErrorContainer'],
  background: r['background'],
  onBackground: r['onBackground'],
  surface: r['surface'],
  onSurface: r['onSurface'],
  surfaceVariant: r['surfaceVariant'],
  onSurfaceVariant: r['onSurfaceVariant'],
  surfaceDim: r['surfaceDim'],
  surfaceBright: r['surfaceBright'],
  surfaceContainerLowest: r['surfaceContainerLowest'],
  surfaceContainerLow: r['surfaceContainerLow'],
  surfaceContainer: r['surfaceContainer'],
  surfaceContainerHigh: r['surfaceContainerHigh'],
  surfaceContainerHighest: r['surfaceContainerHighest'],
  inverseSurface: r['inverseSurface'],
  onInverseSurface: r['onInverseSurface'],
  inversePrimary: r['inversePrimary'],
  surfaceTint: r['surfaceTint'],
  scrim: r['scrim'],
  shadow: r['shadow'],
  outline: r['outline'],
  outlineVariant: r['outlineVariant'],
);

// ---------------------------------------------------------------------------
//  Hex и имена вариантов
// ---------------------------------------------------------------------------

/// `#RRGGBB` (или `#AARRGGBB`, или без `#`). `null`, если не цвет.
Color? parseHexColor(String? raw) {
  if (raw == null) return null;
  var h = raw.trim().replaceAll('#', '').replaceAll(' ', '');
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(value);
}

String hexOf(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final alpha = (argb >> 24) & 0xFF;
  return alpha == 0xFF
      ? '#$rgb'
      : '#${alpha.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
}

/// Вариант палитры M3 — то, как из seed'а расходятся тона ролей.
///
/// Порядок = порядок в UI: сначала два «рабочих», затем остальные.
const List<DynamicSchemeVariant> themeVariants = [
  DynamicSchemeVariant.fidelity,
  DynamicSchemeVariant.vibrant,
  DynamicSchemeVariant.tonalSpot,
  DynamicSchemeVariant.expressive,
  DynamicSchemeVariant.content,
  DynamicSchemeVariant.neutral,
  DynamicSchemeVariant.monochrome,
  DynamicSchemeVariant.rainbow,
  DynamicSchemeVariant.fruitSalad,
];

String variantKey(DynamicSchemeVariant v) => v.name;

/// Вариант по умолчанию для пресетов, где он не выбран.
const DynamicSchemeVariant defaultVariant = DynamicSchemeVariant.vibrant;

DynamicSchemeVariant? variantFromKey(String? key) {
  if (key == null) return null;
  for (final v in DynamicSchemeVariant.values) {
    if (v.name == key) return v;
  }
  return null;
}

/// Человеческое объяснение: что выбрать, если нужен «именно мой цвет».
Map<String, String> get variantHints => {
  'fidelity': tr('Точная — оттенок и насыщенность seed сохраняются один в один'),
  'vibrant':
      tr('Яркая — насыщенность seed усиливается, цвет отличается от исходного'),
  'tonalSpot': tr('Material 3 по умолчанию — мягкая, слегка приглушённая'),
  'expressive': tr('Эмоциональная — сине-родовые акценты, оттенок seed уходит'),
  'content': tr('Из самого seed, включая его оттенок у поверхностей'),
  'neutral': tr('Почти монохром — акцент тусклый, всё в серых тонах'),
  'monochrome': tr('Графит — оттенок игнорируется полностью, только серые'),
  'rainbow': tr('Игрушечная — оттенок seed в тему не попадает вовсе'),
  'fruitSalad': tr('Игрушечная, фруктовая — как rainbow, но мягче'),

};
