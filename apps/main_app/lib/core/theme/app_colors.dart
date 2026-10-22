import 'package:flutter/material.dart';

enum AccentTheme { beige, forest }

class AppColors {
  static AccentTheme _currentAccent = AccentTheme.beige;

  static void switchAccent(AccentTheme accent) {
    _currentAccent = accent;
  }

  static AppColors of(Brightness brightness) {
    if (_currentAccent == AccentTheme.forest) {
      return brightness == Brightness.light
          ? defaultLightForest
          : defaultDarkForest;
    }
    return brightness == Brightness.light ? defaultLight : defaultDark;
  }

  // Фоны
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceLight;

  // Текст
  final Color textPrimary;
  final Color textSecondary;
  final Color textPlaceholder;

  // Акцент
  final Color accent;
  Color get accentLight => accent.withOpacity(0.2);
  Color get accentSubtle => accent.withOpacity(0.08);

  // Границы
  final Color border;
  Color get borderLight => border.withOpacity(0.35);

  // Кнопки
  final Color primaryButtonBorder;
  final Color primaryButtonText;
  final Color fabBackground;
  final Color fabForeground;

  // Навигация
  final Color navBackground;
  final Color navInactive;

  // Состояния
  final Color error;
  final Color shimmerBase;
  final Color shimmerHighlight;

