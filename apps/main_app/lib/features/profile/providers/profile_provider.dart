import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/models/market_quest_model.dart';
import 'package:canvas_app/models/review_model.dart';
import 'package:canvas_app/models/user_profile_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- ВСПОМОГАТЕЛЬНЫЕ МОДЕЛИ ---

class Achievement {
  final String id;
  final String name;
  final String description;
  final String iconName;
  final int xpReward;
  final bool isSecret;
  final String category;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    this.xpReward = 0,
    this.isSecret = false,
    this.category = 'common',
  });

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      iconName: json['icon_name'] as String,
      xpReward: (json['xp_reward'] as num?)?.toInt() ?? 0,
      isSecret: json['is_secret'] as bool? ?? false,
      category: json['category'] as String? ?? 'common',
    );
  }
}

class UserAchievement {
  final Achievement achievement;
  final DateTime achievedAt;

  UserAchievement({required this.achievement, required this.achievedAt});
}

// --- ПРОВАЙДЕРЫ ---

final userProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, String>((ref, userId) async {
      try {
        final apiService = ref.watch(apiServiceProvider);
        final response = await apiService.get('profiles/$userId');
        return UserProfile.fromJson(response);
      } catch (e, stack) {
        print('🔍 [UserProfileProvider] Error: $e\nStack: $stack');
        rethrow;
      }
    });

final userPublicationsProvider = FutureProvider.autoDispose
    .family<List<MarketQuest>, String>((ref, userId) async {
      try {
        final apiService = ref.watch(apiServiceProvider);
        final response = await apiService.get('profiles/$userId/quests');

        if (response is! List) {
          return [];
        }

        final quests = <MarketQuest>[];
        for (final json in response) {
          try {
            quests.add(MarketQuest.fromJson(json));
          } catch (e) {
            print('⚠️ [UserPublications] Parse error: $e');
          }
        }
        return quests;
      } catch (e) {
        print('❌ [UserPublications] Error: $e');
        return [];
      }
    });

final userReviewsProvider = FutureProvider.autoDispose
    .family<List<Review>, String>((ref, userId) async {
      try {
        final apiService = ref.watch(apiServiceProvider);
        final response = await apiService.get('profiles/$userId/reviews');

        if (response is! List) {
          return [];
        }

        final reviews = <Review>[];
        for (final json in response) {
          try {
            reviews.add(Review.fromJson(json));
          } catch (e) {
            print('⚠️ [UserReviews] Parse error: $e');
          }
        }
        return reviews;
      } catch (e) {
        print('❌ [UserReviews] Error: $e');
        return [];
      }
    });

// --- ПРОВАЙДЕР ПОДПИСКИ (ИСПРАВЛЕННЫЙ) ---
final isFollowingProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  profileUserId,
) async {
  // Оборачиваем ВЕСЬ блок в try-catch для отлова ошибок инициализации
  try {
    print('🔍 [FollowDebug] Checking follow status for target: $profileUserId');

    final prefs = await SharedPreferences.getInstance();
    final localUserId = prefs.getString('user_id');

    final currentUserId = localUserId;
    print('🔍 [FollowDebug] Current User ID: $currentUserId');

    if (currentUserId == null) {
      print('ℹ️ [FollowDebug] No user logged in -> False');
      return false;
    }

    if (currentUserId == profileUserId) {
      print('ℹ️ [FollowDebug] Viewing own profile -> False');
      return false;
    }

    final apiService = ref.watch(apiServiceProvider);
    print('🚀 [FollowDebug] Sending API request...');

    final response = await apiService.get(
      'profiles/$profileUserId/is-following',
    );

    print('✅ [FollowDebug] API Response: $response');
    return response['isFollowing'] as bool? ?? false;
  } catch (e, stack) {
    // Логируем реальную причину ошибки
    print('❌ [FollowDebug] CRITICAL ERROR: $e');
    print(stack);
    // Пробрасываем ошибку дальше, чтобы UI увидел состояние error
    // Если хочешь "скрыть" ошибку и просто показать кнопку "Подписаться", замени rethrow на return false;
    rethrow;
  }
});

final userAchievementsProvider = FutureProvider.autoDispose
    .family<List<UserAchievement>, String>((ref, userId) async {
      try {
        final apiService = ref.watch(apiServiceProvider);
        final response = await apiService.get('profiles/$userId/achievements');

        return (response as List).map((item) {
          return UserAchievement(
            achievement: Achievement(
              id: item['id'],
              name: item['name'],
              description: item['description'],
              iconName: item['icon_name'],
              xpReward: (item['xp_reward'] as num?)?.toInt() ?? 0,
              isSecret: item['is_secret'] as bool? ?? false,
              category: item['category'] as String? ?? 'common',
            ),
            achievedAt: DateTime.parse(item['achieved_at'] as String),
          );
        }).toList();
      } catch (e) {
        print('❌ [UserAchievements] Error: $e');
        return [];
      }
    });

final marketQuestProvider = FutureProvider.autoDispose
    .family<MarketQuest, String>((ref, questId) async {
      try {
        final apiService = ref.watch(apiServiceProvider);
        final response = await apiService.get('quests/$questId');
        return MarketQuest.fromJson(response);
      } catch (e) {
        print('❌ [MarketQuest] Error: $e');
        rethrow;
      }
    });
