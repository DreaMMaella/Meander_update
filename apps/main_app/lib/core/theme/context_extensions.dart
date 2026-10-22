import 'package:canvas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

extension ThemeColorsX on BuildContext {
  AppColors get themeColors => AppColors.of(Theme.of(this).brightness);
}
