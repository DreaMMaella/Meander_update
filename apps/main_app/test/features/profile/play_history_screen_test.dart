import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/screens/play_history_screen.dart';

/// Бэк отдаёт «игровую историю» одним JSON. Подменяем его и следим за двумя
/// вещами: как числа превращаются в читаемое время и что список не врёт про
/// снятые квесты.
class _FakeApi extends ApiService {
  _FakeApi(this.response);

  final dynamic response;
  final List<String> gets = [];

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    gets.add(endpoint);
    return response;
  }
}

Map<String, dynamic> _row({
  required String id,
  required String title,
  required Object seconds,
  Object days = 1,
  String status = 'published',
  String? lastPlayedAt,
}) => {
  'quest_id': id,
  'title': title,
  'seconds': seconds,
  'days': days,
  'status': status,
  'preview_image_url': null,
  'author_id': 'a-1',
  'author_name': 'Автор',
  'author_name_style': null,
  'last_played_at': lastPlayedAt,
};

Future<_FakeApi> _pump(
  WidgetTester tester,
  dynamic response, {
  String? userId,
  String? ownerName,
}) async {
  final api = _FakeApi(response);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiServiceProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: PlayHistoryScreen(userId: userId, ownerName: ownerName),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('сводка и строки: часы, дни и давность захода', (tester) async {
    await _pump(tester, {
      'items': [
        _row(
          id: 'q-1',
          title: 'Тайна чердака',
          seconds: 7384,
          days: 3,
          lastPlayedAt: '2026-09-20T10:00:00Z',
        ),
      ],
      'summary': {'total_seconds': 7384, 'quests_played': 1, 'active_days': 9},
    });

    expect(find.text('2 ч. 3 мин.'), findsNWidgets(2));
    expect(find.text('3 дня'), findsOneWidget);
    expect(find.text('Квестов'), findsOneWidget);
    expect(find.textContaining('Тайна чердака'), findsOneWidget);
    expect(find.text('Автор'), findsOneWidget);
  });

  testWidgets('BIGINT из postgres приходит строкой — не роняет экран', (
    tester,
  ) async {
    await _pump(tester, {
      'items': [
        _row(id: 'q-1', title: 'Долгий квест', seconds: '3600', days: '12'),
      ],
      'summary': {
        'total_seconds': '3600',
        'quests_played': '1',
        'active_days': '12',
      },
    });

    expect(find.text('1 ч.'), findsNWidgets(2));
    expect(find.text('12 дней'), findsOneWidget);
  });

  testWidgets('сортировка по времени меняет порядок местами', (tester) async {
    await _pump(tester, {
      'items': [
        _row(
          id: 'q-1',
          title: 'Недавний',
          seconds: 60,
          lastPlayedAt: '2026-09-23T10:00:00Z',
        ),
        _row(
          id: 'q-2',
          title: 'Долгий',
          seconds: 90000,
          lastPlayedAt: '2026-09-01T10:00:00Z',
        ),
      ],
      'summary': {'total_seconds': 90060, 'quests_played': 2, 'active_days': 5},
    });

    expect(
      tester.getRect(find.text('Недавний')).top,
      lessThan(tester.getRect(find.text('Долгий')).top),
    );

    await tester.tap(find.text('Больше всего'));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('Долгий')).top,
      lessThan(tester.getRect(find.text('Недавний')).top),
    );
  });

  testWidgets('снятый из маркета квест помечен, а не притворяется живым', (
    tester,
  ) async {
    await _pump(tester, {
      'items': [
        _row(id: 'q-1', title: 'Удалённый', seconds: 120, status: 'removed'),
      ],
      'summary': {'total_seconds': 120, 'quests_played': 1, 'active_days': 1},
    });

    expect(find.text('снят с публикации'), findsOneWidget);
  });

  testWidgets('пустая история объясняет, откуда возьмутся строки', (
    tester,
  ) async {
    await _pump(tester, {
      'items': <dynamic>[],
      'summary': {'total_seconds': 0, 'quests_played': 0, 'active_days': 0},
    });

    expect(find.textContaining('которые вы открывали'), findsOneWidget);
  });

  testWidgets('чужую библиотеку тянем по id и подписываем именем владельца', (
    tester,
  ) async {
    final api = await _pump(
      tester,
      {
        'items': [
          _row(id: 'q-1', title: 'Чужой квест', seconds: 600),
        ],
        'summary': {
          'total_seconds': 600,
          'quests_played': 1,
          'active_days': 1,
        },
      },
      userId: 'u-77',
      ownerName: 'Марина',
    );

    expect(api.gets.first, 'profiles/u-77/playhistory');
    // SliverAppBar.large держит заголовок и в свёрнутом, и в раскрытом виде.
    expect(find.text('Марина · игры'), findsWidgets);
    // Пустой чужой профиль не должен обещать, что «здесь появятся квесты,
    // которые вы открывали».
    expect(find.textContaining('которые вы открывали'), findsNothing);
  });

  testWidgets('полоска активности считает дни и показывает лучший день', (
    tester,
  ) async {
    await _pump(tester, {
      'items': [
        _row(id: 'q-1', title: 'Долгий', seconds: 4200),
      ],
      'activity': [
        {'day': '2026-09-20', 'seconds': 600},
        {'day': '2026-09-21', 'seconds': 4200},
      ],
      'summary': {
        'total_seconds': 4800,
        'quests_played': 1,
        'active_days': 2,
        'window_days': 91,
      },
    });

    expect(find.text('2 дня в игре'), findsOneWidget);
    expect(find.textContaining('за 91 день'), findsOneWidget);
    expect(find.textContaining('лучший день — 1 ч.'), findsOneWidget);
  });

  testWidgets('без активности полоски нет — экран не пустой карточкой', (
    tester,
  ) async {
    await _pump(tester, {
      'items': [
        _row(id: 'q-1', title: 'Один квест', seconds: 60),
      ],
      'summary': {'total_seconds': 60, 'quests_played': 1, 'active_days': 1},
    });

    expect(find.textContaining('в игре'), findsNothing);
  });

  /// Вёрстка узкого телефона: самое длинное, что реально отдаёт бэкенд, —
  /// название в две строки, автор, часы «999 ч. 59 мин.» и дни. Строки
  /// фиксированной ширины, поэтому переполнение Row'а видно сразу как
  /// исключение фреймворка.
  testWidgets('узкий телефон: ни одна строка истории не вылезает за край', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, {
      'items': [
        _row(
          id: 'q-1',
          title:
              'Невероятно длинное название квеста, которое не влезает даже в две строки на маленьком экране',
          seconds: 3599940,
          days: 428,
          lastPlayedAt: '2026-09-20T10:00:00Z',
        ),
      ],
      'activity': [
        {'day': '2026-09-20', 'seconds': 3599940},
      ],
      'summary': {
        'total_seconds': 3599940,
        'quests_played': 9999,
        'active_days': 428,
        'window_days': 91,
      },
    });

    // Переполнение Row'а фреймворк сам поднимает как исключение — его ловит
    // нижний expect, печатать нечего.
    expect(tester.takeException(), isNull);
  });
}
