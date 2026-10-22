import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/models/review_model.dart';
import 'package:canvas_app/models/vote_model.dart';
import 'package:canvas_app/models/quest_screenshot_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Загрузка отзывов к квесту (публично)
final reviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>(
  (ref, questId) async {
    final apiService = ref.watch(apiServiceProvider);
    final response = await apiService.get('quests/$questId/reviews');
    return (response as List).map((json) => Review.fromJson(json)).toList();
  },
);

// Получение голоса текущего пользователя (Приватный запрос)
final userVoteProvider = FutureProvider.autoDispose.family<UserVote, String>((
  ref,
  questId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id');

  // Если не авторизован - голоса нет
  if (userId == null) {
    return UserVote(VoteType.none);
  }

  final apiService = ref.watch(apiServiceProvider);
  try {
    final response = await apiService.get('quests/$questId/my-vote');
    if (response == null || response['is_like'] == null) {
      return UserVote(VoteType.none);
    }
    return UserVote(response['is_like'] ? VoteType.like : VoteType.dislike);
  } catch (e) {
    return UserVote(VoteType.none);
  }
});

// Получение отзыва текущего пользователя (Приватный запрос)
final userReviewProvider = FutureProvider.autoDispose
    .family<(int, String), String>((ref, questId) async {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      if (userId == null) {
        return (0, '');
      }

      final apiService = ref.watch(apiServiceProvider);
      try {
        final response = await apiService.get('quests/$questId/my-review');
        final rating = (response['rating'] as int?) ?? 0;
        final reviewText = (response['text_content'] as String?) ?? '';
        return (rating, reviewText);
      } catch (e) {
        return (0, '');
      }
    });

// Скриншоты квеста (Публично)
final screenshotsProvider = FutureProvider.autoDispose
    .family<List<QuestScreenshot>, String>((ref, questId) async {
      final apiService = ref.watch(apiServiceProvider);
      try {
        final response = await apiService.get('quests/$questId/screenshots');
        return (response as List)
            .map((json) => QuestScreenshot.fromJson(json))
            .toList();
      } catch (_) {
        return [];
      }
    });
