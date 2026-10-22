// Примитивы адаптивных поверхностей: одно и то же меню должно выглядеть
// bottom sheet'ом на телефоне и диалогом у курсора на ПК, а контекстное меню
// обязано открываться и правой кнопкой, и долгим тапом.

import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openWindow(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Экран с кнопкой, открывающей меню через [showAdaptiveSheet].
  Widget host(Future<void> Function(BuildContext) open) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => open(context),
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
  );

  testWidgets('на телефоне — привычный bottom sheet', (tester) async {
    await openWindow(tester, const Size(390, 844));
    await tester.pumpWidget(
      host(
        (context) => showAdaptiveSheet<void>(
          context: context,
          builder: (_) => const Text('пункт'),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('пункт'), findsOneWidget);
  });

  // НЕГАТИВНЫЙ КОНТРОЛЬ (#215): в `_showBottomSheet` содержимое обёрнуто в
  // `SafeArea(top: false)`. Убери обёртку — Material при `useSafeArea: false`
  // не добавляет SafeArea вообще (bottom_sheet.dart: `useSafeArea ? SafeArea(
  // bottom: false …) : MediaQuery.removePadding`), и нижний край текста
  // оказывается ровно на 844, то есть под зоной жеста home-индикатора.
  group('bottom sheet на iPhone', () {
    Future<void> openPhoneSheet(
      WidgetTester tester, {
      bool homeIndicator = true,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      if (homeIndicator) {
        tester.view.padding = const FakeViewPadding(bottom: 34);
      }
      addTearDown(tester.view.reset);
      addTearDown(tester.view.resetPadding);

      await tester.pumpWidget(
        host(
          (context) => showAdaptiveSheet<void>(
            context: context,
            builder: (_) => const Text('пункт'),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();
    }

    testWidgets('последний пункт не залезает под жест home-индикатора', (
      tester,
    ) async {
      await openPhoneSheet(tester);

      const homeArea = 34.0;
      final contentBottom = tester.getRect(find.text('пункт')).bottom;
      expect(
        contentBottom,
        lessThanOrEqualTo(844 - homeArea),
        reason: 'тап по нижней кнопке попадает в зону системного жеста',
      );
      // И при этом не улетает вверх: шит обязан оставаться у нижнего края.
      expect(contentBottom, greaterThan(844 - homeArea - 120));
    });

    testWidgets('без нижней зоны отступ не выдумывается', (tester) async {
      // iPhone SE / Android: padding.bottom = 0 → лишнего воздуха быть не должно.
      await openPhoneSheet(tester, homeIndicator: false);

      expect(tester.getRect(find.text('пункт')).bottom, closeTo(844, 1));
    });
  });

  testWidgets('на широком окне — диалог у курсора, а не у нижнего края', (
    tester,
  ) async {
    await openWindow(tester, const Size(1440, 900));
    await tester.pumpWidget(
      host(
        (context) => showAdaptiveSheet<void>(
          context: context,
          title: 'Действия',
          anchor: const Offset(200, 150),
          builder: (_) => const Text('пункт'),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Действия'), findsOneWidget);
    final top = tester.getTopLeft(find.text('пункт'));
    expect(top.dx, lessThan(400));
    expect(top.dy, lessThan(400));
  });

  testWidgets('диалог не выпускает широкое содержимое за края', (tester) async {
    await openWindow(tester, const Size(1440, 900));
    await tester.pumpWidget(
      host(
        (context) => showAdaptiveSheet<void>(
          context: context,
          builder: (_) => SizedBox(
            width: 2000,
            child: ListView(
              shrinkWrap: true,
              children: const [Text('a'), Text('b')],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(ListView)).width, lessThanOrEqualTo(420));
  });

  testWidgets('AdaptiveContent держит форму в читаемой колонке', (
    tester,
  ) async {
    await openWindow(tester, const Size(1440, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveContent(child: Container(color: Colors.blue)),
        ),
      ),
    );

    expect(tester.getSize(find.byType(Container)).width, 720);
  });

  testWidgets('контекстное меню открывается правой кнопкой', (tester) async {
    await openWindow(tester, const Size(1440, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopContextMenu(
            items: (_) => [
              const PopupMenuItem(value: 'hide', child: Text('Скрыть')),
            ],
            child: const SizedBox(width: 200, height: 80, child: Text('слой')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('слой'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Скрыть'), findsOneWidget);
  });

  testWidgets('долгий тап на тач-экране не отбираем — он тоже открывает', (
    tester,
  ) async {
    await openWindow(tester, const Size(1440, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopContextMenu(
            items: (_) => [
              const PopupMenuItem(value: 'hide', child: Text('Скрыть')),
            ],
            child: const SizedBox(width: 200, height: 80, child: Text('слой')),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('слой'));
    await tester.pumpAndSettle();

    expect(find.text('Скрыть'), findsOneWidget);
  });

  testWidgets('выбранный пункт возвращается вызывающей стороне', (
    tester,
  ) async {
    Object? chosen;
    await openWindow(tester, const Size(1440, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopContextMenu(
            items: (_) => [
              const PopupMenuItem(value: 'hide', child: Text('Скрыть')),
            ],
            onSelected: (value) => chosen = value,
            child: const SizedBox(width: 200, height: 80, child: Text('слой')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('слой'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скрыть'));
    await tester.pumpAndSettle();

    expect(chosen, 'hide');
  });

  testWidgets('длинный пикер в диалоге прокручивается, а не переливается', (
    tester,
  ) async {
    await openWindow(tester, const Size(1440, 900));
    await tester.pumpWidget(
      host(
        (context) => showAdaptiveSheet<void>(
          context: context,
          scrollable: true,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 40; i++) ListTile(title: Text('$i')),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Column строит все пункты сразу, поэтому проверяем не наличие в дереве,
    // а позицию: без прокрутки последний пункт уехал бы за нижний край.
    final hiddenAt = tester.getTopLeft(find.text('39')).dy;
    expect(hiddenAt, greaterThan(900));

    await tester.drag(find.byType(ListTile).first, const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('39')).dy, lessThan(hiddenAt));
    expect(tester.getBottomRight(find.text('39')).dy, lessThanOrEqualTo(900));
  });
}
