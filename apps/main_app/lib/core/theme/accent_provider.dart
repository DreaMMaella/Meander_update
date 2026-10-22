import 'package:canvas_app/core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accentKey = 'accent_theme';

class AccentThemeNotifier extends StateNotifier<AccentTheme> {
  AccentThemeNotifier() : super(AccentTheme.beige);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_accentKey);
    switch (value) {
      case 'forest':
        state = AccentTheme.forest;
        break;
      default:
        state = AccentTheme.beige;
    }
    AppColors.switchAccent(state);
  }

  Future<void> setAccent(AccentTheme accent) async {
    state = accent;
    AppColors.switchAccent(accent);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentKey, accent.name);
  }
}

final accentThemeProvider =
    StateNotifierProvider<AccentThemeNotifier, AccentTheme>((ref) {
      return AccentThemeNotifier();
    });
