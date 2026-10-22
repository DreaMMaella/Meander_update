import 'package:pdf/pdf.dart';

import 'package:canvas_app/core/l10n/l10n.dart';

/// Цветовая тема для PDF-экспорта.
///
/// Названия живут не в конструкторе, а в геттерах: const-значение поля
/// переключением языка не снять, а метка читается человеком в листе
/// параметров экспорта.
enum PdfTheme {
  light,
  dark,
  sepia,
  parchment;

  String get label => switch (this) {
    PdfTheme.light => tr('Светлая'),
    PdfTheme.dark => tr('Тёмная'),
    PdfTheme.sepia => tr('Сепия'),
    PdfTheme.parchment => tr('Пергамент'),
  };

  String get description => switch (this) {
    PdfTheme.light => tr('Бумажная классика'),
    PdfTheme.dark => tr('Для чтения в темноте'),
    PdfTheme.sepia => tr('Тёплая бумага'),
    PdfTheme.parchment => tr('Винтажная стилизация'),
  };

  /// Палитра темы для PDF.
  PdfThemeColors get colors {
    switch (this) {
      case PdfTheme.light:
        return const PdfThemeColors(
          background: PdfColors.grey50,
          surface: PdfColors.white,
          ink: PdfColors.blueGrey900,
          inkSoft: PdfColors.blueGrey700,
          muted: PdfColors.grey600,
          mutedSoft: PdfColors.grey500,
          hairline: PdfColors.grey300,
          accent: PdfColors.blueGrey800,
          choiceFill: PdfColors.white,
          chatIn: PdfColors.grey100,
          chatOut: PdfColors.blueGrey50,
          codeBg: PdfColors.grey100,
        );
      case PdfTheme.dark:
        return PdfThemeColors(
          background: PdfColor.fromInt(0xFF1A1F26),
          surface: PdfColor.fromInt(0xFF222831),
          ink: PdfColor.fromInt(0xFFE8ECF1),
          inkSoft: PdfColor.fromInt(0xFFB8C0CC),
          muted: PdfColor.fromInt(0xFF8995A3),
          mutedSoft: PdfColor.fromInt(0xFF6B7785),
          hairline: PdfColor.fromInt(0xFF3A434E),
          accent: PdfColor.fromInt(0xFF4FB7C9),
          choiceFill: PdfColor.fromInt(0xFF272E37),
          chatIn: PdfColor.fromInt(0xFF2B333C),
          chatOut: PdfColor.fromInt(0xFF2F4250),
          codeBg: PdfColor.fromInt(0xFF1F262E),
        );
      case PdfTheme.sepia:
        return PdfThemeColors(
          background: PdfColor.fromInt(0xFFF5ECD9),
          surface: PdfColor.fromInt(0xFFF9F2E1),
          ink: PdfColor.fromInt(0xFF3D2E1F),
          inkSoft: PdfColor.fromInt(0xFF5D4733),
          muted: PdfColor.fromInt(0xFF8B7256),
          mutedSoft: PdfColor.fromInt(0xFFA38B6D),
          hairline: PdfColor.fromInt(0xFFDCC9A4),
          accent: PdfColor.fromInt(0xFF8B4513),
          choiceFill: PdfColor.fromInt(0xFFFAF4E4),
          chatIn: PdfColor.fromInt(0xFFEDE0C2),
          chatOut: PdfColor.fromInt(0xFFD9C29A),
          codeBg: PdfColor.fromInt(0xFFE8DDC1),
        );
      case PdfTheme.parchment:
        return PdfThemeColors(
          background: PdfColor.fromInt(0xFFE9DDBC),
          surface: PdfColor.fromInt(0xFFF0E6C9),
          ink: PdfColor.fromInt(0xFF2B1F12),
          inkSoft: PdfColor.fromInt(0xFF4A3A26),
          muted: PdfColor.fromInt(0xFF7A6448),
          mutedSoft: PdfColor.fromInt(0xFF9A8266),
          hairline: PdfColor.fromInt(0xFFC7B58E),
          accent: PdfColor.fromInt(0xFF6B4423),
          choiceFill: PdfColor.fromInt(0xFFEFE3BD),
          chatIn: PdfColor.fromInt(0xFFE0D2A4),
          chatOut: PdfColor.fromInt(0xFFCDB988),
          codeBg: PdfColor.fromInt(0xFFD8C8A0),
        );
    }
  }
}

/// Палитра темы для PDF.
class PdfThemeColors {
  final PdfColor background;
  final PdfColor surface;
  final PdfColor ink;
  final PdfColor inkSoft;
  final PdfColor muted;
  final PdfColor mutedSoft;
  final PdfColor hairline;
  final PdfColor accent;
  final PdfColor choiceFill;
  final PdfColor chatIn;
  final PdfColor chatOut;
  final PdfColor codeBg;

  const PdfThemeColors({
    required this.background,
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.mutedSoft,
    required this.hairline,
    required this.accent,
    required this.choiceFill,
    required this.chatIn,
    required this.chatOut,
    required this.codeBg,
  });
}

/// Размер базового шрифта.
enum PdfTextSize {
  small(10.0),
  normal(11.5),
  large(13.0),
  huge(14.5);

  final double basePt;
  const PdfTextSize(this.basePt);

  String get label => switch (this) {
    PdfTextSize.small => tr('Мелкий'),
    PdfTextSize.normal => tr('Обычный'),
    PdfTextSize.large => tr('Крупный'),
    PdfTextSize.huge => tr('Очень крупный'),
  };
}

/// Опции экспорта PDF.
///
/// Брендинг Meander (плашка на обложке, футер каждой страницы, метаданные)
/// присутствует всегда и не отключается — это часть условий использования.
class PdfExportOptions {
  final PdfTheme theme;
  final PdfTextSize textSize;
  final bool includeCover;
  final bool includeImages;
  final bool justifyText;
  final bool linkChoices;

  const PdfExportOptions({
    this.theme = PdfTheme.light,
    this.textSize = PdfTextSize.normal,
    this.includeCover = true,
    this.includeImages = true,
    this.justifyText = true,
    this.linkChoices = true,
  });

  PdfExportOptions copyWith({
    PdfTheme? theme,
    PdfTextSize? textSize,
    bool? includeCover,
    bool? includeImages,
    bool? justifyText,
    bool? linkChoices,
  }) {
    return PdfExportOptions(
      theme: theme ?? this.theme,
      textSize: textSize ?? this.textSize,
      includeCover: includeCover ?? this.includeCover,
      includeImages: includeImages ?? this.includeImages,
      justifyText: justifyText ?? this.justifyText,
      linkChoices: linkChoices ?? this.linkChoices,
    );
  }
}
