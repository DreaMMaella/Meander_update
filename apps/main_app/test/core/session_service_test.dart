import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/core/services/session_service.dart';
import 'package:canvas_app/features/market/providers/recommendations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пишет, что именно ушло на сервер при выходе, и не трогает сеть.
class _RecordingApi extends ApiService {
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    calls.add({'endpoint': endpoint, 'body': body});
    return const {'success': true};
  }
}

void main() {
  Future<(_RecordingApi, ProviderContainer, BuildContext)> pumpSession(
    WidgetTester tester,
    Map<String, Object> stored,
  ) async {
    SharedPreferences.setMockInitialValues(stored);
    final api = _RecordingApi();
    late BuildContext context;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    return (api, ProviderScope.containerOf(context, listen: false), context);
  }

  const accountPrefs = {
    'jwt_token': 'token-A',
    'user_id': 'user-A',
    'fcm_token': 'device-token',
    'recently_viewed_quests_v1': ['quest-A'],
    // Device-настройка: её трогать нельзя.
    'editor_tabs_enabled': true,
  };

  testWidgets('выход стирает сессию, но не настройки устройства', (
    tester,
  ) async {
    final (api, _, context) = await pumpSession(tester, accountPrefs);

    await endSession(context: context);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jwt_token'), isNull);
    expect(prefs.getString('user_id'), isNull);
    expect(prefs.getString('fcm_token'), isNull);
    expect(prefs.getStringList('recently_viewed_quests_v1'), isNull);
    expect(prefs.getBool('editor_tabs_enabled'), isTrue);
    expect(api.calls, hasLength(1));
    expect(api.calls.single['endpoint'], 'profiles/fcm-token');
    expect(api.calls.single['body']!['token'], isNull);
  });

  testWidgets('выход не дёргает сервер мёртвым токеном', (tester) async {
    final (api, _, context) = await pumpSession(tester, accountPrefs);

    await endSession(context: context, notifyServer: false);

    expect(api.calls, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jwt_token'), isNull);
  });

  testWidgets('кэш аккаунта не доезжает следующему вошедшему', (tester) async {
    final (_, container, context) = await pumpSession(tester, accountPrefs);

    // Держим провайдер живым, как это делает открытый экран, и наполняем
    // его данными пользователя A.
    container.listen(recentlyViewedQuestsProvider, (_, _) {});
    await container.read(recentlyViewedQuestsProvider.notifier).push('quest-A');
    expect(container.read(recentlyViewedQuestsProvider), ['quest-A']);

    await endSession(context: context);
    await tester.pumpAndSettle();

    expect(container.read(recentlyViewedQuestsProvider), isEmpty);
  });
}
