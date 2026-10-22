import 'package:flutter/widgets.dart';
import 'package:mnd_player/providers/game_screen_provider.dart'
    show GameSessionKey;

/// Сессия игрового экрана, доступная нижележащим виджетам (HUD, контент,
/// таймер). Несёт [GameSessionKey] — единый ключ провайдера `gameScreenProvider`,
/// чтобы все виджеты внутри экрана обращались к тому же движку/нотификатору,
/// что и сам экран (исключает рассинхрон «экран vs виджеты»).
class GameSessionScope extends InheritedWidget {
  final GameSessionKey sessionKey;

  const GameSessionScope({
    super.key,
    required this.sessionKey,
    required super.child,
  });

  static GameSessionKey? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<GameSessionScope>()
        ?.sessionKey;
  }

  /// Ключ сессии для виджетов вне экрана (или до его построения):
  /// берём из [GameSessionScope], если он есть, иначе — standalone-ключ.
  static GameSessionKey of(BuildContext context, String questId) {
    return maybeOf(context) ?? (questId: questId, docKey: 'standalone');
  }

  @override
  bool updateShouldNotify(GameSessionScope oldWidget) =>
      oldWidget.sessionKey != sessionKey;
}
