// Шит «Пресеты кнопок» открывается и гостю (из «Локальных пресетов», куда
// новичок попадает без аккаунта). Гостя список фильтрует по `loggedIn`, и
// раньше это выглядело как «пресетов нет» — хотя пресеты на устройстве лежат,
// просто публиковать их некому. Проверяем, что шит говорит про вход, а не
// про пустоту.

import 'package:canvas_app/features/hub/widgets/preset_market.dart';
import 'package:canvas_app/models/user_profile_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

QuestPresetEntry _entry(String name) => QuestPresetEntry(
  questId: 'q-1',
  questTitle: 'Тестовый квест',
  presetId: name,
  presetName: name,
  config: ButtonStyleConfig.fromJson({'presetId': name, 'presetName': name}),
  isOwn: true,
);

UserProfile _author() => UserProfile(
  id: 'u-1',
  fullName: 'Автор',
  createdAt: DateTime(2026),
  followersCount: 0,
  followingCount: 0,
  isVerified: false,
  role: 'user',
);

Future<void> _openSheet(
  WidgetTester tester, {
  required UserProfile? profile,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allQuestPresetsProvider.overrideWith(
          (_) async => [_entry('Альфа'), _entry('Бета')],
        ),
        currentUserProfileProvider.overrideWith((_) async => profile),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPresetMarketSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Кадры вместо pumpAndSettle: пока провайдер не разрешится, в шите крутится
  // индикатор, который никогда не «успокаивается».
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('гость с пресетами: шит про вход, а не про пустоту', (
    tester,
  ) async {
    await _openSheet(tester, profile: null);

    expect(tester.takeException(), isNull);
    expect(find.text('Пресеты кнопок'), findsOneWidget);
    expect(find.text('Войдите в аккаунт'), findsOneWidget);
    expect(
      find.text('Публиковать пресеты можно только из-под своего профиля'),
      findsOneWidget,
    );
    expect(find.text('Пресетов нет'), findsNothing);
  });

  testWidgets('с аккаунтом: пресеты видны в списке', (tester) async {
    await _openSheet(tester, profile: _author());

    expect(tester.takeException(), isNull);
    expect(find.text('Войдите в аккаунт'), findsNothing);
    expect(find.text('Пресетов нет'), findsNothing);
    expect(find.text('Альфа'), findsWidgets);
  });
}
