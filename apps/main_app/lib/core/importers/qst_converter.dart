/// Конвертер из формата URQ (.qst) в формат Meander
/// 
/// Преобразует:
/// - QstQuest → QuestDescriptor + List<SavedNode>
/// - Ноды URQ → Ноды Meander с ContentItem
/// - Команды URQ → Visual Script блоки

import 'package:uuid/uuid.dart';
import 'package:mnd_core/models/quest_descriptor.dart';
import 'package:mnd_core/models/saved_node.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/script_contracts.dart';
import 'package:mnd_core/contracts/script_runtime.dart' show EventType;
import 'qst_models.dart';

class QstToMeanderConverter {
  final _uuid = const Uuid();
  
  /// Конвертировать квест URQ в структуру Meander
  MeanderQuestData convert(QstQuest qstQuest) {
    // Создаём маппинг ID сначала
    final nodeMap = <String, String>{}; // URQ ID → Meander ID
    for (final qstNode in qstQuest.nodes) {
      nodeMap[qstNode.id] = _uuid.v4();
    }
    
    // Получаем Meander ID для стартовой ноды
    final startMeanderId = nodeMap[qstQuest.startNodeId ?? qstQuest.nodes.first.id];
    
    // Создаём дескриптор квеста сразу со startNodeId
    final questDescriptor = Quest(
      id: _uuid.v4(),
      title: qstQuest.title,
      description: trf('Конвертировано из URQ: {p0}', {'p0': qstQuest.title}),
      startNodeId: startMeanderId,
      scriptEngineMode: kScriptEngineModeNew,
    );

    // Конвертируем ноды
    final nodes = <SavedNode>[];
    final scripts = <String, dynamic>{};

    for (final qstNode in qstQuest.nodes) {
      final nodeId = nodeMap[qstNode.id]!;
      final scriptData = _createNodeScript(qstNode, nodeMap, qstQuest);
      if (scriptData != null) {
        // Канонический каталог скриптов: его знают редактор, движок и клинер.
        // Путь относительно корня квеста (совпадает с scriptAssetId).
        scripts['scripts/$nodeId.json'] = scriptData;
      }
      nodes.add(_convertNode(qstNode, nodeId, nodeMap, scriptData != null));
    }

    return MeanderQuestData(
      quest: questDescriptor,
      nodes: nodes,
      variables: qstQuest.variables.toList(),
      inventoryItems: qstQuest.inventoryItems.toList(),
      scripts: scripts,
    );
  }

  /// Конвертировать ноду URQ в ноду Meander
  SavedNode _convertNode(
    QstNode qstNode,
    String nodeId,
    Map<String, String> nodeMap,
    bool hasScript,
  ) {
    final contentItems = <ContentItem>[];

    // Добавляем описания как text content
    for (final desc in qstNode.descriptions) {
      if (desc.argument != null && desc.argument!.isNotEmpty) {
        contentItems.add(ContentItem(
          id: _uuid.v4(),
          type: 'text',
          contentMarkdown: desc.argument,
          flex: 1,
        ));
      }
    }

    // Добавляем кнопки
    final buttons = _createButtons(qstNode, nodeMap);
    contentItems.addAll(buttons);

    return SavedNode(
      id: nodeMap[qstNode.id]!,
      chapterId: '', // Будет установлен позже
      title: trf('Нода {p0}', {'p0': qstNode.id}),
      content: {
        'items': contentItems.map((c) => c.toJson()).toList(),
      },
      x: 0,
      y: 0,
      scriptAssetId: hasScript ? 'scripts/$nodeId.json' : null,
    );
  }

  /// Создать кнопки для ноды
  List<ContentItem> _createButtons(
    QstNode qstNode,
    Map<String, String> nodeMap,
  ) {
    final buttons = <ContentItem>[];
    final regularButtons = qstNode.buttons.where((b) => 
      b.condition == null
    ).toList();

    // Обычные кнопки
    for (final btn in regularButtons) {
      final targetId = btn.argument;
      String? targetNodeId;
      
      if (targetId != null && nodeMap.containsKey(targetId)) {
        targetNodeId = nodeMap[targetId];
      }

      buttons.add(ContentItem(
        id: _uuid.v4(),
        type: 'button',
        buttonText: btn.extraArgument ?? 'Кнопка',
        targetNodeId: targetNodeId,
        flex: 1,
      ));
    }

    // Кнопки с условиями (ifn)
    for (final ifn in qstNode.ifnCommands) {
      if (ifn.argument != null) {
        final targetId = ifn.argument;
        String? targetNodeId;
        
        if (targetId != null && nodeMap.containsKey(targetId)) {
          targetNodeId = nodeMap[targetId];
        }

        buttons.add(ContentItem(
          id: _uuid.v4(),
          type: 'button',
          buttonText: ifn.extraArgument ?? 'Кнопка',
          targetNodeId: targetNodeId,
          flex: 1,
        ));
      }
    }

    return buttons;
  }

