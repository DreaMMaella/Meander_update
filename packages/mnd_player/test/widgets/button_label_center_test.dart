// Подпись кнопки должна стоять по центру плашки, а не прижиматься к её верху.
//
// Плоская кнопка (`ButtonStyleConfig` без картиночных модулей) обязана быть не
// ниже `minHeight`, который считается из модулей стиля. Раньше под `ConstrainedBox`
// лежал `Padding` без выравнивания: `RenderPadding` вычитает паддинги из *минимума*
// высоты и передаёт ребёнку растягивающие ограничения. В итоге бокс `RichText`
// растягивается на всю внутреннюю высоту плашки, а глифы (~20 px для одной строки)
// рисуются в его верху — текст визуально уезжает вверх. Версия кнопки с asset-
// рамкой (`ModuleAssetFrame`) оборачивает контент в `Center` и этого не делает.
//
// Поэтому проверка в двух частях:
//   1) бокс подписи не должен расти вместе с плашкой — это и есть негативный
//      контроль, он падает на старом коде (24 px против 81.6 px);
//   2) бокс подписи должен совпадать центром с плашкой — на старом коде проходит
//      «вхолостую» (растянутый бокс симметричен), потому и нужна часть 1.
//
// Движок для этого не нужен: `GlassButton` рисует только свой контент.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';

/// Надпись кнопки — это `RichText` со спанами после разбора markdown-тегов,
/// поэтому ищем по её итоговому тексту, а не по виджету `Text`.
Finder buttonLabel(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
);

/// Рендерит плоскую кнопку с заданной высотой плашки ([verticalModules]) и
/// возвращает прямоугольники плашки и подписи.
Future<({Rect button, Rect label})> renderFlatButton(
  WidgetTester tester, {
  required String text,
  required int verticalModules,
  bool wrapText = true,
}) async {
  final container = ProviderContainer()..listen(gameStateProvider, (_, __) {});
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassButton(
              onPressed: () {},
              text: text,
              wrapText: wrapText,
              styleConfig: ButtonStyleConfig(
                moduleSize: 12,
                verticalModules: verticalModules,
                horizontalModules: 6,
                centerModules: 10,
              ),
              questId: 'q1',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (
    button: tester.getRect(find.byType(GlassButton)),
    label: tester.getRect(buttonLabel(text)),
  );
}

void main() {
  group('центрирование подписи кнопки', () {
    testWidgets('плашка не растягивает надпись', (tester) async {
      // v=2 → minHeight 40, v=8 → minHeight 120 (кламп). Одна и та же строка
      // текста обязана давать один и тот же бокс подписи.
      final short = await renderFlatButton(
        tester,
        text: 'Идти',
        verticalModules: 2,
      );
      final tall = await renderFlatButton(
        tester,
        text: 'Идти',
        verticalModules: 8,
      );

      expect(tall.button.height - tall.label.height, greaterThan(10));
      expect(
        tall.label.height,
        moreOrLessEquals(short.label.height, epsilon: 0.5),
        reason:
            'бокс подписи вырос вместе с плашкой: '
            '${short.label.height} px → ${tall.label.height} px, '
            'значит Padding растянул контент и глифы встали в верх',
      );
    });

    testWidgets('короткая надпись по вертикали в центре плашки', (
      tester,
    ) async {
      final r = await renderFlatButton(
        tester,
        text: 'Идти',
        verticalModules: 8,
      );

      expect(r.button.height - r.label.height, greaterThan(10));
      expect(
        r.label.center.dy,
        closeTo(r.button.center.dy, 1.0),
        reason: 'подпись прижата к верху плашки',
      );
    });

    testWidgets('короткая надпись по горизонтали в центре плашки', (
      tester,
    ) async {
      final r = await renderFlatButton(
        tester,
        text: 'Идти',
        verticalModules: 8,
      );

      expect(
        r.label.center.dx,
        closeTo(r.button.center.dx, 1.0),
        reason: 'подпись прижата к левому краю плашки',
      );
    });

    testWidgets('длинная надпись в перенос тоже центрируется', (tester) async {
      final r = await renderFlatButton(
        tester,
        text: 'Открыть дверь и посмотреть, что за ней',
        verticalModules: 8,
      );

      expect(r.label.center.dx, closeTo(r.button.center.dx, 1.0));
      expect(r.label.center.dy, closeTo(r.button.center.dy, 1.0));
    });

    testWidgets('кнопка без стиля (стеклянная плашка) не рассинхронизирована', (
      tester,
    ) async {
      final container = ProviderContainer()
        ..listen(gameStateProvider, (_, __) {});
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: GlassButton(onPressed: null, text: 'Обычная'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paddingRect = tester.getRect(
        find
            .ancestor(
              of: buttonLabel('Обычная'),
              matching: find.byType(Padding),
            )
            .first,
      );
      final label = tester.getRect(buttonLabel('Обычная'));
      // Паддинг симметричный: центр текста совпадает с центром паддинга сам,
      // без какого-либо выравнивания.
      expect(label.center.dy, closeTo(paddingRect.center.dy, 1.0));
    });
  });
}
