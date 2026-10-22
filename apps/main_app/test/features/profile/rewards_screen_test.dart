import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';
import 'package:canvas_app/features/profile/screens/rewards_screen.dart';

/// Награды считает сервер, от клиента требуется честно показать прогресс и
/// не соврать про то, что уже полученное можно надеть.
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

Map<String, dynamic> _rule({
  required String id,
  required String metric,
  required Object threshold,
  required Object current,
  List<String> cosmetics = const ['neon_pulse'],
  bool done = false,
  String? grantedAt,
  String title = 'Неон-пульс за неделю',
  String hint = 'Семь дней заходить подряд.',
}) => {
  'id': id,
  'metric': metric,
  'threshold': threshold,
  'title': title,
  'hint': hint,
  'cosmetics': cosmetics,
  'current': current,
  'done': done,
  'granted_at': grantedAt,
};

Future<void> _pump(WidgetTester tester, dynamic response) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiServiceProvider.overrideWithValue(_FakeApi(response))],
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: RewardsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// SnackBar живёт 5 с и сидит на таймере — иначе тест ругается на висячий
/// таймер в конце.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('недобранная награда: прогресс, остаток и честный значок', (
    tester,
  ) async {
    await _pump(tester, {
      'granted_now': <dynamic>[],
      'rules': [
        _rule(id: 'streak_7', metric: 'streak', threshold: 7, current: 3),
      ],
    });

    expect(find.text('Дни подряд'), findsOneWidget);
    expect(find.text('0 из 1'), findsOneWidget);
    expect(find.text('3 из 7 · осталось 4'), findsOneWidget);
    expect(find.text('Растёт'), findsOneWidget);
    expect(find.text('Ваша'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('выданная награда больше не требует прогресса', (tester) async {
    await _pump(tester, {
      'granted_now': <dynamic>[],
      'rules': [
        _rule(
          id: 'streak_7',
          metric: 'streak',
          threshold: 7,
          current: 7,
          done: true,
          grantedAt: '2026-09-10T08:00:00Z',
        ),
      ],
    });

    expect(find.text('Ваша'), findsOneWidget);
    expect(find.textContaining('осталось'), findsNothing);
    expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);
    expect(find.text('1 из 1'), findsOneWidget);
  });

  testWidgets('числа из postgres приходят строками — экран не падает', (
    tester,
  ) async {
    await _pump(tester, {
      'granted_now': <dynamic>[],
      'rules': [
        _rule(
          id: 'downloads_15',
          metric: 'downloads',
          threshold: '15',
          current: '12',
          title: 'Полка',
        ),
      ],
    });

    expect(find.text('Скачивания'), findsOneWidget);
    expect(find.text('12 из 15 · осталось 3'), findsOneWidget);
  });

  testWidgets('только что выданное показывается снекбаром', (tester) async {
    await _pump(tester, {
      'granted_now': ['reviews_5'],
      'rules': [
        _rule(
          id: 'reviews_5',
          metric: 'reviews',
          threshold: 5,
          current: 5,
          title: 'Голос',
          done: true,
          grantedAt: '2026-09-24T08:00:00Z',
        ),
      ],
    });

    expect(find.textContaining('Награда ваша: Голос'), findsOneWidget);
    expect(find.textContaining('Надеть — в «Оформлении профиля»'), findsOneWidget);

    await _settle(tester);
    expect(find.textContaining('Награда ваша'), findsNothing);
  });

  testWidgets('id из более нового каталога молча пропускаются', (
    tester,
  ) async {
    await _pump(tester, {
      'granted_now': <dynamic>[],
      'rules': [
        _rule(
          id: 'streak_7',
          metric: 'streak',
          threshold: 7,
          current: 7,
          cosmetics: ['neon_pulse', 'cosmetic_from_the_future'],
          done: true,
          grantedAt: '2026-09-24T08:00:00Z',
        ),
      ],
    });

    expect(find.text('Неон-пульс'), findsOneWidget);
    expect(find.text('Редкое'), findsOneWidget);
    expect(find.byType(CosmeticPreview), findsOneWidget);
  });

  testWidgets('пустой ответ объясняется недостающим бэкендом, а не «нет наград»', (
    tester,
  ) async {
    await _pump(tester, {
      'granted_now': <dynamic>[],
      'rules': <dynamic>[],
    });

    expect(find.textContaining('Список наград пока пуст'), findsOneWidget);
    expect(find.textContaining('сервер начнёт их считать'), findsOneWidget);
  });
}
