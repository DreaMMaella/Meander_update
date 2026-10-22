enum BackendType { local, vps }

class AppConfig {
  static const BackendType currentBackend = BackendType.vps;

  static const String vpsApiBaseUrl = 'https://backend.meander.sbs';
  static const String localApiBaseUrl = 'http://192.168.0.101:3000';

  static String get apiUrl {
    switch (currentBackend) {
      case BackendType.vps:
        return vpsApiBaseUrl;
      case BackendType.local:
        return localApiBaseUrl;
    }
  }
}
