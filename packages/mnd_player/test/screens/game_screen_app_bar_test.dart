// Регрессия (#242): шапка игрового экрана не должна разрастаться до
// неширокого телефона.
//
// На «Последнем лесе» (Android, 360 px) в actions стояло шесть пилюль,
// AppBar не вмещал их и рисовал «Громкость» поверх стрелки «назад». Редкие
// кнопки — появление текста, переменные (тест-режим) и редактирование ноды —
// уехали в подменю «Ещё», часто используемые остались в шапке.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/screens/game_screen.dart';

Future<bool> _neverStart() async => false;

void main() {
  testWidgets(
    'редкие кнопки шапки — в подменю, а не в ряд с «назад»',
    (tester) async {
      // Узкий телефон: ровно та ширина, на которой баг был виден.
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var editTaps = 0;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: GameScreen(
              questId: 'test-quest',
              // Префлайт = false: сессия не стартует, движок/FFI не нужны.
              preflight: _neverStart,
              isTesting: true,
              onEditNode: () => editTaps++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Переполнение шапки фреймворк оформляет как исключение layoutа.
      expect(tester.takeException(), isNull);

      // Сам баг: AppBar не лезет в ширину, а уводит actions влево, и
      // «Громкость» рисуется поверх стрелки «назад».
      expect(
        tester.getRect(find.byTooltip('Назад')).right,
        lessThan(tester.getRect(find.byTooltip('Громкость')).left),
      );

      // В шапке только частые кнопки.
      expect(find.byTooltip('Громкость'), findsOneWidget);
      expect(find.byTooltip('Сохранить'), findsOneWidget);
      expect(find.byTooltip('Загрузить'), findsOneWidget);
      // Редкие — не видны, пока меню не открыто.
      expect(find.byTooltip('Переменные'), findsNothing);
      expect(find.byTooltip('Редактировать ноду'), findsNothing);
      expect(find.byTooltip('Ещё'), findsOneWidget);

      await tester.tap(find.byTooltip('Ещё'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Переменные'), findsOneWidget);
      expect(find.text('Редактировать ноду'), findsOneWidget);

      await tester.tap(find.text('Редактировать ноду'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(editTaps, 1);
    },
  );
}
