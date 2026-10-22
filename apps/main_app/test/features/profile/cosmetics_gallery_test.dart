import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetics_repository.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetics_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi({this.failWith});

  final Object? failWith;
  final List<Map<String, dynamic>?> posts = [];

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    posts.add(body);
    if (failWith != null) throw failWith!;
    return {'ok': true};
  }
}

Future<_FakeApi> _pumpGallery(
  WidgetTester tester, {
  required MyCosmetics my,
  Object? failWith,
}) async {
  final api = _FakeApi(failWith: failWith);
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        myCosmeticsProvider.overrideWith((ref) async => my),
      ],
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: CosmeticsScreen(userId: 'u-1'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

/// SnackBar живёт 4 с и сидит на таймере — иначе тест ругается на висячий
/// таймер в конце.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('витрина открывается на вкладке обложек и показывает сетку', (
    tester,
  ) async {
    await _pumpGallery(tester, my: const MyCosmetics());

    expect(find.text('Оформление профиля'), findsOneWidget);
    expect(find.text('Обложка'), findsWidgets);
    // Первый тайл всегда «По умолчанию» — им же и снимают предмет.
    expect(find.text('По умолчанию'), findsWidgets);
    expect(find.text('Северное сияние'), findsOneWidget);
  });

  testWidgets('невыданный предмет залочен и не уходит на сервер', (
    tester,
  ) async {
    final api = await _pumpGallery(tester, my: const MyCosmetics());

    await tester.tap(find.text('Северное сияние'));
    await tester.pumpAndSettle();

    expect(api.posts, isEmpty);
    expect(find.textContaining('победу в конкурсах'), findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.textContaining('победу в конкурсах'), findsNothing);
  });

  testWidgets('выданный предмет надеется одним POST в нужный слот', (
    tester,
  ) async {
    final api = await _pumpGallery(
      tester,
      my: const MyCosmetics(granted: {'aurora_drift'}),
    );

    await tester.tap(find.text('Северное сияние'));
    await tester.pumpAndSettle();

    expect(api.posts, hasLength(1));
    final cosmetics = api.posts.single!['cosmetics'] as Map;
    expect(cosmetics[CosmeticSlot.banner.wireName], 'aurora_drift');
    expect(find.text('Надето: Северное сияние'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('надетый слот помечен, «По умолчанию» его снимает', (
    tester,
  ) async {
    final api = await _pumpGallery(
      tester,
      my: const MyCosmetics(
        equipped: EquippedCosmetics(banner: 'aurora_drift'),
        granted: {'aurora_drift'},
      ),
    );

    await tester.tap(find.text('По умолчанию').first);
    await tester.pumpAndSettle();

    final cosmetics = api.posts.single!['cosmetics'] as Map;
    expect(cosmetics[CosmeticSlot.banner.wireName], isNull);
    expect(find.text('Снято'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('отказ сервера показывается текстом из ответа', (tester) async {
    await _pumpGallery(
      tester,
      my: const MyCosmetics(granted: {'aurora_drift'}),
      failWith: Exception('Failed to put data: 403 {"error":"Аккаунт заблокирован"}'),
    );

    await tester.tap(find.text('Северное сияние'));
    await tester.pumpAndSettle();

    expect(find.text('Аккаунт заблокирован'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('переключение вкладок доходит до эффектов', (tester) async {
    await _pumpGallery(tester, my: const MyCosmetics());

    await tester.tap(find.text('Эффект профиля'));
    await tester.pumpAndSettle();

    expect(find.text('Снегопад'), findsOneWidget);
    expect(find.text('Денежный дождь'), findsOneWidget);
  });
}
