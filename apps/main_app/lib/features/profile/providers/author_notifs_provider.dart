import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/services/api_service.dart';

/// Настройки уведомлений об авторах.
///
/// `mode: 'all'` — пишем обо всех, `exceptions` чёрный список;
/// `mode: 'none'` — молчим обо всех, `exceptions` белый список.
class AuthorNotifsSettings {
  const AuthorNotifsSettings({required this.mode, required this.exceptions});

  final String mode; // 'all' or 'none'
  final List<String> exceptions;

  /// Дефолт для тех, у кого ответа сервера нет: гостя, обрыва сети, первого
  /// кадра до загрузки профиля. Уведомления по умолчанию приходят — молчание
  /// человек включит сам.
  static const AuthorNotifsSettings unknown = AuthorNotifsSettings(
    mode: 'all',
    exceptions: <String>[],
  );

  factory AuthorNotifsSettings.fromJson(Map<String, dynamic> json) {
    return AuthorNotifsSettings(
      mode: json['mode'] as String? ?? 'all',
      exceptions:
          (json['exceptions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
    );
  }

  bool isMuted(String authorId) {
    final hasException = exceptions.contains(authorId);
    if (mode == 'all') {
      return hasException; // Замьючен, если в блэклисте
    }
    return !hasException; // Замьючен, если НЕ в вайтлисте
  }
}

class AuthorNotifsSettingsNotifier
    extends StateNotifier<AsyncValue<AuthorNotifsSettings>> {
  final Ref ref;

  AuthorNotifsSettingsNotifier(this.ref)
    : super(const AsyncValue.data(AuthorNotifsSettings.unknown)) {
    _load();
  }

  bool _inFlight = false;

  /// Гостю эти настройки не существуют: без токена эндпоинт отвечает 401, а
  /// приземлённая сюда ошибка раньше вырывалась наружу прямо из `build()`
  /// шапки профиля — вместо баннера человек видел серый прямоугольник
  /// Flutter (#289). Поэтому гость остаётся на дефолте и запрос не делает.
  Future<void> _load() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('jwt_token') == null) return;
      final api = ref.read(apiServiceProvider);
      final response = await api.get('profiles/author-notifs-settings');
      if (response is Map<String, dynamic>) {
        state = AsyncValue.data(AuthorNotifsSettings.fromJson(response));
      }
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    } finally {
      _inFlight = false;
    }
  }

  /// Открыли профиль ещё раз — пробуем снова, если прошлая попытка упала
  /// (обрыв сети на старте приложения, сон телефона, 401 до восстановления
  /// сессии). Без этого одна неудача на холодном старте отравляла провайдер
  /// до конца работы приложения.
  Future<void> retryIfFailed() async {
    if (state.hasError) await _load();
  }

  /// true — сервер принял переключение. Возвращаем результат, чтобы шапка
  /// не рапортовала «Уведомления отключены» при отменённом запросе.
  Future<bool> toggleAuthor(String authorId) async {
    final current = state.valueOrNull ?? AuthorNotifsSettings.unknown;

    final newExceptions = List<String>.from(current.exceptions);
    if (newExceptions.contains(authorId)) {
      newExceptions.remove(authorId);
    } else {
      newExceptions.add(authorId);
    }

    // Оптимистичное обновление UI
    final newStateData = AuthorNotifsSettings(
      mode: current.mode,
      exceptions: newExceptions,
    );
    state = AsyncValue.data(newStateData);

    try {
      final api = ref.read(apiServiceProvider);
      await api.post('profiles/author-notifs-settings', body: {
        'mode': newStateData.mode,
        'exceptions': newStateData.exceptions,
      });
      return true;
    } catch (_) {
      // Откат при ошибке: человек видит прежний список, затем свежий ответ
      // сервера. Состояние остаётся данными — сборка шапки не бросается.
      state = AsyncValue.data(current);
      await _load();
      return false;
    }
  }
}

final authorNotifsSettingsProvider =
    StateNotifierProvider<AuthorNotifsSettingsNotifier,
        AsyncValue<AuthorNotifsSettings>>((ref) {
  return AuthorNotifsSettingsNotifier(ref);
});
