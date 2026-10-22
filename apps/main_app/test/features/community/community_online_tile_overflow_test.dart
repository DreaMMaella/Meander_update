import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/community/models/community_user_model.dart';
import 'package:canvas_app/features/community/screens/community_screen.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';

/// Ряд «Активны на этой неделе» зажат в `SizedBox(height: 108)`
/// (`_buildOnlineSection`), у плитки внутри паддинг 6 по вертикали —
/// значит на Column остаётся ровно 96 px. Это те самые ограничения
/// `BoxConstraints(w=72.0, h=96.0)` из crash_log.txt.
const double _rowHeight = 108;
const double _tileVerticalPadding = 6;
const double _columnBudget = _rowHeight - _tileVerticalPadding * 2;

/// Место, отведённое под аватар в сетке плитки: радиус 28 без рамки.
/// Рамка обязана съедать радиус, а не габарит — иначе её кольцо выталкивает
/// подпись за 96 px и Flutter рвёт ряд.
const double _avatarFootprint = 28 * 2;

/// Тики косметики выключены: `pumpAndSettle` на бесконечном тикере не
/// завершится, а нам важен сам факт отсутствия переполнения.
Widget _wrapRow(Widget child, {double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: true,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: SizedBox(height: _rowHeight, width: 80, child: child),
    ),
  ),
);

CommunityUser _wearing(String? frameId) => CommunityUser(
  id: 'u-1',
  fullName: 'Максимилиан Александрович',
  lastSeenAt: DateTime.now(),
  equipped: EquippedCosmetics(avatarFrame: frameId),
);

List<String> _allFrames() => kCosmetics
    .where((def) => def.slot == CosmeticSlot.avatarFrame)
    .map((def) => def.id)
    .toList();

void main() {
  group('плитка ленты «Активны на этой неделе»', () {
    testWidgets('тяжёлая рамка «Солнечная корона» не рвёт ряд', (tester) async {
      await tester.pumpWidget(_wrapRow(CommunityOnlineTile(user: _wearing('solar_corona'))));

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(CosmeticAvatar)).height,
        lessThanOrEqualTo(_avatarFootprint),
        reason: 'рамка выросла наружу и вытолкнула подпись из ряда',
      );
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(CommunityOnlineTile),
                matching: find.byType(Column),
              ),
            )
            .height,
        lessThanOrEqualTo(_columnBudget),
      );
    });

    testWidgets('ни одна рамка из каталога не выходит за высоту ряда', (tester) async {
      final frames = _allFrames();
      expect(frames, contains('solar_corona'), reason: 'каталог прочитан пусто');

      for (final id in frames) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_wrapRow(CommunityOnlineTile(user: _wearing(id))));
        final reason = 'рамка $id (outset ${avatarFrameOutset(cosmeticById(id))} px)';
        expect(tester.takeException(), isNull, reason: '$reason порвала ряд');
        expect(
          tester.getSize(find.byType(CosmeticAvatar)).height,
          lessThanOrEqualTo(_avatarFootprint),
          reason: '$reason выросла наружу вместо радиуса',
        );
      }
    });

    // Свалка Flexible: предельный системный шрифт должен резать подпись,
    // а не разрывать ряд.
    testWidgets('крупный системный шрифт режет подпись, а не ряд', (tester) async {
      await tester.pumpWidget(
        _wrapRow(
          CommunityOnlineTile(user: _wearing('solar_corona')),
          textScale: 2.0,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('без рамки ряд тоже в бюджете', (tester) async {
      await tester.pumpWidget(_wrapRow(CommunityOnlineTile(user: _wearing(null))));

      expect(tester.takeException(), isNull);
    });
  });
}
