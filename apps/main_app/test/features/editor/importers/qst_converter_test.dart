import 'package:canvas_app/core/importers/qst_converter.dart';
import 'package:canvas_app/core/importers/qst_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/parser.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
//  URQ-импорт обязан давать ИСПОЛНЯЕМЫЕ скрипты:
//  1. Только реальные типы блоков движка (регрессия: type:'action' с полями
//     action/trueNodeId не понимал ни один парсер).
//  2. Event-обёртка onNodeEnter — без неё исполнитель блоки не видит.
//  3. Скрипты попадают в MeanderQuestData.scripts и пишутся на диск
//     (раньше scriptAssetId указывал на файл, который никто не создавал).
// ============================================================================

QstQuest _quest(List<QstNode> nodes) => QstQuest(
      title: 'T',
      nodes: nodes,
      startNodeId: '1',
      variables: {'флаг'},
      inventoryItems: {'меч'},
    );

void main() {
  test('инвентарь → assign_variable, условие → condition, goto → go_to_node',
      () {
    final node = QstNode(id: '1', commands: [
      const QstCommand(
        type: QstCommandType.inv,
        rawLine: 'inv + меч',
        argument: 'меч',
        extraArgument: 'add',
      ),
      const QstCommand(
        type: QstCommandType.inv,
        rawLine: 'inv - щит',
        argument: 'щит',
        extraArgument: 'remove',
      ),
      const QstCommand(
        type: QstCommandType.ifn,
        rawLine: 'ifn флаг=1 2',
        argument: '2',
        condition: 'флаг=1',
      ),
    ]);

    final data = QstToMeanderConverter().convert(_quest([
      node,
      // Цель перехода для ifn.
      QstNode(id: '2', commands: const [
        QstCommand(
            type: QstCommandType.pln, rawLine: 'pln x', argument: 'x'),
      ]),
    ]));

    expect(data.scripts, hasLength(1));
    final script = data.scripts.values.single;
    final blocks = script['blocks'] as List;

    // Event-обёртка.
    final event = blocks.single;
    expect(event['type'], 'event');
    expect(event['eventType'], 'onNodeEnter');

    final children = (event['children'] as List).cast<Map>();
    expect(children, hasLength(3));

    expect(children[0]['type'], 'assign_variable');
    expect(children[0]['variable'], 'инвентарь_меч');
    expect(children[0]['value'], '1');
    expect(children[1]['value'], '0');

    expect(children[2]['type'], 'condition');
    // Число не квотируется (легаси-семантика условий).
    expect(children[2]['expression'], '{флаг} == 1');
    final thenBlocks = (children[2]['then_blocks'] as List).single;
    expect(thenBlocks['type'], 'go_to_node');
    expect(thenBlocks['node_id'], isNotEmpty);

    // scriptAssetId ноды указывает на записанный файл.
    final nodeJson = data.nodes.first.toJson();
    final assetId = nodeJson['scriptAssetId'];
    expect(assetId, data.scripts.keys.first);
  });

  test('все сгенерированные блоки проходят ScriptParser без UnknownBlock', () {
    final nodes = [
      QstNode(id: '1', commands: const [
        QstCommand(
          type: QstCommandType.inv,
          rawLine: 'inv + меч',
          argument: 'меч',
          extraArgument: 'add',
        ),
        QstCommand(
          type: QstCommandType.ifn,
          rawLine: 'ifn not флаг 2',
          argument: '2',
          condition: 'not флаг',
        ),
        QstCommand(type: QstCommandType.goto, rawLine: 'goto 2', argument: '2'),
      ]),
      QstNode(id: '2', commands: const [
        QstCommand(type: QstCommandType.pln, rawLine: 'pln конец', argument: 'к'),
      ]),
    ];

    final data = QstToMeanderConverter().convert(_quest(nodes));
    expect(data.scripts, isNotEmpty);

    for (final script in data.scripts.values) {
      final parsed =
          ScriptParser.parseBlocks(script['blocks'] as List<dynamic>);
      for (final block in parsed) {
        expect(block.runtimeType.toString(), isNot('UnknownBlock'),
            reason: 'блок ${block.id} превратился в UnknownBlock');
      }
      // Отрицание ушло в оператор, а не в унарный not.
      final event = (script['blocks'] as List).single as Map;
      for (final child
          in (event['children'] as List).cast<Map>()) {
        if (child['type'] == 'condition') {
          expect(child['expression'], '{флаг} == false');
        }
      }
    }
  });
}
