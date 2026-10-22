import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/app/screens/tutorial_screen.dart';

/// «Академия» ограничена `AdaptiveContent(maxWidth: 900)`, а окно десктопа
/// бывает 1400 широким. Число колонок считалось по ширине окна: сетка брала
/// три колонки в 900 px — карточка 282.7, текст 168.7. Это ровно
/// `BoxConstraints(w=168.7, h=72.0)` и `A RenderFlex overflowed by 4.0 pixels
/// on the bottom` из crash_log.txt (Column tutorial_screen.dart:659, карточка
/// сообщества).
///
/// В тесте `setSurfaceSize` меняет только монтажную коробку, а
/// `MediaQuery.size` остаётся 800×600 — поэтому размер окна подменяем явно.
/// Так воспроизводится настоящая пара: окно 1400, колонка контента 900.
///
/// Негативный контроль проверен на дофиксовом файле:
/// 1) вернуть `MediaQuery.of(context).size.width` вместо
///    `constraints.maxWidth` — тест падает с `RenderFlex overflowed` при тех
///    же `BoxConstraints(w=168.7, h=72.0)` из лога (в тестовом шрифте буквы
///    квадратные и шире, поэтому перелив 54 px вместо 4 px из crash_log.txt);
/// 2) оставить LayoutBuilder, но снять ограничители текста и вернуть
///    `mainAxisExtent: 96` — те же 4 px уже при `w=315`.
/// Второй тест — страховка, что на телефоне остался один столбец; на
/// дофиксовом коде он тоже зелёный.
Future<void> _openCommunity(
  WidgetTester tester, {
  required double windowWidth,
}) async {
  await tester.binding.setSurfaceSize(Size(windowWidth, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(windowWidth, 950)),
            child: const TutorialScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Сетка строится при переключении таба: пока активен «Гайды», карточек
  // сообщества нет.
  await tester.tap(find.text('Сообщество'));
  await tester.pumpAndSettle();
}

/// Карточка приватна для теста — ищем по имени класса.
Finder communityCards() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_CommunityCard',
);

void main() {
  testWidgets('окно 1400: три колонки не впихиваются в 900 px контента', (
    tester,
  ) async {
    await _openCommunity(tester, windowWidth: 1400);

    expect(
      tester.takeException(),
      isNull,
      reason: 'карточка сообщества переполняется — жёлто-чёрные полосы',
    );
    expect(communityCards(), findsNWidgets(7));

    final cardWidth = tester.getSize(communityCards().first).width;
    expect(
      cardWidth,
      greaterThan(300),
      reason:
          'карточка $cardWidth px: сетка взяла три колонки из ширины окна, '
          'хотя колонка контента — 900 px',
    );
  });

  testWidgets('телефон 420: список остаётся одноколоночным', (tester) async {
    await _openCommunity(tester, windowWidth: 420);

    expect(tester.takeException(), isNull);
    expect(communityCards(), findsNWidgets(7));
    expect(
      tester.getSize(communityCards().first).width,
      lessThan(420),
      reason: 'одна колонка во всю ширину, без сетки',
    );
  });
}
