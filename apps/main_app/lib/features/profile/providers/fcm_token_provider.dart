import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/core/services/firebase_messaging_service.dart';

/// Provider to manage FCM device token
final fcmTokenProvider = FutureProvider<String?>((ref) async {
  try {
    // Wait for Firebase initialization before requesting token
    await FirebaseMessagingService().initializationFuture;
    final token = await FirebaseMessaging.instance.getToken();
    return token;
  } catch (e) {
    return null;
  }
});

/// Notifier to sync FCM token to backend
final fcmTokenSyncProvider = FutureProvider<void>((ref) async {
  try {
    final token = await ref.watch(fcmTokenProvider.future);
    if (token == null) return;

    final prefs = await SharedPreferences.getInstance();
    
    // Check if user disabled notifications
    final enabled = prefs.getBool('notifications_enabled') ?? true;
    if (!enabled) return; // Do not sync if disabled

    final storedToken = prefs.getString('fcm_token');

    // Only sync if token changed
    if (storedToken != token) {
      await prefs.setString('fcm_token', token);

      // Send to backend
      final apiService = ref.read(apiServiceProvider);
      await apiService.post('profiles/fcm-token', body: {'token': token});

      debugPrint('✅ [FCM Token] Synced to backend');
    }
  } catch (e) {
    debugPrint('❌ [FCM Token] Sync error: $e');
  }
});
