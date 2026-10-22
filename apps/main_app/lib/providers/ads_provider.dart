import 'package:canvas_app/core/services/api_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `true` - ads are disabled, `false` - ads are enabled.
final adsDisabledProvider = StateProvider<bool>((ref) => false);

DateTime? _lastAdsStateSyncAt;
const Duration _adsStateSyncTtl = Duration(minutes: 2);

Future<bool> syncAdsDisabledState(WidgetRef ref, {bool force = false}) async {
  final now = DateTime.now();
  if (!force &&
      _lastAdsStateSyncAt != null &&
      now.difference(_lastAdsStateSyncAt!) < _adsStateSyncTtl) {
    return ref.read(adsDisabledProvider);
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) {
      ref.read(adsDisabledProvider.notifier).state = false;
      _lastAdsStateSyncAt = now;
      return false;
    }

    final response = await ref.read(apiServiceProvider).get('profiles/$userId');
    final rawUntil = response['ad_free_until']?.toString();
    final adFreeUntil = rawUntil == null || rawUntil.isEmpty
        ? null
        : DateTime.tryParse(rawUntil);
    final isAdFreeActive =
        adFreeUntil != null && adFreeUntil.toUtc().isAfter(now.toUtc());

    ref.read(adsDisabledProvider.notifier).state = isAdFreeActive;
    _lastAdsStateSyncAt = now;
    return isAdFreeActive;
  } catch (_) {
    return ref.read(adsDisabledProvider);
  }
}
