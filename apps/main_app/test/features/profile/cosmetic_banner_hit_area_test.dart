import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';

/// Старая раскладка: обложка 160, аватар висит на `bottom: -38`, зазор до
/// имени 46. Кнопка рисуется на y≈183 — вне бокса обложки, тап не долетает.
const double _oldReserve = 0;
const double _oldAvatarBottom = -38;
const double _oldGap = 46;

/// Новая: те же 38 px свеса забраны в бокс обложки, аватар прижат к её нижнему
/// краю, зазор до имени на столько же меньше.
const double _newReserve = 38;
const double _newAvatarBottom = 0;
const double _newGap = 8;

/// Аватар свисает с нижнего края обложки, и кнопка «сменить аватар» стоит на
/// самом его низу. Отрисовка Stack'а не обрезается, а тап — проверяется по
/// границам бокса, поэтому без `CosmeticBanner.hitReserve` по этой кнопке
/// было невозможно попасть: она видимая, мёртвая, и ничего не происходит.
Widget _host({
  required double hitReserve,
  required double avatarBottom,
  required double gap,
  required VoidCallback onTap,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 390,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CosmeticBanner(
              def: null,
              height: 160,
              hitReserve: hitReserve,
              forceStatic: true,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 20,
                    bottom: avatarBottom,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: const BoxDecoration(
                            color: Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: GestureDetector(
                            onTap: onTap,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_a_photo,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: gap),
            const Text('Имя'),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'камера на свисающем аватаре ловит тап, если бокс резервирует свес',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          hitReserve: _newReserve,
          avatarBottom: _newAvatarBottom,
          gap: _newGap,
          onTap: () => taps++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_a_photo));
      await tester.pump();
      expect(taps, 1);
    },
  );

  testWidgets('без резерва тап по той же кнопке не долетает — в этом и баг', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        hitReserve: _oldReserve,
        avatarBottom: _oldAvatarBottom,
        gap: _oldGap,
        onTap: () => taps++,
      ),
    );
    await tester.pumpAndSettle();

    // warnIfMissed: false — кнопка действительно рисуется вне бокса,
    // и это ровно то, что проверяем.
    await tester.tap(find.byIcon(Icons.add_a_photo), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('резерв не сдвигает ни аватар, ни имя под обложкой', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        hitReserve: _oldReserve,
        avatarBottom: _oldAvatarBottom,
        gap: _oldGap,
        onTap: () {},
      ),
    );
    await tester.pumpAndSettle();
    final badge = tester.getRect(find.byIcon(Icons.add_a_photo));
    final name = tester.getRect(find.text('Имя'));

    await tester.pumpWidget(
      _host(
        hitReserve: _newReserve,
        avatarBottom: _newAvatarBottom,
        gap: _newGap,
        onTap: () {},
      ),
    );
    await tester.pumpAndSettle();

    // Кнопка там же: меняются только границы области попаданий.
    expect(tester.getRect(find.byIcon(Icons.add_a_photo)), badge);
    // …и имя под обложкой тоже: 38 px ушли из зазора в бокс.
    expect(tester.getRect(find.text('Имя')), name);
  });
}
