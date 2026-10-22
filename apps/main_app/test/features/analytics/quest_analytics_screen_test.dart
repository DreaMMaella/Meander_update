import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/analytics/models/quest_analytics_model.dart';
import 'package:canvas_app/features/analytics/screens/quest_analytics_screen.dart';

/// Экран обязан показывать ровно то, что посчитал сервер. Проверяем два
/// опасных места: строки вместо чисел из `COUNT`/`BIGINT` и порядок оценок в
/// гистограмме, где сервер не присылает пустые достоинства.
class _FakeApi extends ApiService {
  _FakeApi(this.responses);

  /// Ответы по порядку: первый запрос — одно, второй после смены окна — другое.
  final List<dynamic> responses;
  final List<String> gets = [];
  final List<String?> daysRequested = [];

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    gets.add(endpoint);
    daysRequested.add(queryParams?['days']);
    final index = gets.length - 1;
    final response = responses[index.clamp(0, responses.length - 1)];
    if (response is Exception) throw response;
    return response;
  }
}

Map<String, dynamic> _day({
  required String day,
  int views = 0,
  int viewers = 0,
  int downloads = 0,
  int likes = 0,
  int dislikes = 0,
  int ratings = 0,
  double? ratingAvg,
  int reviews = 0,
  int players = 0,
  int playtimeSeconds = 0,
}) => {
  'day': day,
  'views': '$views',
  'viewers': '$viewers',
  'downloads': '$downloads',
  'likes': '$likes',
  'dislikes': '$dislikes',
  'ratings': '$ratings',
  'rating_avg': ratingAvg,
  'reviews': '$reviews',
  'players': '$players',
  'playtime_seconds': '$playtimeSeconds',
};

Map<String, dynamic> _window({
  int views = 0,
  int viewers = 0,
  int downloads = 0,
  int downloaders = 0,
  int likes = 0,
  int dislikes = 0,
  int ratings = 0,
  double ratingAvg = 0,
  int reviews = 0,
  int players = 0,
  int playtimeSeconds = 0,
}) => {
  'views': '$views',
  'viewers': '$viewers',
  'downloads': '$downloads',
  'downloaders': '$downloaders',
  'likes': '$likes',
  'dislikes': '$dislikes',
  'ratings': '$ratings',
  'rating_avg': '$ratingAvg',
  'reviews': '$reviews',
  'players': '$players',
  'playtime_seconds': '$playtimeSeconds',
};

/// Пустой квест: ни просмотров за всё время, ни скачиваний, ни отзывов.
Map<String, dynamic> _blankLifetime() => {
  'views': '0',
  'viewers': '0',
  'plays_total_seconds': '0',
  'players': '0',
  'reviews': '0',
  'reviews_approved': '0',
  'reviews_answered': '0',
  'last_viewed_day': null,
  'last_downloaded_at': null,
  'last_played_at': null,
};

Map<String, dynamic> _payload({
  int days = 7,
  List<Map<String, dynamic>>? series,
  Map<String, dynamic>? window,
  Map<String, dynamic>? previous,
  Map<String, dynamic>? lifetime,
  List<Map<String, dynamic>>? histogram,
  int downloadsCount = 37,
}) => {
  'quest': {
    'id': 'q1',
    'title': 'Тихая комната',
    'status': 'published',
    'created_at': '2026-09-01T10:00:00.000Z',
    'downloads_count': '$downloadsCount',
    'like_count': '25',
    'dislike_count': '4',
  },
  'days': days,
  'from': '2026-09-17',
  'to': '2026-09-23',
  'series':
      series ??
      [
        _day(day: '2026-09-22', views: 40, viewers: 30, downloads: 12),
        _day(
          day: '2026-09-23',
          views: 60,
          viewers: 41,
          downloads: 18,
          likes: 9,
          dislikes: 1,
          ratings: 7,
          ratingAvg: 4.4,
          reviews: 2,
          players: 14,
          playtimeSeconds: 9000,
        ),
      ],
  'window':
      window ??
      _window(
        views: 100,
        viewers: 60,
        downloads: 30,
        downloaders: 27,
        likes: 9,
        dislikes: 1,
        ratings: 7,
        ratingAvg: 4.4,
        reviews: 2,
        players: 14,
        playtimeSeconds: 9000,
      ),
  'previous':
      previous ??
      _window(
        views: 40,
        viewers: 30,
        downloads: 12,
        downloaders: 11,
        likes: 3,
        dislikes: 1,
        ratings: 2,
        ratingAvg: 3.5,
        reviews: 0,
        players: 5,
        playtimeSeconds: 2000,
      ),
  'lifetime':
      lifetime ??
      {
        'views': '4321',
        'viewers': '1200',
        'plays_total_seconds': '600000',
        'players': '210',
        'reviews': '44',
        'reviews_approved': '40',
        'reviews_answered': '20',
        'last_viewed_day': '2026-09-23',
        'last_downloaded_at': '2026-09-23T07:00:00.000Z',
        'last_played_at': '2026-09-23T08:30:00.000Z',
      },
  'rating_histogram':
      histogram ??
      [
        {'rating': 5, 'count': 30},
        {'rating': 4, 'count': 12},
        {'rating': 3, 'count': 5},
        {'rating': 2, 'count': 1},
        {'rating': 1, 'count': 2},
      ],
};

