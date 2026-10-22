import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mnd_player/utils/device_memory.dart';

class PlatformPerformance {
  static PlatformPerformance? _instance;
  static PlatformPerformance get instance {
    _instance ??= PlatformPerformance._();
    return _instance!;
  }

  PlatformPerformance._();

  bool? _shouldDisableBlur;
  bool? _userPreference;

  Future<bool> shouldDisableBlur() async {
    if (_userPreference != null) {
      return _userPreference!;
    }

    if (_shouldDisableBlur != null) {
      return _shouldDisableBlur!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('disable_blur_effects');
      if (saved != null) {
        _userPreference = saved;
        return saved;
      }
    } catch (_) {}

    _shouldDisableBlur = _detectShouldDisableBlur();
    return _shouldDisableBlur!;
  }

  /// Размытие ФОНА (статичной картинки за контентом).
  ///
  /// Отдельно от [shouldDisableBlur], потому что `shouldDisableBlur` режет всё
  /// тяжёлое разом — `BackdropFilter` шапки, дорогие переходы нод, размытие
  /// видео-текстуры — и на Linux возвращает true. Из-за этого авторское
  /// размытие фона не работало вообще ни на одном десктопе, хотя один
  /// `ImageFiltered` по статичной картинке стоит одна перерисовка и обходится
  /// дешевле, чем непрозрачный фоллбэк шапки. Здесь резаем только по реальной
  /// памяти устройства ([backgroundBlurDisabledForMemory]); настройка
  /// пользователя (`disable_blur_effects`) важнее автодетекта.
  Future<bool> shouldDisableBackgroundBlur() async {
    if (_userPreference != null) {
      return _userPreference!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('disable_blur_effects');
      if (saved != null) {
        _userPreference = saved;
        return saved;
      }
    } catch (_) {}

    if (kIsWeb) return false;
    return backgroundBlurDisabledForMemory(physicalMemoryBytes());
  }

  /// Резать ли размытие фона по объёму памяти устройства.
  ///
  /// Запрет «всем Android» и «всем iOS» (#223) ломал авторский замысел молча:
  /// у настройки `disable_blur_effects` нет ни одного места, где её включают
  /// обратно, поэтому платформенный запрет был не «режим экономии», а просто
  /// выключенным эффектом — и на телефоне не размывалось ни фото, ни видео.
  /// Теперь режем только то, что реально не тянет: одна `ImageFiltered` по
  /// статичной картинке и один mpv-фильтр по фоновому видео стоят дешёвого
  /// offscreen-пасса, а 4 ГБ — граница между устройствами, где это заметно в
  /// FPS, и где нет.
  ///
  /// Ноль и меньше — память не определилась. Тогда НЕ режем: десктоп (Linux,
  /// Windows) всегда отвечает 0, а на телефоне без `/proc/meminfo` лучше
  /// вернуть авторское размытие, чем снова выключить его у всех.
  /// Чистая функция — порог проверяется тестом без устройства.
  static bool backgroundBlurDisabledForMemory(int totalPhysicalMemoryBytes) {
    const fourGb = 4 * 1024 * 1024 * 1024;
    if (totalPhysicalMemoryBytes <= 0) return false;
    return totalPhysicalMemoryBytes < fourGb;
  }

  bool _detectShouldDisableBlur() {
    if (kIsWeb) return false;

    if (Platform.isLinux) {
      if (kDebugMode) {
        print(
          '🐧 [Performance] Linux detected - blur may cause performance issues',
        );
      }
      return true;
    }

    // BackdropFilter на Android — покадровое чтение буфера поверх
    // анимированного фона/видео: заметно просаживает FPS. Отключаем по
    // умолчанию; вызывающие виджеты (AppBar, GlassSurface) рисуют fallback
    // — градиент/более непрозрачный фон.
    if (Platform.isAndroid) {
      return true;
    }

    if (Platform.isWindows) {
      return false;
    }

    return false;
  }

  Future<void> setBlurEnabled(bool enabled) async {
    _userPreference = !enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('disable_blur_effects', !enabled);
    } catch (_) {}
  }

  Future<double> getOptimalBlurSigma(double requestedSigma) async {
    if (await shouldDisableBlur()) {
      return 0.0;
    }

    if (!kIsWeb && Platform.isLinux) {
      return requestedSigma / 2;
    }

    return requestedSigma;
  }

  Future<bool> shouldUseShadows() async {
    if (await shouldDisableBlur()) {
      return false;
    }
    return true;
  }

  int getTargetFPS() {
    if (kIsWeb) return 60;
    if (!kIsWeb && Platform.isLinux) return 60;
    return 60;
  }

  String getPlatformInfo() {
    if (kIsWeb) return 'Web';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }
}