  /// Создать скрипт для ноды.
  ///
  /// Генерирует блоки ТОЛЬКО типов, понятных движку (см. listBlockTypes):
  /// assign_variable / condition / go_to_node, обёрнутые в event
  /// onNodeEnter — без event-обёртки исполнитель скриптов блоки не видит,
  /// а чужие типы ('action' и пр.) парсер роняет в UnknownBlock.
  Map<String, dynamic>? _createNodeScript(
    QstNode qstNode,
    Map<String, String> nodeMap,
    QstQuest quest,
  ) {
    final children = <Map<String, dynamic>>[];

    // Инвентарь URQ -> переменные `инвентарь_<предмет>`: 1/0.
    for (final invCmd in qstNode.inventoryCommands) {
      final itemName = invCmd.argument;
      if (itemName == null || itemName.trim().isEmpty) continue;
      final isAdd = invCmd.extraArgument == 'add';
      children.add({
        'id': _uuid.v4(),
        'type': BlockTypes.assignVariable,
        'variable': 'инвентарь_${itemName.trim()}',
        'value': isAdd ? '1' : '0',
      });
    }

    // Условия ifn: переход при истинности.
    for (final ifn in qstNode.ifnCommands) {
      final targetId = ifn.argument;
      final condition = ifn.condition;
      if (targetId == null || condition == null) continue;
      final targetNodeId = nodeMap[targetId];
      if (targetNodeId == null) continue;

      children.add({
        'id': _uuid.v4(),
        'type': BlockTypes.condition,
        'expression': _conditionExpression(condition),
        'then_blocks': [
          {'id': _uuid.v4(), 'type': BlockTypes.goToNode, 'node_id': targetNodeId},
        ],
        'else_blocks': <Map<String, dynamic>>[],
      });
    }

    // Безусловный goto — только если больше нечего делать.
    final gotoCmd = qstNode.gotoCommand;
    if (gotoCmd != null && gotoCmd.argument != null && children.isEmpty) {
      final targetNodeId = nodeMap[gotoCmd.argument];
      if (targetNodeId != null) {
        children.add({
          'id': _uuid.v4(),
          'type': BlockTypes.goToNode,
          'node_id': targetNodeId,
        });
      }
    }

    if (children.isEmpty) return null;

    return {
      'name': 'Script for node ${qstNode.id}',
      'blocks': [
        {
          'id': _uuid.v4(),
          'type': BlockTypes.event,
          'eventType': EventType.onNodeEnter.name,
          'children': children,
          'collapsed': false,
        }
      ],
      'version': '1.0',
    };
  }

  /// URQ-условие (`if x=1 then`, `if not x then`) -> выражение движка.
  /// Отрицание уходит в оператор сравнения: унарный `!` не используем.
  String _conditionExpression(String condition) {
    final neg = condition.toLowerCase().startsWith('not ');
    final clean = neg ? condition.substring(4).trim() : condition;

    if (clean.contains('=')) {
      final eq = clean.indexOf('=');
      var left = clean.substring(0, eq).trim();
      var right = clean.substring(eq + 1).trim();
      if (right.startsWith('=')) right = right.substring(1).trim();
      return '{$left} ${neg ? '!=' : '=='} ${_literalOrString(right)}';
    }
    return neg ? '{$clean} == false' : '{$clean}';
  }

  /// Числа и ссылки на переменные — как есть, остальное — строка в кавычках.
  String _literalOrString(String value) {
    final isNumeric = num.tryParse(value) != null;
    final isVarRef = value.startsWith('{') && value.endsWith('}');
    final alreadyQuoted = value.startsWith("'") || value.startsWith('"');
    if (isNumeric || isVarRef || alreadyQuoted) return value;
    return "'$value'";
  }
}


class MeanderQuestData {
  final Quest quest;
  final List<SavedNode> nodes;
  final List<String> variables;
  final List<String> inventoryItems;

  /// Сгенерированные скрипты: путь относительно квеста → JSON скрипта.
  final Map<String, dynamic> scripts;

  const MeanderQuestData({
    required this.quest,
    required this.nodes,
    required this.variables,
    required this.inventoryItems,
    this.scripts = const {},
  });

  /// Сериализовать в JSON для сохранения
  Map<String, dynamic> toJson() => {
    'quest': quest.toJson(),
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'variables': variables,
    'inventoryItems': inventoryItems,
  };
}
