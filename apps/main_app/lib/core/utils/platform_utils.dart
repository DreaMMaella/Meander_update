// lib/core/utils/platform_utils.dart

import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';

/// Утилита для получения уникальных и трудно подделываемых данных о приложении.
class PlatformUtils {
  /// Возвращает уникальный и стабильный идентификатор подписи/установки приложения.
  /// Этот идентификатор используется как компонент для генерации ключа шифрования.
  static Future<String> getAppIdentifier() async {
    final packageInfo = await PackageInfo.fromPlatform();

    if (Platform.isAndroid) {
      // На Android `buildSignature` представляет собой хэш SHA-256
      // сертификата, которым подписано приложение.
      // Это идеальный идентификатор: он не меняется при обновлениях,
      // но гарантированно изменится, если APK будет переподписан (например, в моде).
      // Важно: для отладки и релиза используются разные подписи!
      // Наш сервис использует релизную подпись, поэтому моды,
      // собранные с debug-ключом, также будут заблокированы.
      return packageInfo.buildSignature;
    } else if (Platform.isIOS) {
      // На iOS нет простого API для получения хэша подписи из Dart.
      // В качестве надежной альтернативы мы используем связку из
      // идентификатора пакета (bundleId) и номера сборки.
      // Это не так надежно, как хэш подписи, но все равно создает
      // серьезное препятствие для простого копирования и модификации.
      return "${packageInfo.packageName}:${packageInfo.buildNumber}";
    }

    // Если приложение запускается на другой платформе (Web, Desktop),
    // выбрасываем ошибку, так как для них не определена стратегия безопасности.
    throw UnsupportedError(
      'Платформа не поддерживается для данной схемы безопасности.',
    );
  }

  /// Возвращает имя пакета приложения (например, com.example.meander_app).
  /// Используется как дополнительный компонент для генерации ключа.
  static Future<String> getPackageName() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.packageName;
  }
}
