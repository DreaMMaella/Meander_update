import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Глобальная громкость квеста (0.0 - 1.0). Умножается на все
/// скриптовые и нодовые громкости. Позволяет игроку приглушить
/// квест не трогая системную громкость.
const _kGlobalVolumeKey = 'mnd_global_volume';

class GlobalAudioVolumeNotifier extends StateNotifier<double> {
  GlobalAudioVolumeNotifier() : super(1.0) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_kGlobalVolumeKey);
      if (v != null) state = v.clamp(0.0, 1.0);
    } catch (_) {}
  }

  Future<void> setVolume(double v) async {
    final clamped = v.clamp(0.0, 1.0);
    state = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kGlobalVolumeKey, clamped);
    } catch (_) {}
  }
}

final globalAudioVolumeProvider =
    StateNotifierProvider<GlobalAudioVolumeNotifier, double>(
  (ref) => GlobalAudioVolumeNotifier(),
);
