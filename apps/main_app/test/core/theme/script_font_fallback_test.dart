import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/theme/app_theme.dart';
import 'package:canvas_app/core/theme/theme_registry.dart';

/// Manrope закрывает только латиницу и кириллицу. Всё остальное — хан, канны,
/// хангыль, арабица, деванагари — обязано доставаться из fallback-цепочки,
/// иначе на Linux вместо 简体中文 остаются квадратики.
void main() {
  final pickers = <String, TextStyle? Function(TextTheme)>{
    'titleMedium': (t) => t.titleMedium,
    'titleLarge': (t) => t.titleLarge,
    'bodyMedium': (t) => t.bodyMedium,
    'bodyLarge': (t) => t.bodyLarge,
    'labelLarge': (t) => t.labelLarge,
  };

  for (final preset in ThemeRegistry.builtIn) {
    for (final brightness in Brightness.values) {
      test('${preset.id}/${brightness.name}: тема умеет восточно-азиатские '
          'письменности', () {
        final textTheme = AppTheme.fromPreset(preset, brightness).textTheme;
        for (final entry in pickers.entries) {
          final style = entry.value(textTheme);
          expect(style, isNotNull, reason: '${entry.key} пропал из темы');
          final fallback = style!.fontFamilyFallback ?? const <String>[];
          expect(
            fallback,
            containsAll(const <String>['Noto Sans CJK SC', 'Noto Sans KR']),
            reason: '${entry.key}: нет CJK/хангыля в fallback — иероглифы '
                'будут квадратиками',
          );
        }
      });
    }
  }
}
