import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/widgets/items/game_stack_widget.dart';
import 'package:mnd_player/widgets/pinned_stack_layer.dart';

/// Слой закреплённого стека: рамка на экране, заглушка модалки и закрытие по
/// тапу вне. Движок здесь ни при чём — проверяется чистая геометрия и ввод.
void main() {
  const viewport = Size(400, 800);
  const boxKey = Key('box');
  const underKey = Key('under');

  Widget wrap(
    ContentItem item, {
    Offset offset = Offset.zero,
    VoidCallback? onDismiss,
    VoidCallback? onUnderTap,
  }) {
    // Провайдер нужен слою: решение о стекле модалки он принимает по тому же
    // состоянию, по которому плеер гасит содержимое окна.
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: underKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: onUnderTap,
                  child: const ColoredBox(color: Color(0xFF112233)),
                ),
              ),
              Positioned.fill(
                child: PinnedStackLayer(
                  item: item,
                  viewport: viewport,
                  offset: offset,
                  onDismiss: onDismiss,
                  child: const ColoredBox(
                    key: boxKey,
                    color: Color(0xFF00FF00),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ContentItem stack({
    String pin = 'center',
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? offsetLeft,
    bool? modal,
    double? scrim,
    bool? dismissOutside,
  }) => ContentItem(
    id: 's1',
    type: 'stack',
    stackPin: pin,
    stackWidth: 290,
    stackHeight: 300,
    pinAnchorLeft: left,
    pinAnchorTop: top,
    pinAnchorRight: right,
    pinAnchorBottom: bottom,
    pinOffsetLeft: offsetLeft,
    stackModal: modal,
    stackScrim: scrim,
    stackDismissOnTapOutside: dismissOutside,
  );

  testWidgets('рамка по легаси-ярлыку: колонка у левого края', (tester) async {
    await tester.pumpWidget(wrap(stack(pin: 'left')));
    // 290×300 авторских px, по вертикали — по центру вьюпорта.
    expect(
      tester.getRect(find.byKey(boxKey)),
      const Rect.fromLTRB(0, 250, 290, 550),
    );
  });

  testWidgets('ряд из двух закреплённых стеков: половина экрана каждому', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(stack(pin: 'custom', left: 0, top: 0, right: 0.5, bottom: 1)),
    );
    expect(
      tester.getRect(find.byKey(boxKey)),
      const Rect.fromLTRB(0, 0, 200, 800),
    );
  });

  testWidgets('сдвиг на колонку 720 на широком окне учитывается', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(stack(pin: 'left'), offset: const Offset(100, 0)),
    );
    expect(
      tester.getRect(find.byKey(boxKey)),
      const Rect.fromLTRB(100, 250, 390, 550),
    );
  });

  testWidgets('немодальный слой не перекрывает ноду под собой', (tester) async {
    var underTaps = 0;
    await tester.pumpWidget(
      wrap(stack(pin: 'center'), onUnderTap: () => underTaps++),
    );
    // Мимо рамки — тап достаёт до ноды.
    await tester.tapAt(const Offset(5, 5));
    expect(underTaps, 1);
    // Внутри рамки — нет: стек ловит ввод сам.
    await tester.tapAt(const Offset(200, 400));
    expect(underTaps, 1);
  });

  testWidgets('модалка затемняет и не пускает тап к ноде', (tester) async {
    var underTaps = 0;
    await tester.pumpWidget(
      wrap(stack(pin: 'center', modal: true), onUnderTap: () => underTaps++),
    );
    final scrim = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(PinnedStackLayer),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(scrim.color, Color.fromRGBO(0, 0, 0, kStackModalScrimDefault));
    expect(scrim.color.alpha, greaterThan(0));
    expect(scrim.color.alpha, lessThan(255));

    await tester.tapAt(const Offset(5, 5));
    expect(underTaps, 0, reason: 'окно обязано перехватить тап мимо рамки');
  });

  testWidgets('тап вне окна закрывает его, тап внутри — нет', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(
      wrap(stack(pin: 'center', modal: true), onDismiss: () => dismissed++),
    );
    await tester.tapAt(const Offset(5, 5));
    expect(dismissed, 1);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    expect(dismissed, 1, reason: 'внутри окна заглушки нет');
  });

  testWidgets('запрет закрытия по тапу вне: окно держится, но блокирует', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      wrap(
        stack(pin: 'center', modal: true, dismissOutside: false),
        onDismiss: () => dismissed++,
      ),
    );
    await tester.tapAt(const Offset(5, 5));
    expect(dismissed, 0);
  });

  testWidgets('scrim = 0: заглушка прозрачна, но ввод всё равно перехвачен', (
    tester,
  ) async {
    var underTaps = 0;
    await tester.pumpWidget(
      wrap(
        stack(pin: 'center', modal: true, scrim: 0),
        onUnderTap: () => underTaps++,
      ),
    );
    await tester.tapAt(const Offset(5, 5));
    expect(underTaps, 0);
  });

  testWidgets('рамка и холст сходятся: полоса на всю ширину не плющит', (
    tester,
  ) async {
    // Растянутая по X рамка (0..1) со схлопнутой высотой: холст 200×300 в
    // px дизайна, экран 400 ⇒ масштаб 2 ⇒ и рамка, и нарисованный стек
    // обязаны быть 400×600. До связки рамки с масштабом стек получал рамку
    // 400×300 и FittedBox растягивал картинку по вертикали вдвое.
    final band = ContentItem(
      id: 's1',
      type: 'stack',
      stackPin: 'custom',
      pinAnchorLeft: 0,
      pinAnchorRight: 1,
      pinAnchorTop: 0.5,
      pinAnchorBottom: 0.5,
      stackWidth: 200,
      stackHeight: 300,
      children: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: PinnedStackLayer(
                      item: band,
                      viewport: viewport,
                      child: GameStackWidget(
                        item: band,
                        questId: 'q1',
                        onInteract: (_) {},
                        onInputSubmitted: (_, __) {},
                        onComplete: () {},
                        onTransition: (_) {},
                        onNavigateToNode: (_) {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byType(GameStackWidget)),
      const Rect.fromLTRB(0, 100, 400, 700),
      reason: 'рамка = нарисованный холст, иначе FittedBox плющит картинку',
    );
  });
}
