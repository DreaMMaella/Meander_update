// Regression-тест на сборку экрана «Локальные пресеты»: экран живёт внутри
// CustomScrollView, и box-виджет (например LayoutBuilder) в списке slivers
// роняет вьюпорт assertion'ом из framework.dart. Поэтому прогоняем все три
// перехода состояния провайдера — loading (shimmer), data (сетка/пусто),
// error (блок ошибки): каждая ветка возвращает свой тип сливера.
//
// Пресеты подаём оверрайдом, а не с диска: реальный IO под FakeAsync не
// дожидается, а бесконечный Shimmer вечно вешает pumpAndSettle.

import 'dart:async';

import 'package:canvas_app/features/hub/screens/local_presets_screen.dart';
import 'package:canvas_app/features/hub/widgets/preset_market.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

QuestPresetEntry _entry(String name, {required bool isOwn}) => QuestPresetEntry(
  questId: 'q-1',
  questTitle: 'Тестовый квест',
  presetId: name,
  presetName: name,
  config: ButtonStyleConfig.fromJson({'presetId': name, 'presetName': name}),
  isOwn: isOwn,
);

Future<void> _pumpScreen(
  WidgetTester tester,
  Future<List<QuestPresetEntry>> Function() presets,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allQuestPresetsProvider.overrideWith((_) => presets()),
      ],
      child: const MaterialApp(home: LocalPresetsScreen()),
    ),
  );
  // Кадры вместо pumpAndSettle: shimmer-анимация никогда не «успокаивается».
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('данные: свои и чужие пресеты в сетке', (tester) async {
    await _pumpScreen(
      tester,
      () async => [
        _entry('Альфа', isOwn: true),
        _entry('Бета', isOwn: false),
      ],
    );

    expect(tester.takeException(), isNull);
    // Имя пресета видно дважды: надпись на превью кнопки и заголовок карточки.
    expect(find.text('Альфа'), findsNWidgets(2));
    expect(find.text('Бета'), findsNWidgets(2));
    expect(find.text('ВАШ'), findsOneWidget);
    expect(find.text('ИЗ МАРКЕТА'), findsOneWidget);
  });

  testWidgets('фильтры перестраивают сетку без смены типа сливера', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      () async => [
        _entry('Альфа', isOwn: true),
        _entry('Бета', isOwn: false),
      ],
    );

    await tester.tap(find.text('Мои'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Альфа'), findsNWidgets(2));
    expect(find.text('Бета'), findsNothing);

    await tester.tap(find.text('Из скачанных квестов'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Альфа'), findsNothing);
    expect(find.text('Бета'), findsNWidgets(2));
  });

  testWidgets('пустой список → пустое состояние, не падение', (
    tester,
  ) async {
    await _pumpScreen(tester, () async => const []);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Пресетов нет.'), findsOneWidget);
  });

  testWidgets('ошибка провайдера → блок ошибки вместо сетки', (tester) async {
    await _pumpScreen(
      tester,
      () => Future.error(StateError('disk is unavailable')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Попробовать снова'), findsOneWidget);
    expect(find.textContaining('Пресетов нет.'), findsNothing);
  });

  testWidgets('пока данные грузятся — shimmer-сетка', (tester) async {
    await _pumpScreen(tester, () => Completer<List<QuestPresetEntry>>().future);
    expect(tester.takeException(), isNull);
    expect(find.text('Альфа'), findsNothing);
    expect(find.textContaining('Пресетов нет.'), findsNothing);
  });
}