Future<_FakeApi> _pump(
  WidgetTester tester,
  List<dynamic> responses, {
  Size size = const Size(1000, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = _FakeApi(responses);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiServiceProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: QuestAnalyticsScreen(
            questId: 'q1',
            title: 'Тихая комната',
            days: 7,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  group('модель', () {
    test('считает числа из строк, которые отдаёт node-postgres', () {
      final data = QuestAnalytics.fromJson(_payload());
      expect(data.window.views, 100);
      expect(data.lifetime.views, 4321);
      expect(data.lifetimeDownloads, 37);
      expect(data.window.ratingAvg, closeTo(4.4, 0.001));
      expect(data.series.length, 2);
    });

    test('дельта — текущее окно минус предыдущее того же размера', () {
      final data = QuestAnalytics.fromJson(_payload());
      expect(data.deltaViews(), 60);
      expect(data.deltaDownloads(), 18);
      expect(data.deltaPlaytime(), 7000);
      expect(data.deltaReviews(), 2);
    });

    test('гистограмма стоит по оценкам, а не по порядку строк ответа', () {
      final data = QuestAnalytics.fromJson(
        _payload(
          histogram: [
            {'rating': 1, 'count': 2},
            {'rating': 5, 'count': 30},
          ],
        ),
      );
      expect(data.histogram, [30, 0, 0, 0, 2]);
    });

    test('воронка не врёт, когда знаменателя нет', () {
      final empty = QuestAnalyticsWindow.fromJson(null);
      expect(empty.downloadRate, isNull);
      expect(empty.playRate, isNull);
      expect(empty.positiveShare, isNull);

      // Скачали больше, чем просмотрели: просмотры начали считать позже.
      final odd = QuestAnalyticsWindow.fromJson(
        _window(views: 10, downloads: 40, players: 60, likes: 5, dislikes: 5),
      );
      expect(odd.downloadRate, 1.0);
      expect(odd.playRate, 1.0);
      expect(odd.positiveShare, 0.5);
    });

    test('квест без следов активности — isEmpty, а не нехватка полей', () {
      final data = QuestAnalytics.fromJson(
        _payload(
          series: const [],
          window: _window(),
          previous: _window(),
          lifetime: _blankLifetime(),
          histogram: const [],
          downloadsCount: 0,
        ),
      );
      expect(data.isEmpty, isTrue);
      expect(data.histogram, [0, 0, 0, 0, 0]);
      expect(data.series, isEmpty);
    });
  });

  testWidgets('просит статистику у сервера и показывает окна', (tester) async {
    final api = await _pump(tester, [_payload()]);
    expect(api.gets, ['quests/q1/analytics']);
    expect(api.daysRequested, ['7']);

    expect(find.text('Тихая комната'), findsOneWidget);
    expect(find.text('7 дн'), findsOneWidget);
    expect(find.text('90 дн'), findsOneWidget);
    for (final label in [
      'Просмотры',
      'Скачивания',
      'Игроки',
      'Время в квесте',
      'Лайки',
      'Отзывы',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('на телефоне сетка не переполняется', (tester) async {
    // Любой RenderFlex overflow валит тест сам — здесь важно только то, что
    // два KPI в ряд живут и на 390 логических пикселях.
    await _pump(tester, [_payload()], size: const Size(390, 844));
    expect(find.text('Просмотры'), findsOneWidget);
    expect(find.text('Путь игрока за окно'), findsOneWidget);
  });

  testWidgets('показывает графики, воронку, оценки и итоги', (tester) async {
    await _pump(tester, [_payload()]);

    for (final title in [
      'Просмотры по дням',
      'Скачивания по дням',
      'Голоса по дням',
      'Время игры по дням',
      'Игроки по дням',
      'Путь игрока за окно',
      'Оценки',
      'За всё время',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Пока никто не заходил'), findsNothing);
    // 9000 секунд на 14 игроков = 643 с: средняя сессия — текстом, а не только
    // столбиком, иначе автор сверяет экран с ощущением на глаз.
    expect(find.textContaining('Средняя сессия: 10 мин.'), findsOneWidget);
    expect(find.textContaining('из 44 одобрено'), findsOneWidget);
  });

  testWidgets('смена окна переспрашивает сервер с новым days', (tester) async {
    final api = await _pump(tester, [_payload(), _payload()]);
    await tester.tap(find.text('30 дн'));
    await tester.pumpAndSettle();

    expect(api.gets.length, 2);
    expect(api.daysRequested, ['7', '30']);
  });

  testWidgets('квест без аудитории говорит об этом прямо', (tester) async {
    await _pump(tester, [
      _payload(
        series: const [],
        window: _window(),
        previous: _window(),
        lifetime: _blankLifetime(),
        histogram: const [],
        downloadsCount: 0,
      ),
    ]);
    expect(find.text('Пока никто не заходил'), findsOneWidget);
    // Пусто — это не «нет экранов»: графики остаются с нулевыми колонками.
    expect(find.text('Просмотры по дням'), findsOneWidget);
  });

  testWidgets('сервер отказал — экран не притворяется нулём', (tester) async {
    await _pump(tester, [Exception('HTTP 403: Статистику видит только автор')]);
    expect(find.text('Статистика не загрузилась'), findsOneWidget);
    expect(find.textContaining('HTTP 403'), findsOneWidget);
    expect(find.text('Просмотры по дням'), findsNothing);
  });

  /// То же для экрана одного квеста: колонка метрик на узком телефоне
  /// принимает числа до девяти знаков, и плашка сравнения периодов живёт
  /// рядом с заголовком.
  testWidgets('узкий телефон с большими числами не переполняется', (tester) async {
    await _pump(
      tester,
      [
        _payload(
          window: _window(
            views: 999999999,
            viewers: 888888888,
            downloads: 777777777,
            downloaders: 666666666,
            likes: 555555555,
            dislikes: 444444444,
            ratings: 333333333,
            ratingAvg: 4.7,
            reviews: 222222222,
            players: 111111111,
            playtimeSeconds: 3599999,
          ),
          downloadsCount: 999999999,
        ),
      ],
      size: const Size(360, 900),
    );

    expect(tester.takeException(), isNull);
  });
}
