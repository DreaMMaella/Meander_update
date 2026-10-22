// Из настроек ноды убран блок «ДОСТУП» («Разрешить сохранение» и «Доступ к
// инвентарю»). Оба переключателя управляли флагами, которые читала только
// HUD-панель: её вырезали из движка и приложения (#187, коммит 9fe28eb), после
// чего строки остались пустить пыль — кнопка «Сохранить» в плеере теперь
// unconditional, а доступ к инвентарю не ограничен нигде.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ: вернуть в `node_settings_screen.dart` прежнюю секцию
// «ДОСТУП» с двумя `SwitchListTile` — падает первый тест (находит снятые
// строки). Второй тест — страховка от обратного: он требует, чтобы вместе с
// секцией не выехал весь экран, и проверяет, что живой блок таймера и кнопка
// сохранения на месте.
//
// Что этим тестом НЕ покрыто: поля `allowSave`/`allowInventoryAccess`
// намеренно остались в модели и в projection (`node_content_screen.dart`
// читает их из ноды и пишет обратно) — ключи в nodes.json живых квестов не
// должны измениться. Это проверка диффа, не рантайма.

import 'package:canvas_app/features/editor/screens/node_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openSettings(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: NodeSettingsScreen(
          questId: 'quest-1',
          nodeId: 'n1',
          initialBackgroundId: null,
          initialBackgroundVideoId: 'intro.mp4',
          initialBackgroundVideoName: 'Intro',
          initialVideoVolume: 1,
          initialVideoLoop: true,
          initialVideoMuted: false,
          initialVideoFit: 'cover',
          initialBackgroundBlur: null,
          initialAudioId: null,
          initialAudioVolume: 1,
          initialItemSpacing: null,
          initialImageRoundedCorners: null,
          initialTransitionMode: 'fade',
          initialTimerEnabled: true,
          initialTimerHidden: false,
          initialTimerDurationText: '30',
          initialDefaultActionNodeId: null,
          initialDefaultActionNodeName: 'Нода не найдена',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('наследия HUD-панели в настройках ноды больше нет', (
    WidgetTester tester,
  ) async {
    await _openSettings(tester);

    // Верх экрана виден сразу, нижний блок докручиваем — ListView за вьюпором
    // не строит и find его не увидит.
    for (final title in const ['Разрешить сохранение', 'Доступ к инвентарю']) {
      expect(
        find.text(title),
        findsNothing,
        reason: '$title — строка HUD-панели, её не должно быть в настройках',
      );
    }

    await tester.scrollUntilVisible(
      find.text('Готово — сохранить'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    for (final title in const ['Разрешить сохранение', 'Доступ к инвентарю']) {
      expect(find.text(title), findsNothing, reason: '$title вернулась вниз');
    }
    expect(find.text('ДОСТУП'), findsNothing);
  });

  testWidgets('убрана только секция «ДОСТУП» — экран целиком живой', (
    WidgetTester tester,
  ) async {
    await _openSettings(tester);

    expect(find.text('ФОН'), findsOneWidget);
    // ListView строит только то, что попадает во вьюпорт, поэтому за остальными
    // заголовками нужно приехать скроллом.
    await tester.scrollUntilVisible(
      find.text('ОФОРМЛЕНИЕ'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ОФОРМЛЕНИЕ'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Готово — сохранить'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Последний блок с переключателем — «Скрыть таймер».
    expect(find.text('Скрыть таймер'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
