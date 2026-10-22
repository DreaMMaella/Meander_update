import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/utils/platform_performance.dart';

/// Порог, по которому плеер решает, рисовать ли размытие фона.
///
/// НЕГАТИВНЫЙ КОНТРОЛЬ (#223): до фикса `shouldDisableBackgroundBlur` возвращал
/// `true` для `Platform.isAndroid` целиком, а «память не определилась» тоже
/// считалось запретом. Итог — на телефоне не размывалось ни фото, ни видео,
/// причём молча: у настройки `disable_blur_effects` нет ни одного места в UI,
/// где её включают обратно. Если заменить тело функции на `return true`,
/// падают кейсы «размытие разрешено»; на `return false` — кейс «слабое
/// устройство бережём». А если вернуть платформенные ветки — падает
/// проверка, что гейт смотрит только в память.
void main() {
  const gb = 1024 * 1024 * 1024;

  group('backgroundBlurDisabledForMemory', () {
    test('4 ГБ и больше — размытие разрешено', () {
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(4 * gb), isFalse);
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(6 * gb), isFalse);
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(8 * gb), isFalse);
    });

    test('меньше 4 ГБ — режем (устройства, где offscreen-слой виден в FPS)', () {
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(3 * gb), isTrue);
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(2 * gb), isTrue);
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(1 * gb), isTrue);
    });

    test('граница порога строгая: 4 ГБ ровно — уже можно', () {
      expect(
        PlatformPerformance.backgroundBlurDisabledForMemory(4 * gb - 1),
        isTrue,
      );
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(4 * gb), isFalse);
    });

    test('память не определилась — НЕ режем: авторское размытие важнее', () {
      // Десктоп (Linux, Windows) отвечает 0 всегда — там размытие и так было.
      // Телефон без доступного /proc/meminfo тоже 0: выключить эффект у всех,
      // кого не удалось измерить, — это ровно тот баг, который чиним.
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(0), isFalse);
      expect(PlatformPerformance.backgroundBlurDisabledForMemory(-1), isFalse);
    });
  });

  group('shouldDisableBackgroundBlur не знает о платформах', () {
    test('в теле гейта нет ветки по Platform — только память и настройка', () {
      final file = File('lib/utils/platform_performance.dart');
      if (!file.existsSync()) {
        markTestSkipped('platform_performance.dart не найден');
        return;
      }
      final source = file.readAsStringSync();
      final at = source.indexOf('Future<bool> shouldDisableBackgroundBlur');
      expect(at, greaterThan(-1), reason: 'гейт не найден');
      final open = source.indexOf('{', at);
      var depth = 0;
      var end = open;
      for (var i = open; i < source.length; i++) {
        if (source[i] == '{') {
          depth++;
        } else if (source[i] == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      final body = source.substring(open, end + 1);
      expect(
        body,
        isNot(contains('Platform.is')),
        reason:
            'запрет по имени платформы (#223) выключает авторский эффект молча',
      );
      expect(body, contains('backgroundBlurDisabledForMemory'));
    });
  });
}