  // Уведомления
  final Color notifLike;
  final Color notifReview;
  final Color notifUpdate;
  final Color notifPublish;
  final Color notifFollow;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textPlaceholder,
    required this.accent,
    required this.border,
    required this.primaryButtonBorder,
    required this.primaryButtonText,
    required this.fabBackground,
    required this.fabForeground,
    required this.navBackground,
    required this.navInactive,
    required this.error,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.notifLike,
    required this.notifReview,
    required this.notifUpdate,
    required this.notifPublish,
    required this.notifFollow,
  });

  Map<String, dynamic> toJson() => {
    'background': background.value.toRadixString(16).padLeft(8, '0'),
    'surface': surface.value.toRadixString(16).padLeft(8, '0'),
    'surfaceAlt': surfaceAlt.value.toRadixString(16).padLeft(8, '0'),
    'surfaceLight': surfaceLight.value.toRadixString(16).padLeft(8, '0'),
    'textPrimary': textPrimary.value.toRadixString(16).padLeft(8, '0'),
    'textSecondary': textSecondary.value.toRadixString(16).padLeft(8, '0'),
    'textPlaceholder': textPlaceholder.value.toRadixString(16).padLeft(8, '0'),
    'accent': accent.value.toRadixString(16).padLeft(8, '0'),
    'border': border.value.toRadixString(16).padLeft(8, '0'),
    'primaryButtonBorder': primaryButtonBorder.value
        .toRadixString(16)
        .padLeft(8, '0'),
    'primaryButtonText': primaryButtonText.value
        .toRadixString(16)
        .padLeft(8, '0'),
    'fabBackground': fabBackground.value.toRadixString(16).padLeft(8, '0'),
    'fabForeground': fabForeground.value.toRadixString(16).padLeft(8, '0'),
    'navBackground': navBackground.value.toRadixString(16).padLeft(8, '0'),
    'navInactive': navInactive.value.toRadixString(16).padLeft(8, '0'),
    'error': error.value.toRadixString(16).padLeft(8, '0'),
    'shimmerBase': shimmerBase.value.toRadixString(16).padLeft(8, '0'),
    'shimmerHighlight': shimmerHighlight.value
        .toRadixString(16)
        .padLeft(8, '0'),
    'notifLike': notifLike.value.toRadixString(16).padLeft(8, '0'),
    'notifReview': notifReview.value.toRadixString(16).padLeft(8, '0'),
    'notifUpdate': notifUpdate.value.toRadixString(16).padLeft(8, '0'),
    'notifPublish': notifPublish.value.toRadixString(16).padLeft(8, '0'),
    'notifFollow': notifFollow.value.toRadixString(16).padLeft(8, '0'),
  };

  factory AppColors.fromJson(Map<String, dynamic> json) {
    Color parse(String key) {
      final hex = json[key] as String;
      return Color(int.parse(hex, radix: 16));
    }

    return AppColors(
      background: parse('background'),
      surface: parse('surface'),
      surfaceAlt: parse('surfaceAlt'),
      surfaceLight: parse('surfaceLight'),
      textPrimary: parse('textPrimary'),
      textSecondary: parse('textSecondary'),
      textPlaceholder: parse('textPlaceholder'),
      accent: parse('accent'),
      border: parse('border'),
      primaryButtonBorder: parse('primaryButtonBorder'),
      primaryButtonText: parse('primaryButtonText'),
      fabBackground: parse('fabBackground'),
      fabForeground: parse('fabForeground'),
      navBackground: parse('navBackground'),
      navInactive: parse('navInactive'),
      error: parse('error'),
      shimmerBase: parse('shimmerBase'),
      shimmerHighlight: parse('shimmerHighlight'),
      notifLike: parse('notifLike'),
      notifReview: parse('notifReview'),
      notifUpdate: parse('notifUpdate'),
      notifPublish: parse('notifPublish'),
      notifFollow: parse('notifFollow'),
    );
  }

  static const AppColors defaultDark = AppColors(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceAlt: Color(0xFF141414),
    surfaceLight: Color(0xFF252525),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA0A0A0),
    textPlaceholder: Color(0xFF888888),
    accent: Color(0xFFE2D9C9),
    border: Color(0xFF333333),
    primaryButtonBorder: Color(0xFFE2D9C9),
    primaryButtonText: Color(0xFFE2D9C9),
    fabBackground: Color(0xFFE2D9C9),
    fabForeground: Color(0xFF121212),
    navBackground: Color(0xFF121212),
    navInactive: Color(0xFF888888),
    error: Color(0xFFFF5252),
    shimmerBase: Color(0xFF1E1E1E),
    shimmerHighlight: Color(0xFF2A2A2A),
    notifLike: Color(0xFFFF5C8A),
    notifReview: Color(0xFFFFC857),
    notifUpdate: Color(0xFF5AA9FF),
    notifPublish: Color(0xFF3DDC84),
    notifFollow: Color(0xFF9D6BFF),
  );

  static const AppColors defaultLight = AppColors(
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFEFEF),
    surfaceLight: Color(0xFFE8E8E8),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF666666),
    textPlaceholder: Color(0xFF999999),
    accent: Color(0xFFE2D9C9),
    border: Color(0xFFD0D0D0),
    primaryButtonBorder: Color(0xFFE2D9C9),
    primaryButtonText: Color(0xFF1A1A1A),
    fabBackground: Color(0xFFE2D9C9),
    fabForeground: Color(0xFF1A1A1A),
    navBackground: Color(0xFFFFFFFF),
    navInactive: Color(0xFF999999),
    error: Color(0xFFE53935),
    shimmerBase: Color(0xFFE0E0E0),
    shimmerHighlight: Color(0xFFF0F0F0),
    notifLike: Color(0xFFE91E63),
    notifReview: Color(0xFFFFA000),
    notifUpdate: Color(0xFF1976D2),
    notifPublish: Color(0xFF388E3C),
    notifFollow: Color(0xFF7B1FA2),
  );

  static const AppColors defaultDarkForest = AppColors(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceAlt: Color(0xFF141414),
    surfaceLight: Color(0xFF252525),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA0A0A0),
    textPlaceholder: Color(0xFF888888),
    accent: Color(0xFF4CAF50),
    border: Color(0xFF333333),
    primaryButtonBorder: Color(0xFF4CAF50),
    primaryButtonText: Color(0xFF4CAF50),
    fabBackground: Color(0xFF4CAF50),
    fabForeground: Color(0xFF121212),
    navBackground: Color(0xFF121212),
    navInactive: Color(0xFF888888),
    error: Color(0xFFFF5252),
    shimmerBase: Color(0xFF1E1E1E),
    shimmerHighlight: Color(0xFF2A2A2A),
    notifLike: Color(0xFFFF5C8A),
    notifReview: Color(0xFFFFC857),
    notifUpdate: Color(0xFF5AA9FF),
    notifPublish: Color(0xFF66BB6A),
    notifFollow: Color(0xFF9D6BFF),
  );

  static const AppColors defaultLightForest = AppColors(
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFEFEF),
    surfaceLight: Color(0xFFE8E8E8),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF666666),
    textPlaceholder: Color(0xFF999999),
    accent: Color(0xFF4CAF50),
    border: Color(0xFFD0D0D0),
    primaryButtonBorder: Color(0xFF4CAF50),
    primaryButtonText: Color(0xFF1A1A1A),
    fabBackground: Color(0xFF4CAF50),
    fabForeground: Color(0xFFFFFFFF),
    navBackground: Color(0xFFFFFFFF),
    navInactive: Color(0xFF999999),
    error: Color(0xFFE53935),
    shimmerBase: Color(0xFFE0E0E0),
    shimmerHighlight: Color(0xFFF0F0F0),
    notifLike: Color(0xFFE91E63),
    notifReview: Color(0xFFFFA000),
    notifUpdate: Color(0xFF1976D2),
    notifPublish: Color(0xFF388E3C),
    notifFollow: Color(0xFF7B1FA2),
  );
}
