/// Тип события, на которое подписан скрипт.
enum EventType {
  /// Событие «при запуске квеста»: вызывается один раз при начале новой игры,
  /// до первой ноды. Движок находит такие скрипты сам — среди файлов в
  /// каталоге `scripts/`, объявивших это событие.
  onQuestStart,
  onNodeEnter,
  onPress,
  onContentAppear,
  function,
  /// Событие «При изменении данных»: движок сам находит такие блоки среди
  /// скриптов квеста (`scripts/`) и текущей ноды, следит за путями из поля
  /// `watchPaths` и запускает обработчик на границе игрового шага.
  /// В `_changed_path`/`_changed_paths` — что именно изменилось.
  onDataChange,
}

/// Таблица квеста (ключ-значение) видимая скриптам.
abstract class ScriptTable {
  Map<String, dynamic> get data;
}

/// Состояние выполнения скриптов: переменные и таблицы.
///
/// Контракт намеренно минимальный — конкретная реализация
/// (`InMemoryScriptRuntimeState`) лежит в `mnd_core/runtime/`.
abstract class ScriptRuntimeState {
  Map<String, dynamic> get allVariables;
  Map<String, ScriptTable> get allTables;

  void setVariable(String name, dynamic value);
  dynamic getVariable(String name);

  void setTable(String tableName, ScriptTable table);
  ScriptTable? getTable(String tableName);
}
