import 'package:canvas_app/core/theme/accent_provider.dart';
import 'package:canvas_app/core/theme/theme_preset_provider.dart';
import 'package:canvas_app/core/theme/theme_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final initThemeProvider = FutureProvider<void>((ref) async {
  await ref.read(themeModeProvider.notifier).load();
  // Новая система — пресеты тем.
  await ref.read(themePresetProvider.notifier).load();
  // Старая система акцентов (deprecated, оставлена для совместимости).
  await ref.read(accentThemeProvider.notifier).load();
});
