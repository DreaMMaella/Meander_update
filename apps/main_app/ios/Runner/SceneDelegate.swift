import Flutter
import UIKit
import yandex_login_sdk

/// Класс прописан в Info.plist как `UISceneDelegateClassName`. iOS 27 роняет
/// приложение на старте, если жизненный цикл сцен не объявлен вообще
/// (`EXC_BREAKPOINT` в `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`).
class SceneDelegate: FlutterSceneDelegate {
  /// Yandex Login возвращается либо по URL-схеме `yx…`, либо по универсальной
  /// ссылке, и сам умеет принимать только `application(_:open:)` — под
  /// сценным жизненным циклом UIKit его не вызывает, нужен перенаправитель.
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    let unhandled = URLContexts.filter {
      !YandexLoginSdkPlugin.handle(openURL: $0.url)
    }
    if !unhandled.isEmpty {
      // Остальное (supabase-колбэк, universal links) забирают плагины,
      // зарегистрированные через `addSceneDelegate`.
      super.scene(scene, openURLContexts: unhandled)
    }
  }
}
