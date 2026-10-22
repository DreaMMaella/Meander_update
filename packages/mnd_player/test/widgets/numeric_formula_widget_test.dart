// Рантайм: числовые поля айтема могут брать значение из формулы
// (`numericExprs`), а не из статического числа — `{gap}`, `hp/2 + 16`.
// Покрыто: отступ (spacer), зазор ряда, длительность отсчёта и кегль текста.
// Значение пересчитывается при каждом изменении состояния, как у `{текст}` и
// у картинки-источника; при нераскрытой формуле остаётся статическое число из
// редактора. Без формулы поведение ровно прежнее. У отсчёта своё правило:
// формула считается один раз при появлении, иначе пересчёт перезапускал бы
// таймер на середине.
//
// Простая переменная считается быстрым путём Dart (без FFI); арифметику
// целиком берёт Rust-ядро, поэтому группа «арифметика» требует собранный `.so`
// — как в test/widgets/image_resource_expr_test.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';

final String? _soPath = () {
  final env = Platform.environment['MND_FFI_SO'];
  if (env != null && File(env).existsSync()) return env;
  for (final candidate in [
    '../../target/release/libmnd_ffi.so',
    '../../crates/mnd-ffi/target/release/libmnd_ffi.so',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}();

void main() {
  setUpAll(() async {
    if (_soPath != null) {
      await initRustCore(externalLibrary: ExternalLibrary.open(_soPath!));
    }
  });

  /// Виджет строки/отступа рисуется без движка (нет `GameSessionScope`), то
  /// есть по legacy-пути резолвера — тот же код нормализации и фолбэка.
  ///
  /// [prebuild] нужен для таймера: его длительность считается один раз при
  /// появлении, поэтому переменную надо завести до первого кадра.
  Future<ProviderContainer> render(
    WidgetTester tester,
    ContentItem item, {
    void Function(ProviderContainer container)? prebuild,
  }) async {
    final container = ProviderContainer()
      ..listen(gameStateProvider, (_, __) {});
    addTearDown(container.dispose);
    prebuild?.call(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ContentDisplayFactory.build(
                item: item,
                questId: 'q1',
                onInteract: (_) {},
                onInputSubmitted: (_, __) {},
                onComplete: () {},
                onTransition: (_) {},
                onNavigateToNode: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  ContentItem spacer({double? padding, String? expr}) => ContentItem(
    id: 'sp',
    type: 'spacer',
    padding: padding,
    numericExprs: expr == null ? null : {'padding': expr},
  );

  double spacerHeight(WidgetTester tester) => tester
      .widget<SizedBox>(
        find.byWidgetPredicate((w) => w is SizedBox && w.height != null).first,
      )
      .height!;

  void setGap(ProviderContainer container, Object value) {
    container.read(gameStateProvider.notifier).setVariable('gap', value);
  }

  group('отступ (spacer)', () {
    testWidgets('без формулы — статическое число и прежний дефолт', (
      tester,
    ) async {
      await render(tester, spacer(padding: 24));
      expect(spacerHeight(tester), 24.0);

      await render(tester, spacer());
      expect(spacerHeight(tester), 16.0);
    });

    testWidgets('формула `{gap}` берёт число из переменной', (tester) async {
      final container = await render(
        tester,
        spacer(padding: 24, expr: '{gap}'),
      );

      setGap(container, 40);
      await tester.pump();

      expect(spacerHeight(tester), 40.0);
    });

    testWidgets('значение пересчитывается при каждом изменении состояния', (
      tester,
    ) async {
      final container = await render(tester, spacer(expr: 'gap'));

      for (final next in [12, 64, 12]) {
        setGap(container, next);
        await tester.pump();
        expect(spacerHeight(tester), next.toDouble(), reason: '$next');
      }
    });

    testWidgets('нечисловое значение — откат на число из ноды', (tester) async {
      final container = await render(
        tester,
        spacer(padding: 24, expr: '{gap}'),
      );

      // Переменная не задана вовсе, потом стала текстом, потом числом.
      expect(spacerHeight(tester), 24.0);
      setGap(container, 'закат');
      await tester.pump();
      expect(spacerHeight(tester), 24.0);

      setGap(container, 30);
      await tester.pump();
      expect(spacerHeight(tester), 30.0);
    });

    testWidgets('размер ограничен снизу нулём, сверху 999', (tester) async {
      final container = await render(tester, spacer(expr: 'gap'));

      setGap(container, -5);
      await tester.pump();
      expect(spacerHeight(tester), 0.0);

      setGap(container, 100000);
      await tester.pump();
      expect(spacerHeight(tester), 999.0);
    });
  });

  group('зазор ряда', () {
    ContentItem row({double? spacing, String? expr}) => ContentItem(
      id: 'row',
      type: 'row',
      itemSpacing: spacing,
      numericExprs: expr == null ? null : {'itemSpacing': expr},
      children: [
        ContentItem(id: 'a', type: 'spacer', padding: 8),
        ContentItem(id: 'b', type: 'spacer', padding: 8),
      ],
    );

    /// Row делит зазор пополам на каждую сторону между детьми.
    Iterable<EdgeInsetsGeometry> pads(WidgetTester tester) =>
        tester.widgetList<Padding>(find.byType(Padding)).map((p) => p.padding);

    testWidgets('без формулы — явное число или дефолт ряда 4 px', (
      tester,
    ) async {
      await render(tester, row(spacing: 10));
      expect(pads(tester), contains(EdgeInsets.only(left: 0.0, right: 5.0)));
      expect(pads(tester), contains(EdgeInsets.only(left: 5.0, right: 0.0)));

      await render(tester, row());
      expect(pads(tester), contains(EdgeInsets.symmetric(horizontal: 4.0)));
    });

    testWidgets('формула `{gap}` задаёт зазор и обновляется со состоянием', (
      tester,
    ) async {
      final container = await render(tester, row(spacing: 10, expr: '{gap}'));

      setGap(container, 20);
      await tester.pump();

      expect(
        pads(tester),
        contains(EdgeInsets.only(left: 0.0, right: 10.0)),
        reason: '20 px между двумя детьми — по 10 на сторону',
      );
    });
  });

  group('длительность отсчёта', () {
    ContentItem timer({String? text, String? expr}) => ContentItem(
      id: 't',
      type: 'timer',
      text: text,
      numericExprs: expr == null ? null : {'duration': expr},
    );

    double secondsOf(WidgetTester tester) =>
        tester.widget<TimerItemWidget>(find.byType(TimerItemWidget)).seconds;

    double? progress(WidgetTester tester) => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value;

    testWidgets('без формулы — секунды из текста, как раньше', (tester) async {
      await render(tester, timer(text: '2,5'));
      expect(secondsOf(tester), 2.5);

      // Пустой текст и мусор были 1.0, слишком короткое — 0.1.
      await render(tester, timer());
      expect(secondsOf(tester), 1.0);
      await render(tester, timer(text: '0.02'));
      expect(secondsOf(tester), 0.1);
    });

    testWidgets('формула `{gap}` задаёт длительность', (tester) async {
      await render(
        tester,
        timer(text: '3.0', expr: '{gap}'),
        prebuild: (c) =>
            c.read(gameStateProvider.notifier).setVariable('gap', 10),
      );

      expect(secondsOf(tester), 10.0);
      // Движок уже отдал 10 с, поэтому кадр через — десятая часть.
      await tester.pump(const Duration(seconds: 1));
      expect(progress(tester), closeTo(0.1, 0.01));
    });

    testWidgets('смена переменной на середине таймер не перезапускает', (
      tester,
    ) async {
      final container = await render(
        tester,
        timer(expr: 'gap'),
        prebuild: (c) =>
            c.read(gameStateProvider.notifier).setVariable('gap', 10),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(progress(tester), closeTo(0.1, 0.01));

      setGap(container, 40);
      await tester.pump();
      // Виджет видит новое значение — но бегущий отсчёт остаётся на 10 с:
      // пересчёт на середине перезапустил бы таймер.
      expect(secondsOf(tester), 40.0);
      await tester.pump(const Duration(seconds: 1));
      expect(progress(tester), closeTo(0.2, 0.02));
    });

    testWidgets('нераскрытая формула — число из текста', (tester) async {
      await render(
        tester,
        timer(text: '3.0', expr: '{gap}'),
        prebuild: (c) =>
            c.read(gameStateProvider.notifier).setVariable('gap', 'закат'),
      );

      expect(secondsOf(tester), 3.0);
    });

    testWidgets('длительность ограничена 0.1 … 86400', (tester) async {
      final container = await render(
        tester,
        timer(expr: 'gap'),
        prebuild: (c) =>
            c.read(gameStateProvider.notifier).setVariable('gap', 5),
      );

      setGap(container, -10);
      await tester.pump();
      expect(secondsOf(tester), 0.1);

      setGap(container, 1000000);
      await tester.pump();
      expect(secondsOf(tester), 86400.0);
    });
  });

  group('размер текста', () {
    ContentItem note({
      double? textSize,
      String? expr,
      String text = 'обычный абзац',
    }) => ContentItem(
      id: 'tx',
      type: 'text',
      text: text,
      textSize: textSize,
      numericExprs: expr == null ? null : {'textSize': expr},
    );

    /// Кегль доходит до дерева как `DefaultTextStyle.merge` над markdown-блоком
    /// (сам генератор абзацы плодит внутри), поэтому читаем самый глубокий
    /// ненулевой — это база, из которой множатся заголовки.
    double? fontSizeRendered(WidgetTester tester) => tester
        .widgetList<DefaultTextStyle>(find.byType(DefaultTextStyle))
        .map((w) => w.style.fontSize)
        .whereType<double>()
        .last;

    testWidgets('без формулы — 16 или число из редактора', (tester) async {
      await render(tester, note());
      expect(fontSizeRendered(tester), 16.0);

      await render(tester, note(textSize: 28));
      expect(fontSizeRendered(tester), 28.0);
    });

    testWidgets('формула меняет кегль и пересчитывается со состоянием', (
      tester,
    ) async {
      final container = await render(
        tester,
        note(textSize: 18, expr: '{gap}'),
        prebuild: (c) =>
            c.read(gameStateProvider.notifier).setVariable('gap', 32),
      );
      expect(fontSizeRendered(tester), 32.0);

      setGap(container, 20);
      await tester.pump();
      expect(fontSizeRendered(tester), 20.0);
    });

    testWidgets('кегль ограничен 6 … 200', (tester) async {
      final container = await render(
        tester,
        // Короткая строка: абзац на 200 px не влезает в тестовый вьюпорт 600 px
        // и падает переполнением раньше, чем успевает что-то проверить.
        note(expr: 'gap', text: 'раз'),
        prebuild: (c) =>
            c.read(gameStateProvider.notifier).setVariable('gap', 20),
      );

      setGap(container, 1);
      await tester.pump();
      expect(fontSizeRendered(tester), 6.0);

      setGap(container, 4000);
      await tester.pump();
      expect(fontSizeRendered(tester), 200.0);
    });
  });

  group('скругление стека', () {
    ContentItem panel({double? radius, String? expr}) => ContentItem(
      id: 'st',
      type: 'stack',
      stackHeight: 120,
      backgroundColor: const Color(0xFF112233),
      borderRadius: radius,
      numericExprs: expr == null ? null : {'borderRadius': expr},
      children: [ContentItem(id: 'c', type: 'text', text: 'слой')],
    );

    /// Радиус фона — единственная `Container` с цветом и скруглением.
    double? radiusOf(WidgetTester tester) {
      for (final box in tester.widgetList<Container>(find.byType(Container))) {
        final d = box.decoration;
        if (d is BoxDecoration && d.color != null && d.borderRadius != null) {
          return (d.borderRadius! as BorderRadius).topLeft.x;
        }
      }
      return null;
    }

    testWidgets('без формулы — число из редактора, без него рамки нет', (
      tester,
    ) async {
      await render(tester, panel(radius: 12));
      expect(radiusOf(tester), 12.0);

      // Скругления не задавали вовсе — Container с нулевым радиусом не плодим.
      await render(tester, panel());
      expect(radiusOf(tester), isNull);
    });

    testWidgets(
      'формула `{gap}` задаёт радиус и пересчитывается со состоянием',
      (tester) async {
        final container = await render(
          tester,
          panel(radius: 12, expr: '{gap}'),
          prebuild: (c) =>
              c.read(gameStateProvider.notifier).setVariable('gap', 30),
        );
        expect(radiusOf(tester), 30.0);

        setGap(container, 4);
        await tester.pump();
        expect(radiusOf(tester), 4.0);

        // Отрицательный радиус `Radius` не терпит.
        setGap(container, -8);
        await tester.pump();
        expect(radiusOf(tester), 0.0);
      },
    );

    testWidgets('нераскрытая формула — число из редактора', (tester) async {
      final container = await render(
        tester,
        panel(radius: 12, expr: '{gap}'),
        prebuild: (c) =>
            c.read(gameStateProvider.notifier).setVariable('gap', 'снег'),
      );

      expect(radiusOf(tester), 12.0);
      setGap(container, 40);
      await tester.pump();
      expect(radiusOf(tester), 40.0);
    });
  });

  group('арифметика считается выражением целиком', () {
    testWidgets('`{hp}/2 + 16` — это hp/2+16, а не подстановка в текст', (
      tester,
    ) async {
      final container = await render(
        tester,
        spacer(padding: 24, expr: '{hp}/2 + 16'),
      );
      container.read(gameStateProvider.notifier).setVariable('hp', 48);
      await tester.pump();

      expect(spacerHeight(tester), 40.0);
    });

    testWidgets('формула с функцией: `min(40, hp)`', (tester) async {
      final container = await render(tester, spacer(expr: 'min(40, hp)'));
      container.read(gameStateProvider.notifier).setVariable('hp', 90);
      await tester.pump();
      expect(spacerHeight(tester), 40.0);

      container.read(gameStateProvider.notifier).setVariable('hp', 18);
      await tester.pump();
      expect(spacerHeight(tester), 18.0);
    });
  }, skip: _soPath == null);
}
