import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/analytics/models/quest_analytics_model.dart';
import 'package:canvas_app/features/analytics/screens/author_analytics_screen.dart';

/// Сводка и карточка квеста живут на одном серверном правиле. Проверка
/// держит это на замке: экран автора просит свой эндпоинт, а строка квеста
/// ведёт на обычный экран квеста, который уже сам спросит `quests/:id/analytics`.
class _FakeApi extends ApiService {
  _FakeApi(this.byEndpoint);

  final Map<String, dynamic> byEndpoint;
  final List<String> gets = [];
  final List<String?> daysRequested = [];

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    gets.add(endpoint);
    daysRequested.add(queryParams?['days']);
    final response = byEndpoint[endpoint];
    if (response == null) throw Exception('нет данных для $endpoint');
    if (response is Exception) throw response;
    return response;
  }
}

Map<String, dynamic> _window({
  int views = 0,
  int viewers = 0,
  int downloads = 0,
  int players = 0,
  int playtimeSeconds = 0,
  int likes = 0,
}) => {
  'views': '$views',
  'viewers': '$viewers',
  'downloads': '$downloads',
  'downloaders': '$downloads',
  'likes': '$likes',
  'dislikes': '0',
  'ratings': '0',
  'rating_avg': '0',
  'reviews': '0',
  'players': '$players',
  'playtime_seconds': '$playtimeSeconds',
};

Map<String, dynamic> _quest({
  required String id,
  required String title,
  int views = 0,
  int downloads = 0,
  int players = 0,
  int playtimeSeconds = 0,
  int likes = 0,
  String status = 'published',
  double? ratingAvg,
}) => {
  'id': id,
  'title': title,
  'status': status,
  'views': '$views',
  'viewers': '$views',
  'downloads': '$downloads',
  'players': '$players',
  'playtime_seconds': '$playtimeSeconds',
  'likes': '$likes',
  'rating_avg': ratingAvg,
};

Map<String, dynamic> _payload({
  int days = 30,
  int questsTotal = 2,
  int questsPublished = 2,
  Map<String, dynamic>? window,
  Map<String, dynamic>? previous,
  List<Map<String, dynamic>>? series,
  List<Map<String, dynamic>>? quests,
}) => {
  'days': days,
  'from': '2026-09-17',
  'to': '2026-09-23',
  'quests_total': questsTotal,
  'quests_published': questsPublished,
  'window':
      window ??
      _window(
        views: 320,
        viewers: 140,
        downloads: 60,
        players: 24,
        playtimeSeconds: 5400,
        likes: 18,
      ),
  'previous':
      previous ??
      _window(views: 120, downloads: 20, players: 9, playtimeSeconds: 1800),
  'series':
      series ??
      [
        {
          'day': '2026-09-22',
          'views': '150',
          'viewers': '70',
          'downloads': '28',
          'likes': '9',
          'dislikes': '1',
          'ratings': '6',
          'rating_avg': '4.5',
          'reviews': '1',
          'players': '11',
          'playtime_seconds': '2600',
        },
        {
          'day': '2026-09-23',
          'views': '170',
          'viewers': '80',
          'downloads': '32',
          'likes': '9',
          'dislikes': '0',
          'ratings': '5',
          'rating_avg': '4.2',
          'reviews': '2',
          'players': '13',
          'playtime_seconds': '2800',
        },
      ],
  'quests':
      quests ??
      [
        _quest(
          id: 'q1',
          title: 'Тихая комната',
          views: 210,
          downloads: 40,
          players: 16,
          playtimeSeconds: 3600,
          likes: 12,
          ratingAvg: 4.6,
        ),
        _quest(
          id: 'q2',
          title: 'Лестница',
          views: 110,
          downloads: 20,
          players: 8,
          playtimeSeconds: 1800,
          likes: 6,
          status: 'removed',
        ),
      ],
};

