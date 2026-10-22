import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/community/screens/post_comments_screen.dart';
import 'package:canvas_app/models/wall_comment_model.dart';
import 'package:canvas_app/models/wall_post_model.dart';
import 'package:canvas_app/providers/wall_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Считает обращения к серверу: гостю их быть не должно.
class _CallLog {
  int addCommentCalls = 0;
  int commentLikeCalls = 0;
}

class _RecordingApi extends ApiService {
  _RecordingApi(this._log);

  final _CallLog _log;

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    if (endpoint.endsWith('/comments')) _log.addCommentCalls++;
    if (endpoint.endsWith('/like')) _log.commentLikeCalls++;
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

/// Гость мог набрать комментарий целиком, нажать отправку и получить сырой
/// «Ошибка: Unauthorized: {…}» — текст терялся вместе с ним. Теперь сессия
/// проверяется до отправки, и напечатанное остаётся в поле.
void main() {
  const postId = '11111111-1111-1111-1111-111111111111';

  WallPost post() => WallPost(
    id: postId,
    authorId: '22222222-2222-2222-2222-222222222222',
    authorName: 'Лена',
    content: 'Прошёл замок без ключа.',
    likesCount: 0,
    commentsCount: 0,
    viewsCount: 0,
    isLikedByViewer: false,
    createdAt: DateTime(2026, 10, 3, 12),
  );

  WallComment comment() => WallComment(
    id: '33333333-3333-3333-3333-333333333333',
    postId: postId,
    userId: '22222222-2222-2222-2222-222222222222',
    userName: 'Лена',
    content: 'Спасибо, прохожу!',
    likesCount: 0,
    isLikedByViewer: false,
    createdAt: DateTime(2026, 10, 3, 13),
  );

  final log = _CallLog();
  final api = _RecordingApi(log);

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(api),
          wallPostCommentsProvider(postId).overrideWith((_) => [comment()]),
        ],
        child: MaterialApp(home: PostCommentsScreen(post: post())),
      ),
    );
    await tester.pump();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'Отличный квест');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('гостю отправка комментария объясняет про аккаунт', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(tester);

    await send(tester);

    expect(find.text('Нужен аккаунт'), findsOneWidget);
    expect(find.textContaining('модерация должна знать'), findsOneWidget);
    expect(log.addCommentCalls, 0);
    // Обещание из текста окна: напечатанное не выбрасывается.
    expect(find.text('Отличный квест'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('с сессией комментарий уходит на сервер без окна', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'token-1'});
    await pumpScreen(tester);

    await send(tester);

    expect(find.text('Нужен аккаунт'), findsNothing);
    expect(log.addCommentCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  /// Сердечко комментария: провайдер ошибку глотает, и гость видел только
  /// отыгравшую анимацию — без всякого объяснения.
  testWidgets('гостю лайк комментария объясняет про аккаунт', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(tester);

    // Сердечек на экране две (статистика поста и комментарий): тап по
    // комментарию — последнее в дереве.
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Нужен аккаунт'), findsOneWidget);
    expect(find.textContaining('только автор с аккаунтом'), findsOneWidget);
    expect(log.commentLikeCalls, 0);

    await tester.pumpWidget(const SizedBox());
  });
}
