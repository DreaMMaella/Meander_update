import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Глобальное предпочтение игрока: с какой скоростью (и показывать ли вообще)
/// анимацию появления текста, которую включил автор квеста.
///
/// Автор задаёт режим у конкретного текста (`item.textReveal`), игрок имеет
/// право это не смотреть — поэтому выключатель живёт отдельно от квеста и
/// хранится как громкость: SharedPreferences, провайдер, значение на всё
/// приложение.
enum TextRevealPreference {
  off('Выкл', 0),
  slow('Медленно', 0.5),
  normal('Обычно', 1),
  fast('Быстро', 2);

  const TextRevealPreference(this.label, this.factor);

  /// Подпись в окне настроек плеера.
  final String label;

  /// Множитель скорости автора. У [off] он 0 — режим выключен совсем.
  final double factor;

  bool get isEnabled => this != off;

  static TextRevealPreference parse(Object? raw) {
    final name = (raw as String?)?.trim();
    return TextRevealPreference.values.firstWhere(
      (p) => p.name == name,
      orElse: () => normal,
    );
  }
}

/// Ключ в SharedPreferences. Публичный: тесты и отладка обязаны уметь
/// подставить нужное значение, не угадывая строку.
const String kPlayerTextRevealPreferenceKey = 'player_text_reveal_preference';

class TextRevealPreferenceNotifier extends StateNotifier<TextRevealPreference> {
  TextRevealPreferenceNotifier() : super(TextRevealPreference.normal) {
    loaded = _load().whenComplete(() => _isLoaded = true);
  }

  /// Чтение с диска не мгновенное, а первый текст ноды монтируется сразу.
  /// Хост анимации ждёт этот future, иначе игрок с «Выкл» успел бы увидеть
  /// несколько набираемых кадров до приезда значения.
  late final Future<void> loaded;

  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = TextRevealPreference.parse(
        prefs.getString(kPlayerTextRevealPreferenceKey),
      );
    } catch (_) {
      // Нет хранилища (standalone-плеер, тест) — остаётся дефолт.
    }
  }

  Future<void> setPreference(TextRevealPreference value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPlayerTextRevealPreferenceKey, value.name);
    } catch (_) {}
  }
}

final textRevealPreferenceProvider =
    StateNotifierProvider<TextRevealPreferenceNotifier, TextRevealPreference>(
      (ref) => TextRevealPreferenceNotifier(),
    );
