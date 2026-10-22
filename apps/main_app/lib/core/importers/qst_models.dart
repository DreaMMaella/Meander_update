/// Модели для формата URQ (.qst/.urq)
/// DOS URQ - формат текстовых квестов

/// Типы команд в URQ
enum QstCommandType {
  pln,      // Описание (plain text)
  btn,      // Кнопка с переходом
  inv,      // Инвентарь (inv+/inv-)
  goto,     // Переход
  ifn,      // Условие
  end,      // Конец ноды
  unknown,  // Неизвестная команда
}

/// Команда в нодe URQ
class QstCommand {
  final QstCommandType type;
  final String rawLine;
  final String? argument;      // Основной аргумент
  final String? extraArgument; // Дополнительный (для btn: текст кнопки)
  final String? condition;     // Для ifn: условие

  const QstCommand({
    required this.type,
    required this.rawLine,
    this.argument,
    this.extraArgument,
    this.condition,
  });

  @override
  String toString() => 'QstCommand(${type.name}, $rawLine)';
}

/// Нода в формате URQ
class QstNode {
  final String id;             // ID ноды (из :номер)
  final List<QstCommand> commands;
  final String? description;   // Первый pln текст
  
  const QstNode({
    required this.id,
    required this.commands,
    this.description,
  });

  /// Получить все кнопки
  List<QstCommand> get buttons => 
    commands.where((c) => c.type == QstCommandType.btn).toList();

  /// Получить все описания
  List<QstCommand> get descriptions => 
    commands.where((c) => c.type == QstCommandType.pln).toList();

  /// Получить все команды инвентаря
  List<QstCommand> get inventoryCommands => 
    commands.where((c) => c.type == QstCommandType.inv).toList();

  /// Получить goto команду
  QstCommand? get gotoCommand => 
    commands.where((c) => c.type == QstCommandType.goto).firstOrNull;

  /// Получить ifn команды
  List<QstCommand> get ifnCommands => 
    commands.where((c) => c.type == QstCommandType.ifn).toList();

  @override
  String toString() => 'QstNode($id, ${commands.length} commands)';
}

/// Распарсенный квест URQ
class QstQuest {
  final String title;
  final List<QstNode> nodes;
  final String? startNodeId;
  final Set<String> variables; // Все переменные из условий
  final Set<String> inventoryItems; // Все предметы инвентаря

  const QstQuest({
    required this.title,
    required this.nodes,
    this.startNodeId,
    required this.variables,
    required this.inventoryItems,
  });

  /// Найти ноду по ID
  QstNode? getNodeById(String id) {
    try {
      return nodes.firstWhere((n) => n.id == id);
    } catch (e) {
      return null;
    }
  }
}

/// Результат парсинга
class QstParseResult {
  final bool success;
  final QstQuest? quest;
  final String? error;
  final List<String> warnings;

  const QstParseResult({
    required this.success,
    this.quest,
    this.error,
    this.warnings = const [],
  });

  factory QstParseResult.success(QstQuest quest, {List<String>? warnings}) =>
    QstParseResult(
      success: true,
      quest: quest,
      warnings: warnings ?? const [],
    );

  factory QstParseResult.error(String error) =>
    QstParseResult(success: false, error: error);
}
