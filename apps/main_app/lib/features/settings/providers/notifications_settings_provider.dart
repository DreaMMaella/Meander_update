import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_app/core/services/api_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationsSettingsNotifier extends StateNotifier<bool> {
  final Ref ref;
  static const String _prefsKey = 'notifications_enabled';

  NotificationsSettingsNotifier(this.ref) : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefsKey) ?? true;
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);

    final api = ref.read(apiServiceProvider);
    if (enabled) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await api.post('profiles/fcm-token', body: {'token': token});
        }
      } catch (_) {}
    } else {
      try {
        await api.post('profiles/fcm-token', body: {'token': null});
      } catch (_) {}
    }
  }
}

final notificationsSettingsProvider =
    StateNotifierProvider<NotificationsSettingsNotifier, bool>((ref) {
      return NotificationsSettingsNotifier(ref);
    });