Future<_FakeApi> _pump(
  WidgetTester tester,
  Map<String, dynamic> byEndpoint, {
  Size size = const Size(1000, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = _FakeApi(byEndpoint);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiServiceProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AuthorAnalyticsScreen(nick: 'Автор'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  group('модель сводки', () {
    test('числа из строк и дельты окон', () {
      final data = AuthorAnalytics.fromJson(_payload());
      expect(data.window.views, 320);
      expect(data.quests.length, 2);
      expect(data.deltaViews(), 200);
      expect(data.deltaPlaytime(), 3600);
      expect(data.quests.first.ratingAvg, closeTo(4.6, 0.001));
      expect(data.quests.last.ratingAvg, isNull);
    });

    test('пустое окно — isEmpty', () {
      final data = AuthorAnalytics.fromJson(
        _payload(window: _window(), previous: _window(), series: const []),
      );
      expect(data.isEmpty, isTrue);
    });
  });

  testWidgets('просит сводку и показывает квесты сортированными сервером', (
    tester,
  ) async {
    final api = await _pump(tester, {'quests/analytics/author': _payload()});
    expect(api.gets, ['quests/analytics/author']);
    expect(api.daysRequested, ['30']);

    expect(find.text('Автор · 2 публикации'), findsOneWidget);
    expect(find.text('Просмотры по дням'), findsOneWidget);
    expect(find.text('По квестам за окно'), findsOneWidget);
    expect(find.text('Тихая комната'), findsOneWidget);
    expect(find.text('Лестница'), findsOneWidget);
    // Снятый квест помечен значком: он тоже приносит просмотры, и автор
    // должен видеть, какой именно строке нечего показывать в маркете.
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('склонение заголовка по числу публикаций', (tester) async {
    const cases = <(int, String)>[
      (1, '1 публикация'),
      (5, '5 публикаций'),
      (22, '22 публикации'),
    ];
    for (final item in cases) {
      await _pump(tester, {
        'quests/analytics/author': _payload(
          questsTotal: item.$1,
          quests: const [],
        ),
      });
      expect(
        find.text('Автор · ${item.$2}'),
        findsOneWidget,
        reason: '${item.$1}',
      );
    }
  });

  testWidgets('тап по строке квеста открывает статистику этого квеста', (
    tester,
  ) async {
    final api = await _pump(tester, {
      'quests/analytics/author': _payload(),
      'quests/q1/analytics': {
        'quest': {
          'id': 'q1',
          'title': 'Тихая комната',
          'status': 'published',
          'created_at': '2026-09-01T10:00:00.000Z',
          'downloads_count': '40',
          'like_count': '12',
          'dislike_count': '0',
        },
        'days': 30,
        'from': '2026-09-17',
        'to': '2026-09-23',
        'series': const [],
        'window': _window(views: 210, downloads: 40, players: 16),
        'previous': _window(),
        'lifetime': {
          'views': '900',
          'viewers': '300',
          'plays_total_seconds': '7200',
          'players': '60',
          'reviews': '5',
          'reviews_approved': '4',
          'reviews_answered': '2',
          'last_viewed_day': '2026-09-23',
          'last_downloaded_at': null,
          'last_played_at': null,
        },
        'rating_histogram': const [],
      },
    });

    await tester.tap(find.text('Тихая комната'));
    await tester.pumpAndSettle();

    expect(find.text('Просмотры по дням'), findsOneWidget);
    expect(find.text('Путь игрока за окно'), findsOneWidget);
    expect(api.gets, ['quests/analytics/author', 'quests/q1/analytics']);
    // Окно передаётся: сводка на 30 дней → квест тоже на 30.
    expect(api.daysRequested, ['30', '30']);
  });

  testWidgets('пустое окно сказано прямо', (tester) async {
    await _pump(tester, {
      'quests/analytics/author': _payload(
        window: _window(),
        previous: _window(),
        series: const [],
        quests: const [],
      ),
    });
    expect(find.text('За это окно никто не заходил'), findsOneWidget);
    expect(find.text('Публикаций пока нет.'), findsOneWidget);
  });

  testWidgets('ошибка сервера не превращается в нули', (tester) async {
    await _pump(tester, {
      'quests/analytics/author': Exception('HTTP 500: Server error'),
    });
    expect(find.text('Сводка не загрузилась'), findsOneWidget);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(find.text('Просмотры по дням'), findsNothing);
  });

  /// Узкий телефон + максимум чисел и длинное название: строки сводки и
  /// таблицы квестов не должны выезжать за край — переполнение Row'а
  /// прилетает в тест как исключение фреймворка.
  testWidgets('узкий телефон с большими числами не переполняется', (tester) async {
    await _pump(
      tester,
      {
        'quests/analytics/author': _payload(
          questsTotal: 1234567,
          questsPublished: 1234566,
          window: _window(
            views: 999999999,
            viewers: 888888888,
            downloads: 777777777,
            players: 666666666,
            playtimeSeconds: 3599999,
            likes: 555555555,
          ),
          quests: [
            _quest(
              id: 'q1',
              title:
                  'Невероятно длинное название квеста, которое не влезает в строку',
              views: 999999999,
              downloads: 888888888,
              players: 777777777,
              playtimeSeconds: 3599999,
              likes: 666666666,
              ratingAvg: 4.7,
            ),
          ],
        ),
      },
      size: const Size(360, 900),
    );

    expect(tester.takeException(), isNull);
  });
}
