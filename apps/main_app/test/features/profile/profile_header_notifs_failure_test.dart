import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/screens/profile_screen.dart';

/// #289: на iPhone шапка профиля превращалась в светло-серый прямоугольник
/// (это `RenderErrorBox` Flutter, который в release-сборке рисует пустую
/// плашку вместо упавшего поддерева). Падало поддерево баннера, потому что
/// кнопка «⋮» в шапке читала состояние настроек уведомлений через `.value`,
/// а тот при `AsyncError` бросает сохранённую сетевую ошибку прямо в `build()`.
///
/// Здесь роняется именно `GET /profiles/author-notifs-settings` — 401 у гостя
/// или обрыв сети на холодном старте. Проверяем, что профиль при этом остаётся
/// профилем.
class _FakeApi extends ApiService {
  _FakeApi({this.failNotifs = false, this.failToggle = false});

  final bool failNotifs;
  final bool failToggle;
  int notifsCalls = 0;

  static const _profile = {
    'id': 'u-author',
    'full_name': 'Автор',
    'bio': 'Описание',
    'created_at': '2026-01-01T00:00:00Z',
    'followers_count': 3,
    'following_count': 2,
    'quests_count': 1,
    'likes_count': 4,
  };

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    if (endpoint == 'profiles/author-notifs-settings') {
      notifsCalls++;
      if (failNotifs) throw Exception('Unauthorized: {"error":"no token"}');
      return const {'mode': 'all', 'exceptions': <String>[]};
    }
    if (endpoint.startsWith('profiles/u-author')) {
      if (endpoint.endsWith('is-following')) {
        return const {'isFollowing': false};
      }
      return _profile;
    }
    return const [];
  }

  @override
  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    if (endpoint == 'profiles/author-notifs-settings' && failToggle) {
      throw Exception('Unauthorized');
    }
    return const {'ok': true};
  }
}

Future<void> _pumpProfile(WidgetTester tester, _FakeApi api) async {
  // Геометрия iPhone 13: 390×844 логических пикселя, с безопасными зонами.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

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
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openProfileMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'jwt_token': 'token-1',
      'user_id': 'u-viewer',
    });
  });

  testWidgets('сбой настроек уведомлений: шапка живёт, заглушки ошибок нет', (
    tester,
  ) async {
    await _pumpProfile(tester, _FakeApi(failNotifs: true));

    expect(tester.takeException(), isNull);
    // Шапка отрисована: имя человека и кнопка меню на баннере.
    expect(find.text('Автор'), findsWidgets);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    // Серая плашка RenderErrorBox = поддерево, где сборка бросила.
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('сбой настроек: меню открывается и честно предлагает действие', (
    tester,
  ) async {
    await _pumpProfile(tester, _FakeApi(failNotifs: true));
    await _openProfileMenu(tester);

    expect(find.text('Скопировать ID'), findsOneWidget);
    expect(find.text('Отключить уведомления'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('переключение прошло: снэкбар обещает то, что случилось', (
    tester,
  ) async {
    await _pumpProfile(tester, _FakeApi());
    await _openProfileMenu(tester);
    await tester.tap(find.text('Отключить уведомления'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Уведомления отключены'), findsOneWidget);
  });

  testWidgets('переключение не сохранилось: вранья про успех нет', (
    tester,
  ) async {
    await _pumpProfile(tester, _FakeApi(failToggle: true));
    await _openProfileMenu(tester);
    await tester.tap(find.text('Отключить уведомления'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Уведомления отключены'), findsNothing);
    expect(find.textContaining('нет соединения с сервером'), findsOneWidget);
  });

  testWidgets('гость: запрос не идёт, шапка не падает', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeApi(failNotifs: true);
    await _pumpProfile(tester, api);

    expect(api.notifsCalls, 0);
    expect(find.text('Автор'), findsWidgets);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
