import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/services/hang_watchdog.dart';

/// Сторож отличает настоящее зависание UI от сна системы по паре шкал:
/// стеновые часы (штамп heartbeat) и монотонные часы самого сторожа.
void main() {
  group('HangWatchdog.isRealStall', () {
    test('зависание: обе шкалы ушли вперёд одинаково', () {
      const nineHoursMs = 9 * 3600 * 1000;
      expect(
        HangWatchdog.isRealStall(wallGapMs: nineHoursMs, monoGapMs: nineHoursMs),
        isTrue,
      );
    });

    test('пробуждение после ночного сна: стена ушла, монотонные часы стояли', () {
      expect(
        HangWatchdog.isRealStall(wallGapMs: 9 * 3600 * 1000, monoGapMs: 120),
        isFalse,
      );
    });

    test('короткая заморозка процесса в пределах допуска — ещё зависание', () {
      expect(
        HangWatchdog.isRealStall(
          wallGapMs: HangWatchdog.sleepDriftToleranceMs,
          monoGapMs: 0,
        ),
        isTrue,
      );
    });

    test('дрейф за допуском — процесс спал, вешать alarm на него нельзя', () {
      expect(
        HangWatchdog.isRealStall(
          wallGapMs: HangWatchdog.sleepDriftToleranceMs + 1,
          monoGapMs: 0,
        ),
        isFalse,
      );
    });

    test('штатный таймаут при живом процессе всегда сигналит', () {
      expect(
        HangWatchdog.isRealStall(
          wallGapMs: HangWatchdog.stallTimeout.inMilliseconds,
          monoGapMs: HangWatchdog.stallTimeout.inMilliseconds,
        ),
        isTrue,
      );
    });
  });
}
