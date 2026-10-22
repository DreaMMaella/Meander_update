/// Шина «контент квеста изменился».
///
/// Редактор вызывает [markChanged] после записи данных квеста на диск
/// (`nodes.json` / `config.json`), которые движок симуляции читает один раз
/// при создании и кеширует в памяти. Запущенные симуляции подписываются
/// через [listen] и перечитывают контент — live-обновление: движок
/// пересоздаётся, переменные/таблицы сессии сохраняются.
class QuestContentChangeBus {
  QuestContentChangeBus._();

  static final QuestContentChangeBus instance = QuestContentChangeBus._();

  final Map<String, int> _versions = {};
  final Map<String, List<void Function()>> _listeners = {};

  /// Текущая версия контента квеста (число изменений с момента первого).
  int versionOf(String questId) => _versions[questId] ?? 0;

  /// Отметить, что данные квеста изменились на диске. Уведомляет всех
  /// подписчиков этого квеста.
  void markChanged(String questId) {
    _versions[questId] = versionOf(questId) + 1;
    for (final listener in List.of(_listeners[questId] ?? const [])) {
      listener();
    }
  }

  /// Подписаться на изменения контента квеста. Возвращает функцию отписки.
  void Function() listen(String questId, void Function() listener) {
    _listeners.putIfAbsent(questId, () => []).add(listener);
    return () => unlisten(questId, listener);
  }

  void unlisten(String questId, void Function() listener) {
    final list = _listeners[questId];
    if (list == null) return;
    list.remove(listener);
    if (list.isEmpty) _listeners.remove(questId);
  }
}
