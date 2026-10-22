import 'package:canvas_app/features/quests/providers/quest_provider.dart';
import 'package:canvas_app/features/quests/screens/my_quests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// «Мои» — экран, на который развилка онбординга (#247) сажает новичка с
// намерением «создавать». Первым делом он видел плашку «Облачная синхронизация
// не настроена / Подключите облако, чтобы не потерять прогресс» — страх перед
// человеком, у которого ещё нет ни одного квеста. Плашка теперь появляется
// только когда терять уже есть.
//
// Тест настоящий: экран собирается в ProviderScope с подменённым
// questsProvider, реального диска и Rust-хоста для этого не нужно.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ: убери `if (libraryStats.total > 0)` перед слайвером
// _SyncStatusCard в my_quests_screen.dart — падает первый тест.
void main() {
  setUp(() {
    // Пустые prefs = гость: ни user_id, ни токена, ни настроек облака.
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLibrary(WidgetTester tester, List<Quest> quests) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          questsProvider.overrideWith((ref) async => quests),
        ],
        child: MaterialApp(
          home: MyQuestsScreen(isRoot: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('пустая библиотека не пугает облачной синхронизацией', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester, const []);

    expect(find.text('Здесь пока пусто'), findsOneWidget);
    expect(find.textContaining('Облачная синхронизация'), findsNothing);
    // Призыв создать квест обязан остаться на экране — это и есть весь смысл
    // первого визита.
    expect(find.text('Создать квест'), findsWidgets);
  });

  testWidgets('с первым квестом плашка синхронизации возвращается', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(
      tester,
      [Quest(id: 'q1', title: 'Первый квест', isReadOnly: true)],
    );

    expect(find.textContaining('Облачная синхронизация'), findsOneWidget);
  });
}
