// Резолвер linked-инстансов нод: что реально уходит в рантайм.
// #179 — автор правил ноду-инстанс, а игра показывала payload мастера.

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/services/template_instance_resolver.dart';

Map<String, dynamic> masterNodePayload() => <String, dynamic>{
  'id': 'master-node',
  'title': 'Мастер: сцена допроса',
  'chapterId': 'chapter-master',
  'x': 10,
  'y': 20,
  'content': <String, dynamic>{
    'items': <dynamic>[
      <String, dynamic>{
        'id': 'btn-own',
        'type': 'button',
        'text': 'Открыть дверь',
        'targetNodeId': 'node-2',
      },
    ],
  },
  'backgroundVideoAssetId': 'res/videos/hall.mp4',
  'backgroundBlur': 12,
  'itemSpacing': 0,
  'transitionMode': 'fade',
  'allowSave': false,
  'templateRef': 'tpl-1',
  'isTemplateMaster': true,
};

Map<String, dynamic> instanceNodeJson() => <String, dynamic>{
  'id': 'inst-1',
  'title': 'Моя копия',
  'chapterId': 'chapter-1',
  'x': 300,
  'y': 400,
  'templateRef': 'tpl-1',
  'templateVersion': 1,
  'content': <String, dynamic>{
    'items': <dynamic>[
      <String, dynamic>{'id': 'own-1', 'type': 'text', 'text': 'своя строка'},
    ],
  },
};

TemplateItem masterTemplate({int contentVersion = 4}) => TemplateItem(
  id: 'tpl-1',
  name: 'Сцена допроса',
  kind: TemplateKind.node,
  payload: masterNodePayload(),
  contentVersion: contentVersion,
);

void main() {
  group('TemplateInstanceResolver.resolveNode', () {
    test('контент и заголовок берутся у мастера, а не у инстанса', () {
      final resolver = TemplateInstanceResolver(
        templatesById: {'tpl-1': masterTemplate()},
      );

      final resolved = resolver.resolveNode(
        SavedNode.fromJson(instanceNodeJson()),
      );

      expect(resolved.title, 'Мастер: сцена допроса');
      final items = resolved.content['items'] as List<dynamic>;
      expect(items, hasLength(1));
      final first = Map<String, dynamic>.from(items.first as Map);
      expect(first['text'], 'Открыть дверь');
      // Своя строка инстанса в рантайм не попадает — из-за этого правка
      // автора исчезала молча (#179).
      expect(first['text'], isNot('своя строка'));
    });

    test('инстанс сохраняет свою идентичность: id, глава, позиция', () {
      final resolver = TemplateInstanceResolver(
        templatesById: {'tpl-1': masterTemplate()},
      );

      final resolved = resolver.resolveNode(
        SavedNode.fromJson(instanceNodeJson()),
      );

      expect(resolved.id, 'inst-1');
      expect(resolved.chapterId, 'chapter-1');
      expect(resolved.x, 300);
      expect(resolved.y, 400);
      expect(resolved.defaultActionNodeId, isNull);
    });

    test('настройки мастера доезжают целиком, без потерь по полям', () {
      final resolver = TemplateInstanceResolver(
        templatesById: {'tpl-1': masterTemplate()},
      );

      final resolved = resolver.resolveNode(
        SavedNode.fromJson(instanceNodeJson()),
      );

      expect(resolved.backgroundVideoAssetId, 'res/videos/hall.mp4');
      expect(resolved.backgroundBlur, 12);
      expect(resolved.itemSpacing, 0);
      expect(resolved.transitionMode, 'fade');
      expect(resolved.allowSave, isFalse);
    });

    test('связь с шаблоном остаётся: разрешённый узел всё ещё инстанс', () {
      final resolver = TemplateInstanceResolver(
        templatesById: {'tpl-1': masterTemplate()},
      );

      final resolved = resolver.resolveNode(
        SavedNode.fromJson(instanceNodeJson()),
      );

      // Флаг мастера из payload не должен «развязать» ноду прямо в резолвере:
      // редактор по isTemplateInstance решает, отвязывать ли ноду при правке.
      expect(resolved.isTemplateInstance, isTrue);
      expect(resolved.isTemplateMaster, isFalse);
      expect(resolved.templateRef, 'tpl-1');
      expect(resolved.templateVersion, 4);
    });

    test('повторный вызов из кэша даёт те же поля', () {
      final resolver = TemplateInstanceResolver(
        templatesById: {'tpl-1': masterTemplate()},
      );
      final instance = SavedNode.fromJson(instanceNodeJson());

      final first = resolver.resolveNode(instance);
      final second = resolver.resolveNode(instance);

      expect(second.title, first.title);
      expect(second.content['items'], first.content['items']);
      expect(second.backgroundVideoAssetId, first.backgroundVideoAssetId);
      expect(second.itemSpacing, first.itemSpacing);
      expect(second.isTemplateInstance, isTrue);
    });

    test('мастер удалён — инстанс возвращается как есть', () {
      final resolver = TemplateInstanceResolver(
        templatesById: const {},
      );
      final instance = SavedNode.fromJson(instanceNodeJson());

      expect(resolver.resolveNode(instance), same(instance));
    });

    test('обычная нода не трогается', () {
      final resolver = TemplateInstanceResolver(
        templatesById: {'tpl-1': masterTemplate()},
      );
      final plain = SavedNode.fromJson(instanceNodeJson())
          .copyWith(clearTemplateLink: true);

      expect(resolver.resolveNode(plain), same(plain));
    });
  });
}
