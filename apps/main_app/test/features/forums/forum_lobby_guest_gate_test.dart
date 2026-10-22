import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/forums/screens/forum_lobby_screen.dart';
import 'package:canvas_app/features/forums/screens/forum_topic_composer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Лобби форума гостю предлагало ровно те же действия, что и участнику:
/// «Вступить», сердечко у топика и FAB «Обсуждение». Всё это упиралось в 401,
/// причём редактор топика открывался и позволял написать целый текст впустую.
class _LobbyApi extends ApiService {
  int joinCalls = 0;
  int likeCalls = 0;

  Map<String, dynamic> get forum => {
    'id': 'forum-1',
    'slug': 'games',
    'name': 'Игры',
    'description': 'Обо всём игровом',
    'kind': 'user',
    'creator_id': 'user-1',
    'is_restricted': false,
    'member_count': 12,
    'topics_count': 1,
    'joined': false,
    'banned': false,
  };

  Map<String, dynamic> get topic => {
    'id': 'post-1',
    'title': 'Что играли на выходных?',
    'content': 'Рассказывайте',
    'author_id': 'user-7',
    'author_name': 'Витя',
    'likes_count': 3,
    'comments_count': 4,
    'is_liked_by_viewer': false,
    'created_at': '2026-09-21T08:00:00.000Z',
    'media_urls': const <String>[],
  };

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    if (endpoint == 'api/forums/games') {
      return {'forum': forum, 'mods': const []};
    }
    if (endpoint == 'api/forums/games/posts') {
      return {'forum_id': 'forum-1', 'slug': 'games', 'topics': [topic]};
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    if (endpoint.endsWith('/join')) joinCalls++;
    if (endpoint.endsWith('/like')) likeCalls++;
    return <String, dynamic>{'liked': true};
  }
}

void main() {
  Future<_LobbyApi> openLobby(WidgetTester tester) async {
    final api = _LobbyApi();
    tester.view.physicalSize = const Size(1260, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(api)],
        child: const MaterialApp(home: ForumLobbyScreen(slug: 'games')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    return api;
  }

  Future<void> dismissGate(WidgetTester tester) async {
    expect(find.text('Нужен аккаунт'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('гостю FAB «Обсуждение» не открывает редактор топика', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await openLobby(tester);

    await tester.tap(find.text('Обсуждение'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('Топики обсуждают авторы с аккаунтом'),
      findsOneWidget,
    );
    expect(find.byType(ForumTopicComposerScreen), findsNothing);
  });

  testWidgets('гостю «Вступить» объясняет про аккаунт и не пишет на сервер', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = await openLobby(tester);

    await tester.tap(find.text('Вступить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await dismissGate(tester);
    expect(api.joinCalls, 0);
  });

  testWidgets('гостю лайк топика объясняет про аккаунт', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = await openLobby(tester);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await dismissGate(tester);
    expect(api.likeCalls, 0);
  });

  testWidgets('с сессией вступление уходит на сервер без окна', (tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'token-1'});
    final api = await openLobby(tester);

    await tester.tap(find.text('Вступить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Нужен аккаунт'), findsNothing);
    expect(api.joinCalls, 1);
  });
}
