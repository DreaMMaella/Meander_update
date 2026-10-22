/// OAuth-учётные данные, задаваемые при сборке.
///
/// Значения приходят из `.env` через
/// `flutter build ... --dart-define-from-file=.env`; в репозитории их нет.
/// Пустая строка означает, что провайдер в этой сборке не настроен.
class OAuthConfig {
  static const String googleDesktopClientId =
      String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const String googleDesktopClientSecret =
      String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');
  static const String googleMobileServerClientId =
      String.fromEnvironment('GOOGLE_MOBILE_SERVER_CLIENT_ID');
  static const String yandexClientId =
      String.fromEnvironment('YANDEX_CLIENT_ID');
  static const String telegramClientId =
      String.fromEnvironment('TELEGRAM_CLIENT_ID');
}
