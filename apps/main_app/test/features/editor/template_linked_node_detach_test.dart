// #179: правка linked-инстанса ноды.
//
// Пока нода связана с мастером, в игру уходит payload мастера (то же самое
// делает движок — `Engine::resolve_node`), поэтому локальные правки такой
// ноды исчезали молча, а тестер видел кнопки, которых автор уже не добавлял.
// Редактор отвязывает ноду при первой правке: копирует то, что автор видит,
// и снимает связь. Тест проверяет эту пару чистых функций — сам вызов из
// экрана (тап по полю → снэкбар → запись на диск) здесь не покрыт.

import 'package:canvas_app/features/editor/utils/template_applier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/services/template_instance_resolver.dart';

Map<String, dynamic> masterPayload() => <String, dynamic>{
  'id': 'master-node',
  'title': 'Сцена допроса',
  'chapterId': 'chapter-master',
  'x': 10,
  'y': 20,
  'content': <String, dynamic>{
    'items': <dynamic>[
      <String, dynamic>{
        'id': 'btn-master',
        'type': 'button',
        'text': 'Открыть дверь',
        'targetNodeId': 'node-2',
      },
      <String, dynamic>{
        'id': 'row-master',
        'type': 'row',
        'children': <dynamic>[
          <String, dynamic>{'id': 'txt-inner', 'type': 'text', 'text': 'Улика'},
        ],
      },
    ],
  },
  'isTemplateMaster': true,
  'templateRef': 'tpl-1',
};

SavedNode instance() => SavedNode.fromJson(<String, dynamic>{
  'id': 'inst-1',
  'title': 'Сцена допроса',
  'chapterId': 'chapter-1',
  'x': 300,
  'y': 400,
  'templateRef': 'tpl-1',
  'templateVersion': 1,
  'content': <String, dynamic>{'items': <dynamic>[]},
});

TemplateInstanceResolver resolver() => TemplateInstanceResolver(
  templatesById: <String, TemplateItem>{
    'tpl-1': TemplateItem(
      id: 'tpl-1',
      name: 'Сцена допроса',
      kind: TemplateKind.node,
      payload: masterPayload(),
      contentVersion: 7,
    ),
  },
);

List<String> itemIds(Map<String, dynamic> content) {
  final items = content['items'] as List<dynamic>;
  return items.map((raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    return map['id'].toString();
  }).toList();
}

void main() {
  group('Отвязка linked-ноды (#179)', () {
    test('разрешённый инстанс не содержит своих id — они выводятся из мастера',
        () {
      final resolved = resolver().resolveNode(instance());

      expect(itemIds(resolved.content), isNot(contains('btn-master')));
      expect(itemIds(resolved.content), everyElement(startsWith('tpl_')));
    });

    test('detach снимает связь и делает id обычными uuid', () {
      final resolved = resolver().resolveNode(instance());

      final detached = TemplateApplier.detachNode(resolved);

      expect(detached.templateRef, isNull);
      expect(detached.templateVersion, isNull);
      expect(detached.isTemplateMaster, isFalse);
      expect(detached.isTemplateInstance, isFalse);
      expect(itemIds(detached.content), everyElement(isNot(startsWith('tpl_'))));
      expect(itemIds(detached.content), hasLength(2));
    });

    test('после отвязки резолвер больше не перезаписывает контент', () {
      final detached = TemplateApplier.detachNode(
        resolver().resolveNode(instance()),
      );
      final edited = detached.copyWith(
        content: <String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{
              'id': 'my-button',
              'type': 'button',
              'text': 'Своя кнопка',
            },
          ],
        },
      );

      final inGame = resolver().resolveNode(edited);

      // Это и есть суть правки: отвязанная нода уходит в игру как есть,
      // поэтому то, что автор видит в редакторе, совпадает с рантаймом.
      expect(inGame, same(edited));
      expect(itemIds(inGame.content), ['my-button']);
    });

    test('отвязка сохраняет идентичность ноды и её место на канвасе', () {
      final detached = TemplateApplier.detachNode(
        resolver().resolveNode(instance()),
      );

      expect(detached.id, 'inst-1');
      expect(detached.chapterId, 'chapter-1');
      expect(detached.x, 300);
      expect(detached.y, 400);
    });

    test('дети ряда получают новые id вместе с родителем', () {
      final detached = TemplateApplier.detachNode(
        resolver().resolveNode(instance()),
      );
      final items = detached.content['items'] as List<dynamic>;
      final row = Map<String, dynamic>.from(items[1] as Map);
      final children = row['children'] as List<dynamic>;
      final child = Map<String, dynamic>.from(children.first as Map);

      expect(child['id'], isNot('txt-inner'));
      expect(child['text'], 'Улика');
    });
  });
}
