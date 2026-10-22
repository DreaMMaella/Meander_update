import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/models/notification_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final userNotificationsProvider = FutureProvider.autoDispose
    .family<List<AppNotification>, bool>((ref, archived) async {
  try {
    final apiService = ref.watch(apiServiceProvider);
    final response = await apiService.get(
      'notifications?archived=${archived ? 'true' : 'false'}',
    );

    if (response is! List) return [];

    return response.map((json) {
      try {
        return AppNotification.fromJson(json);
      } catch (e) {
        print('⚠️ [Notifications] Parse error: $e');
        rethrow;
      }
    }).toList();
  } catch (e) {
    print('❌ [Notifications] Error: $e');
    rethrow;
  }
});

final unreadNotificationsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final apiService = ref.watch(apiServiceProvider);
    final response = await apiService.get('notifications/unread-count');
    return int.tryParse(response['count'].toString()) ?? 0;
  } catch (e) {
    print('❌ [Notifications] Unread count error: $e');
    return 0;
  }
});
