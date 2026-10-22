// Шит рамки закрепления: редактор обязан писать ровно то, что читает плеер.
// Проверяем три вещи — сетка позиций меняет только якоря (холст остаётся,
// иначе раскладка объектов уехала бы), поле «Ш» на схлопнутой оси — это
// размер холста, а выключенная модалка не оставляет затемнение в документе.

import 'package:canvas_app/features/editor/widgets/stack_pin_box_editor.dart';
import 'package:canvas_app/features/editor/widgets/stack_pin_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

const Size _viewport = Size(400, 800);

ContentItem _customStack({
  double? stackWidth,
  double? stackHeight,
  bool modal = false,
  double? scrim,
  bool? dismiss,
}) => ContentItem(
  id: 's1',
  type: 'stack',
  stackPin: 'custom',
  stackWidth: stackWidth,
  stackHeight: stackHeight,
  pinAnchorLeft: 0.25,
  pinAnchorTop: 0.5,
  pinAnchorRight: 0.25,
  pinAnchorBottom: 0.5,
  stackModal: modal ? true : null,
  stackScrim: scrim,
  stackDismissOnTapOutside: dismiss,
);

Future<void> _pump(
  WidgetTester tester,
  ContentItem stack,
  List<ContentItem> out,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 520,
            child: StackPinBoxEditor(
              stack: stack,
              viewport: _viewport,
              onChanged: out.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _commitField(WidgetTester tester, String key, String value) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('viewportOf — колонка до 720 и без системных вырезов', (
    tester,
  ) async {
    late Size result;
    final widget = Builder(
      builder: (context) {
        result = StackPinBoxEditor.viewportOf(context);
        return const SizedBox.shrink();
      },
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(900, 1000),
          padding: EdgeInsets.fromLTRB(0, 24, 0, 16),
        ),
        child: MaterialApp(home: Scaffold(body: widget)),
      ),
    );
    expect(result, const Size(720, 960));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 640)),
        child: MaterialApp(home: Scaffold(body: widget)),
      ),
    );
    expect(result, const Size(360, 640));
  });

  testWidgets('сетка позиций пишет якоря и оставляет холст в покое', (
    tester,
  ) async {
    final out = <ContentItem>[];
    await _pump(tester, _customStack(stackWidth: 300, stackHeight: 150), out);

    await tester.tap(find.byKey(const ValueKey('pin_pos_2_2')));
    await tester.pumpAndSettle();

    expect(out, hasLength(1));
    final next = out.single;
    expect(next.stackPin, 'custom');
    expect(next.pinAnchorLeft, 1.0);
    expect(next.pinAnchorTop, 1.0);
    expect(next.pinAnchorRight, 1.0);
    expect(next.pinAnchorBottom, 1.0);
    // Ключевое: холст не пересчитан — объекты внутри стека не разъедутся.
    expect(next.stackWidth, 300);
    expect(next.stackHeight, 150);
    // Правый нижний угол: рамка 300×? прижата к (400, 800).
    final rect = next.stackPinRect(_viewport);
    expect(rect.right, 400);
    expect(rect.bottom, 800);
  });

  testWidgets('превью показывает рамку в тех же px, что считает модель', (
    tester,
  ) async {
    final out = <ContentItem>[];
    await _pump(tester, _customStack(stackWidth: 300, stackHeight: 150), out);

    // Один холст без авторских размеров: превью и подпись обязаны совпасть.
    expect(find.textContaining('px экрана 400×800'), findsOneWidget);
    expect(find.text('300×150'), findsOneWidget);
    // Сам сбор виджета ничего не пишет — иначе каждый рефреш плодит шаг истории.
    expect(out, isEmpty);
  });

  testWidgets('поле Ш на схлопнутой оси — это ширина холста', (tester) async {
    final out = <ContentItem>[];
    await _pump(tester, _customStack(stackWidth: 300, stackHeight: 150), out);

    await _commitField(tester, 'pin_w', '200');
    expect(out.single.stackWidth, 200);
    expect(out.single.stackPinRect(_viewport).width, 200);
  });

  testWidgets('поле В на схлопнутой оси пишет холст в дизайн-px', (
    tester,
  ) async {
    final out = <ContentItem>[];
    // Холст 300×150 на рамке шириной 300 → масштаб 1, поле В = px экрана.
    await _pump(tester, _customStack(stackWidth: 300, stackHeight: 150), out);

    await _commitField(tester, 'pin_h', '240');
    expect(out.single.stackHeight, 240);
    expect(out.single.stackPinRect(_viewport).height, 240);
  });

  testWidgets('растянутая ось: Ш двигает границы, а не холст', (tester) async {
    final out = <ContentItem>[];
    final fill = ContentItem(
      id: 's3',
      type: 'stack',
      stackPin: 'fill',
      stackWidth: 640,
      stackHeight: 480,
    );
    await _pump(tester, fill, out);

    await _commitField(tester, 'pin_w', '300');
    final next = out.single;
    expect(next.stackWidth, 640, reason: 'холст растянутой оси не трогаем');
    expect(next.pinOffsetLeft, 0);
    expect(next.pinOffsetRight, -100);
    expect(next.stackPinRect(_viewport).width, 300);
  });

  testWidgets('растянуть по ширине: якоря к краям, вторая ось цела', (
    tester,
  ) async {
    final out = <ContentItem>[];
    await _pump(tester, _customStack(stackWidth: 300, stackHeight: 150), out);

    await tester.tap(find.text('Растянуть по ширине'));
    await tester.pumpAndSettle();

    final next = out.single;
    expect(next.pinAnchorLeft, 0.0);
    expect(next.pinAnchorRight, 1.0);
    expect(next.pinAnchorTop, 0.5);
    expect(next.pinAnchorBottom, 0.5);
    expect(next.stackPinStretchesWidth, isTrue);
    expect(next.stackPinStretchesHeight, isFalse);
    // Схлопнутая высота следует за масштабом рамки: пропорция холста держится.
    final rect = next.stackPinRect(_viewport);
    expect(rect.width, 400);
    expect(rect.height, closeTo(150 * 400 / 300, 1));
  });

  testWidgets('модалка: выключенное окно не оставляет затемнение', (
    tester,
  ) async {
    final out = <ContentItem>[];
    await _pump(
      tester,
      _customStack(modal: true, scrim: 0.3, dismiss: false),
      out,
    );

    expect(find.byKey(const ValueKey('pin_scrim')), findsOneWidget);
    await _commitField(tester, 'pin_scrim', '45');
    expect(out.last.stackScrim, closeTo(0.45, 1e-9));

    await _commitField(tester, 'pin_scrim', '140');
    expect(out.last.stackScrim, 1.0);

    await tester.tap(find.byKey(const ValueKey('pin_modal_switch')));
    await tester.pumpAndSettle();

    final off = out.last;
    expect(off.stackModal, isNull);
    expect(off.stackScrim, isNull);
    expect(off.stackDismissOnTapOutside, isNull);
    expect(off.isModalStack, isFalse);
    expect(off.stackScrimOpacity, 0.0);
  });

  testWidgets('тап вне закрывает — отдельное поле, модалка остаётся', (
    tester,
  ) async {
    final out = <ContentItem>[];
    await _pump(tester, _customStack(modal: true), out);

    await tester.tap(find.byKey(const ValueKey('pin_dismiss_switch')));
    await tester.pumpAndSettle();

    expect(out.last.stackDismissOnTapOutside, false);
    expect(out.last.stackModal, true);
    expect(out.last.stackDismissesOnTapOutside, false);
  });

  testWidgets('селектор позиции: восемь пресетов и «Рамка»', (tester) async {
    final picked = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: StackPinSelector(value: 'custom', onChanged: picked.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'В потоке',
      'Сверху',
      'Снизу',
      'Слева',
      'Справа',
      'Центр',
      'Экран',
      'Рамка',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(StackPinSelector.label('left'), 'у левого края');
    expect(StackPinSelector.label('right'), 'у правого края');
    expect(StackPinSelector.label('custom'), 'в своей рамке');

    await tester.tap(find.text('Слева'));
    await tester.pumpAndSettle();
    expect(picked, ['left']);
  });
}
