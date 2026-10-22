// Оба редактора проверяют одно и то же правило глазами: кнопка обязана
// проснуться, когда человек написал текст. Раньше условие доступности
// считывалось из контроллера прямо в build, а перерисовки на набор не было,
// поэтому «Опубликовать» и «Создать» оставались серыми при заполненных полях —
// выглядело как сломанная публикация и сломанное создание сообщества.

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/forums/screens/forum_topic_composer_screen.dart';
import 'package:canvas_app/features/forums/screens/forums_catalog_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  final List<(String, Map<String, dynamic>?)> writes = [];

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    if (endpoint == 'api/forums') {
      return {
        'forums': [
          {
            'id': 'forum-1',
            'slug': 'games',
            'name': 'Игры',
            'kind': 'user',
            'creator_id': 'user-1',
            'creator_name': 'Аня',
            'is_restricted': false,
            'member_count': 12,
            'topics_count': 8,
            'joined': false,
          },
        ],
      };
    }
    if (endpoint == 'api/forums/games') {
      return {
        'forum': {
          'id': 'forum-1',
          'slug': 'games',
          'name': 'Игры',
          'kind': 'user',
          'creator_id': 'user-1',
          'is_restricted': false,
          'member_count': 12,
          'topics_count': 0,
          'joined': true,
        },
        'mods': <Map<String, dynamic>>[],
      };
    }
    if (endpoint == 'api/forums/games/posts') {
      return {'topics': <Map<String, dynamic>>[]};
    }
    throw Exception('неизвестный эндпоинт $endpoint');
  }

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    writes.add((endpoint, body));
    if (endpoint == 'api/forums') return {'id': 'forum-2', 'slug': 'goblins'};
    if (endpoint == 'api/forums/games/posts') {
      return {'id': 'post-9', 'forum_id': 'forum-1'};
    }
    throw Exception('неизвестный эндпоинт POST $endpoint');
  }
}

/// Экран всегда лежит под тем же `ProviderScope`, что и диалог: `showAppDialog`
/// строит контент над ним, и переопределение apiServiceProvider должно быть
/// видно обоим, иначе диалог уйдёт на настоящий бэк.
Future<void> _pump(WidgetTester tester, Widget screen, _FakeApi api) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiServiceProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

void main() {
  testWidgets('редактор топика: «Опубликовать» активна после заполнения полей', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, const ForumTopicComposerScreen(slug: 'games'), api);

    expect(
      _button(tester, 'Опубликовать').onPressed,
      isNull,
      reason: 'поля пустые',
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Заголовок'),
      'Всем привет',
    );
    await tester.pump();
    expect(
      _button(tester, 'Опубликовать').onPressed,
      isNull,
      reason: 'одного заголовка мало: сервер требует тело',
    );

    await tester.enterText(find.byType(TextField).last, 'Как дела?');
    await tester.pump();
    expect(_button(tester, 'Опубликовать').onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final posted = api.writes.firstWhere(
      (w) => w.$1 == 'api/forums/games/posts',
    );
    expect(posted.$2?['title'], 'Всем привет');
    expect(posted.$2?['content'], 'Как дела?');
  });

  testWidgets('создание сообщества: «Создать» активна после названия', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'user_id': 'user-1'});
    final api = _FakeApi();
    await _pump(tester, const ForumsCatalogScreen(), api);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(_button(tester, 'Создать').onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Название'),
      'Гоблины',
    );
    await tester.pump();
    expect(_button(tester, 'Создать').onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final created = api.writes.firstWhere((w) => w.$1 == 'api/forums');
    expect(created.$2?['name'], 'Гоблины');
  });
}
