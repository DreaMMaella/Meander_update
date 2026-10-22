import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/screens/profile_screen.dart';

/// Гость видел на чужом профиле живую кнопку «Подписаться», тап по ней молчал,
/// а с подписанным токеном тап уходит в POST /follow. Проверяем обе ветки.
class _FakeApi extends ApiService {
  int followCalls = 0;

  static const _profile = {
    'id': 'u-author',
    'full_name': 'Автор',
    'created_at': '2026-01-01T00:00:00Z',
    'followers_count': 3,
    'following_count': 2,
  };

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    if (endpoint == 'profiles/u-author/is-following') {
      return const {'isFollowing': false};
    }
    if (endpoint == 'profiles/u-author') return _profile;
    if (endpoint == 'profiles/author-notifs-settings') {
      return const {'mode': 'all', 'exceptions': <String>[]};
    }
    return const [];
  }

  @override
  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    if (endpoint == 'profiles/u-author/follow') {
      followCalls++;
      return const {'ok': true, 'isFollowing': true};
    }
    return const {'ok': true};
  }
}

Future<_FakeApi> _pumpProfile(WidgetTester tester) async {
  // Шапка на мобильной ширине; высокий экран — чтобы не было overflow.
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = _FakeApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiServiceProvider.overrideWithValue(api)],
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ProfileScreen(userId: 'u-author'),
        ),
      ),
    ),
  );
  // Шиммер шапки крутится бесконечно — pumpAndSettle здесь не дождётся конца.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return api;
}

void main() {
  testWidgets('гость: «Подписаться» объясняет про аккаунт и не пишет на сервер', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = await _pumpProfile(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Подписаться'));
    // Диалог живёт в оверлее: без прокрутки таймера он не появится.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Нужен аккаунт'), findsOneWidget);
    expect(find.textContaining('Подписки держатся на аккаунте'), findsOneWidget);
    expect(api.followCalls, 0);
  });

  testWidgets('с аккаунтом: тап доходит до POST /follow', (tester) async {
    SharedPreferences.setMockInitialValues({
      'jwt_token': 'token-1',
      'user_id': 'u-viewer',
    });
    final api = await _pumpProfile(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Подписаться'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.followCalls, 1);
    expect(find.text('Нужен аккаунт'), findsNothing);
  });
}
