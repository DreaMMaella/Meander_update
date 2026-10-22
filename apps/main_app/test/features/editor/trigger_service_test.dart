import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/editor/services/trigger_service.dart';
import 'package:canvas_app/features/resources/services/quest_storage.dart';
import 'package:canvas_app/features/resources/services/resource_service.dart';

import '../resources/resource_service_test.dart';

void main() {
  group('TriggerService', () {
    test('имена Lua-функций по событиям движка', () {
      expect(TriggerService.luaFunctionForTrigger('onPress'), 'onPress');
      expect(
        TriggerService.luaFunctionForTrigger('onAppear'),
        'onContentAppear',
      );
      // fallback функции движка для остальных триггеров
      expect(TriggerService.luaFunctionForTrigger('onWeird'), 'start');
    });

    test('Lua-шаблон содержит функцию события с item_id', () {
      final tpl = TriggerService.luaTemplate('onPress', 'Клик');
      expect(tpl, contains('function onPress(item_id)'));
      expect(tpl, contains('-- Клик'));
    });

    test('JSON-блоки триггера по ключу', () {
      final press = TriggerService.jsonInitialBlocks('onPress');
      expect(press.single['eventType'], 'onPress');
      final appear = TriggerService.jsonInitialBlocks('onAppear');
      expect(appear.single['eventType'], 'onContentAppear');
      final fallback = TriggerService.jsonInitialBlocks('onNodeEnter');
      expect(fallback.single['eventType'], 'onNodeEnter');
    });

    test('JSON-блок функции', () {
      final blocks = TriggerService.jsonFunctionBlocks(functionName: 'go');
      final b = blocks.single;
      expect(b['eventType'], 'function');
      expect(b['functionName'], 'go');
    });
  });

  group('ScriptService.kindOfRef', () {
    test('классифицирует ссылки', () {
      expect(ScriptService.kindOfRef('scripts/a.json'), ScriptKind.json);
      expect(ScriptService.kindOfRef('scripts/b.lua'), ScriptKind.lua);
      expect(
        ScriptService.kindOfRef('scripts/c.json#fn=main'),
        ScriptKind.json,
      );
      expect(ScriptService.kindOfRef('scripts/d.lua#fn=f'), ScriptKind.lua);
      expect(ScriptService.kindOfRef(''), ScriptKind.unknown);
    });

    test('displayName для .lua через metadata', () async {
      final adapter = InMemoryStorageAdapter();
      adapter.jsonFiles['quests/q1/res/metadata.json'] = {
        'гоблин.lua': {'name': 'гоблин', 'folder': '/'},
      };
      adapter.jsonFiles['quests/q1/scripts/a.json'] = {
        'id': 'a',
        'name': 'Боевой',
        'blocks': [],
      };
      final svc = ScriptService(
        resources: ResourceService(
          storage: QuestStorage(questId: 'q1', adapter: adapter),
        ),
      );

      expect(
        await svc.displayName('scripts/гоблин.lua'),
        'гоблин',
      );
      expect(
        await svc.displayName('scripts/a.json#fn=main'),
        'Боевой :: main',
      );
    });
  });

  group('ScriptService.createTriggerScript', () {
    test('JSON-триггер: авто-имя + шаблон события', () async {
      final s = makeService();
      final svc = ScriptService(resources: s.service);
      final created = await svc.createTriggerScript(
        triggerKey: 'onPress',
        lua: false,
      );

      expect(created.name, 'Скрипт 1');
      final data = await s.adapter.readJsonFile(created.filePath);
      expect((data['blocks'] as List).single['eventType'], 'onPress');
    });

    test('.lua-триггер: префикс по событию + функция события', () async {
      final s = makeService();
      final svc = ScriptService(resources: s.service);
      final created = await svc.createTriggerScript(
        triggerKey: 'onPress',
        lua: true,
      );

      expect(created.name, 'Нажатие 1');
      expect(created.fileName, 'Нажатие 1.lua');
      final text = await s.adapter.readText(created.filePath);
      expect(text, contains('function onPress(item_id)'));
    });
  });
}
