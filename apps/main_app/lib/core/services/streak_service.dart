import 'package:canvas_app/core/services/api_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StreakService {
  final ApiService _apiService;

  StreakService(this._apiService);

  /// Проверяет, нужно ли обновлять стрик, и если да — обновляет.
  /// Возвращает Map с ответом сервера или null, если обновление не требовалось/ошибка.
  Future<Map<String, dynamic>?> checkAndUpdateStreak() async {
    try {
      // Сервер сам ведет точный учет времени и определяет, наступил ли новый день по UTC.
      // Поэтому мы просто делаем запрос при старте сессии без локального кэширования дат.
      final response = await _apiService.post('profiles/update-streak');
      return response;
    } catch (e) {
      print("Streak update failed: $e");
      return null;
    }
  }
}

final streakServiceProvider = Provider((ref) {
  final api = ref.watch(apiServiceProvider);
  return StreakService(api);
});
