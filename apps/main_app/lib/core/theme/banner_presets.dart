import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Пресет градиентного баннера для шапки профиля.
@immutable
class BannerPreset {
  final String id;
  final String name;
  final List<Color> colors;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  /// Опциональная декоративная иконка, рисуется в углу.
  final IconData? accentIcon;

  const BannerPreset({
    required this.id,
    required this.name,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
    this.accentIcon,
  });

  LinearGradient toGradient() =>
      LinearGradient(begin: begin, end: end, colors: colors);
}

/// Каталог пресетов. **id** должны совпадать с whitelist на бэке
/// (`backend/src/routes/profiles.ts: ALLOWED_BANNER_IDS`).
// Геттер, а не final-таблица: список строится под текущий язык, иначе
// переключение языка не перекрасило бы эти подписи.
List<BannerPreset> get kBannerPresets => [
  BannerPreset(
    id: 'beige',
    name: tr('Бежевый'),
    colors: [Color(0xFFE2D9C9), Color(0xFFB8A88A)],
    accentIcon: Icons.spa_rounded,
  ),
  BannerPreset(
    id: 'forest',
    name: tr('Лесной'),
    colors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
    accentIcon: Icons.park_rounded,
  ),
  BannerPreset(
    id: 'royal_purple',
    name: tr('Королевский пурпур'),
    colors: [Color(0xFF6750A4), Color(0xFF21005D)],
    accentIcon: Icons.auto_awesome_rounded,
  ),
  BannerPreset(
    id: 'sunset',
    name: tr('Закат'),
    colors: [Color(0xFFFF7043), Color(0xFFFFB300)],
    accentIcon: Icons.wb_sunny_rounded,
  ),
  BannerPreset(
    id: 'ocean',
    name: tr('Океан'),
    colors: [Color(0xFF0288D1), Color(0xFF00ACC1)],
    accentIcon: Icons.waves_rounded,
  ),
  BannerPreset(
    id: 'rose',
    name: tr('Роза'),
    colors: [Color(0xFFE91E63), Color(0xFFAD1457)],
    accentIcon: Icons.local_florist_rounded,
  ),
  BannerPreset(
    id: 'cyber',
    name: tr('Кибер'),
    colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
    accentIcon: Icons.bolt_rounded,
  ),
  BannerPreset(
    id: 'mono',
    name: tr('Монохром'),
    colors: [Color(0xFF455A64), Color(0xFF263238)],
    accentIcon: Icons.grain_rounded,
  ),
  BannerPreset(
    id: 'aurora',
    name: tr('Аврора'),
    colors: [Color(0xFF26A69A), Color(0xFF7E57C2)],
    accentIcon: Icons.brightness_5_rounded,
  ),
];

BannerPreset? bannerPresetById(String? id) {
  if (id == null) return null;
  for (final p in kBannerPresets) {
    if (p.id == id) return p;
  }
  return null;
}
