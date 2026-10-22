import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/editor/workspace/editor_tabs_bar.dart';

/// 42 px справа из crash_log.txt — это панель вкладок редактора:
/// `constraints: BoxConstraints(0.0<=w<=152.0)` при ширине детей 194.
/// 152 — компактный слот вкладки (148 + 2*2), 194 — обычный (190 + 2*2).
/// То есть окно сузили ниже 620 px, `SizedBox` скроллера уже пересчитан под
/// компактный режим, а `AnimatedContainer` вкладки ещё досматривает 100-мс
/// анимацию старой ширины. Ряд на этот кадр шире своего контейнера.
Widget _host(double width, {int tabs = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, 900), disableAnimations: true),
    child: Scaffold(
      body: SizedBox(
        width: width,
        child: EditorTabsBar(
          tabs: [
            for (int i = 0; i < tabs; i++)
              EditorTabData(
                id: 'tab-$i',
                title: 'Нода $i',
                icon: Icons.crop_square_rounded,
                isDirty: i == 0,
              ),
          ],
          activeTabId: 'tab-0',
          onSelect: (_) {},
          onClose: (_) {},
          onNewTab: () {},
        ),
      ),
    ),
  ),
);

void main() {
  group('панель вкладок редактора', () {
    testWidgets('сужение окна до компактного режима не рвёт ряд', (tester) async {
      await tester.pumpWidget(_host(700));
      await tester.pump();

      await tester.pumpWidget(_host(600));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('расширение окна обратно тоже без переполнения', (tester) async {
      await tester.pumpWidget(_host(600));
      await tester.pump();

      await tester.pumpWidget(_host(700));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('много вкладок: ряд остаётся прокручиваемым', (tester) async {
      await tester.pumpWidget(_host(600, tabs: 8));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(EditorTabsBar),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        scrollable.position.maxScrollExtent,
        greaterThan(0),
        reason: 'ряд схлопнулся во вьюпорт — вкладки не достать',
      );
    });

    testWidgets('несколько вкладок в_compact-окне влезают в свой слот', (tester) async {
      await tester.pumpWidget(_host(700, tabs: 4));
      await tester.pump();

      await tester.pumpWidget(_host(600, tabs: 4));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
