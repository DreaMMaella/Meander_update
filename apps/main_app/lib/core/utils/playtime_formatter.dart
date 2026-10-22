import 'package:canvas_app/core/l10n/l10n.dart';

class PlaytimeFormatter {
  /// Часы берут с сервера; локальное значение этого устройства — только
  /// подстраховка, когда серверу ещё нечего показать (свежий аккаунт,
  /// офлайн). Наоборот быть не должно: локальный счётчик живёт до первого
  /// сброса приложения, и на втором компьютере профиль выглядел бы так,
  /// будто человек ни разу не играл.
  static int serverFirst(int serverSeconds, int localSeconds) =>
      serverSeconds > 0 ? serverSeconds : localSeconds;

  static String format(int totalSeconds) {
    if (totalSeconds <= 0) return tr('0 мин.');
    if (totalSeconds < 60) return tr('< 1 мин.');
    
    final minutes = totalSeconds ~/ 60;
    if (minutes < 60) return trf('{n} мин.', {'n': minutes});
    
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    
    if (remainingMinutes == 0) return trf('{n} ч.', {'n': hours});
    return trf('{h} ч. {m} мин.', {'h': hours, 'm': remainingMinutes});
  }
}
