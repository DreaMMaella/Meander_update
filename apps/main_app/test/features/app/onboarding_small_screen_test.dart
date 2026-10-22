import 'package:canvas_app/features/app/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// Онбординг — первый экран новичка, и на маленьком телефоне с крупным
// системным шрифтом промо-страница не влезала в PageView: RenderFlex
// переполнялся жёлтыми полосами ровно на «Создавай миры».
//
// Тест настоящий (не по тексту файла): OnboardingScreen собирается в изоляции,
// без riverpod, рекламного SDK и audio-сессии — они нужны только SplashScreen
// и MenuScreen, а до них в этом тесте дело не доходит.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ: верни `Column` вместо `Center + SingleChildScrollView`
// в itemBuilder — падает «промо-страница масштабируется без переполнения».
void main() {
  setUpAll(() {
    // GoogleFonts в тестовой среде не имеет сети: просим его не пытаться
    // скачивать шрифт и молча отдавать дефолтный.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('промо-страница масштабируется без переполнения', (tester) async {
    tester.view.physicalSize = const Size(480, 800); // 320x533 логических px
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);

    // Кнопка «Далее» обязана остаться доступной — без скролла она уезжала за
    // нижний край, и новичок не мог пройти дальше первой страницы.
    expect(find.text('Далее'), findsOneWidget);
  });

  testWidgets('развилка влезает в маленький экран и показывается после промо', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pump();

    // Три промо-страницы, потом «Продолжить» открывает развилку (#247).
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Продолжить'), findsOneWidget);
    await tester.tap(find.text('Продолжить'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Пройти квест'), findsOneWidget);
    expect(find.text('Создать квест'), findsOneWidget);
  });

  testWidgets('развилка честно говорит, куда ведёт выбор', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Продолжить'));
    await tester.pump();

    // Обещание «дальше подскажем, куда идти» никто не выполнял: подсказок в
    // программе нет, а туториал выключен. Честная формулировка — куда именно
    // попадёт новичок после тапа.
    expect(
      find.textContaining('Этот выбор решает только первый экран'),
      findsOneWidget,
    );
    expect(find.textContaining('Дальше подскажем'), findsNothing);
  });
}
