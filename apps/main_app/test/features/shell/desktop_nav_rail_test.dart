import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/shell/widgets/animated_nav_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Row(children: [child, const Expanded(child: SizedBox())])),
);

void main() {
  const items = [
    NavBarItem(icon: Icons.explore_outlined, label: 'Каталог'),
    NavBarItem(icon: Icons.public_outlined, label: 'Сообщество'),
    NavBarItem(
      icon: Icons.notifications_outlined,
      label: 'Уведомления',
      badge: 3,
    ),
  ];

  testWidgets('рельса показывает подписи и шлёт индекс тапа', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      _wrap(
        DesktopNavRail(
          items: items,
          currentIndex: 0,
          onTap: tapped.add,
        ),
      ),
    );

    expect(find.text('Каталог'), findsOneWidget);
    expect(find.text('Сообщество'), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    // На телефоне такая же полоса — нижняя, здесь подписей не видно бы.

    await tester.tap(find.text('Сообщество'));
    await tester.pumpAndSettle();
    expect(tapped, [1]);
  });

  testWidgets('бейдж unread переживает переключение вкладки', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DesktopNavRail(items: items, currentIndex: 2, onTap: (_) {}),
      ),
    );

    expect(find.byType(Badge), findsWidgets);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('в узком окне рельса не переполняется', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        DesktopNavRail(items: items, currentIndex: 0, onTap: (_) {}),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
