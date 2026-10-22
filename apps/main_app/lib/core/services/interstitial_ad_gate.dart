import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

import 'package:canvas_app/providers/ads_provider.dart';

class InterstitialAdGate {
  static const Duration cooldown = Duration(minutes: 15);
  static const Duration nonChapterCooldown = Duration(minutes: 20);
  static const Duration attemptCooldown = Duration(minutes: 1);
  static const Duration showTimeout = Duration(seconds: 10);
  static const String _prefsLastShownAt = 'interstitial_last_shown_at';

  static bool _isShowing = false;
  static DateTime? _lastAttemptAt;

  static Future<void> markShownNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsLastShownAt,
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Ignore prefs errors.
    }
  }

  static Future<bool> maybeShow({
    required WidgetRef ref,
    required bool isUserInitiated,
    required bool isTesting,
    required bool isOnboarding,
    required bool isChapterTransition,
    required String placementLocation,
    bool force = false,
  }) async {
    if (!isUserInitiated) return false;
    if (isTesting || isOnboarding) return false;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;

    final adsDisabled = await syncAdsDisabledState(ref);
    if (adsDisabled) return false;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastShownRaw = prefs.getString(_prefsLastShownAt);
    final lastShown = lastShownRaw == null
        ? null
        : DateTime.tryParse(lastShownRaw);

    if (!force) {
      if (lastShown == null) {
        await prefs.setString(_prefsLastShownAt, now.toIso8601String());
        return false;
      }

      final minCooldown = isChapterTransition ? cooldown : nonChapterCooldown;
      if (now.difference(lastShown) < minCooldown) return false;
    }

    if (_isShowing) return false;
    if (_lastAttemptAt != null &&
        now.difference(_lastAttemptAt!) < attemptCooldown) {
      return false;
    }

    _lastAttemptAt = now;
    _isShowing = true;
    bool didShow = false;
    final adCompleter = Completer<void>();

    try {
      final adRequest = const AdRequest(adUnitId: 'R-M-13846876-3');
      final loader = InterstitialAdLoader();
      final ad = await loader.loadAd(adRequest: adRequest);
      didShow = true;
      prefs.setString(_prefsLastShownAt, now.toIso8601String());
      ad.setAdEventListener(
        eventListener: InterstitialAdEventListener(
          onAdDismissed: () {
            if (!adCompleter.isCompleted) adCompleter.complete();
          },
          onAdFailedToShow: (_) {
            if (!adCompleter.isCompleted) adCompleter.complete();
          },
        ),
      );
      await ad.show();
      await adCompleter.future.timeout(
        showTimeout,
        onTimeout: () {
          if (!adCompleter.isCompleted) adCompleter.complete();
        },
      );
    } catch (_) {
      // Ignore ad errors.
    } finally {
      _isShowing = false;
    }

    return didShow;
  }
}
