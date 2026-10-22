import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/wall/widgets/post_card.dart';
import 'package:canvas_app/models/wall_post_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Лайк поста гость нажимал так же, как залогиненный, — и получал «Не удалось
/// изменить лайк» про отметку, которую сервер у него не принимал. Сердечко на
/// карточке обязано объяснять про аккаунт, а не врать про сеть.
/// Считает обращения к серверу: гостю их быть не должно.
class _CountingApi extends ApiService {
  int likeCalls = 0;

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    if (endpoint.endsWith('/like')) {
      likeCalls++;
      return {'liked': true};
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    return <String, dynamic>{};
  }
}

void main() {
  WallPost post() => WallPost(
    id: '11111111-1111-1111-1111-111111111111',
    authorId: '22222222-2222-2222-2222-222222222222',
    authorName: 'Лена',
    content: 'Прошёл замок без ключа.',
    likesCount: 0,
    commentsCount: 0,
    viewsCount: 0,
    isLikedByViewer: false,
    createdAt: DateTime(2026, 10, 3, 12),
  );

  Future<_CountingApi> pumpCard(WidgetTester tester) async {
    final api = _CountingApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: [PostCard(post: post())]),
          ),
        ),
      ),
    );
    await tester.pump();
    return api;
  }

  Future<void> tapHeart(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('гостю лайк объясняет про аккаунт и не трогает сервер', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = await pumpCard(tester);

    await tapHeart(tester);

    expect(find.text('Нужен аккаунт'), findsOneWidget);
    expect(find.textContaining('анонимных отметок'), findsOneWidget);
    expect(api.likeCalls, 0);
    // Без сессии не должно быть и rollback-плашки про «не удалось».
    expect(find.text('Не удалось изменить лайк'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('с сессией лайк уходит на сервер без окна', (tester) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'token-1'});
    final api = await pumpCard(tester);

    await tapHeart(tester);

    expect(find.text('Нужен аккаунт'), findsNothing);
    expect(api.likeCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });
}
