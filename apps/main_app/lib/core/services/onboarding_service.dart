import 'package:shared_preferences/shared_preferences.dart';

/// Сервис, отвечающий за хранение состояния обучающих сценариев.
///
/// Все флаги сохраняются в [SharedPreferences] и привязаны к устройству
/// (не к конкретному пользователю), чтобы один и тот же тур не показывался
/// повторно после перезапуска приложения.
class OnboardingService {
  OnboardingService._();

  // ---------------------------------------------------------------------------
  //  Ключи в SharedPreferences
  // ---------------------------------------------------------------------------

  /// Пользователь успешно прошёл обучение по созданию квеста (нажал «Готово»).
  static const String _kQuestCreationCompleted =
      'onboarding_quest_creation_completed';

  /// Пользователь явно нажал «Я уже знаю» (или закрыл туториал).
  static const String _kQuestCreationSkipped =
      'onboarding_quest_creation_skipped';

  /// Ответ новичка на финальном экране онбординга: `play` — пришёл проходить
  /// чужие квесты, `create` — пришёл делать свой. Пишется и читается напрямую
  /// через [SharedPreferences] — экран онбординга и оболочка уже держат prefs.
  static const String kIntentKey = 'onboarding_intent';

  static const String intentPlay = 'play';
  static const String intentCreate = 'create';

  // ---------------------------------------------------------------------------
  //  Создание квеста
  // ---------------------------------------------------------------------------

  /// Нужно ли показать обучение перед первым созданием квеста.
  ///
  /// Возвращает `true`, только если пользователь его ещё не проходил и
  /// не пропускал.
  static Future<bool> shouldShowQuestCreationTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_kQuestCreationCompleted) ?? false;
    final skipped = prefs.getBool(_kQuestCreationSkipped) ?? false;
    return !completed && !skipped;
  }

  /// Помечаем обучение как пройденное.
  static Future<void> markQuestCreationCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kQuestCreationCompleted, true);
  }

  /// Помечаем обучение как пропущенное.
  static Future<void> markQuestCreationSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kQuestCreationSkipped, true);
  }

  /// Сброс состояния — пригодится для повторного запуска обучения
  /// из настроек приложения.
  static Future<void> resetQuestCreationTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kQuestCreationCompleted);
    await prefs.remove(_kQuestCreationSkipped);
  }
}
