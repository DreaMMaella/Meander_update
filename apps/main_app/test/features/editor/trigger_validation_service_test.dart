import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/editor/services/trigger_validation_service.dart';

class InMemoryTriggerStorage implements TriggerValidationStorage {
  final Set<String> files = {};
  final Map<String, Map<String, dynamic>> jsonFiles = {};

  @override
  Future<bool> exists(String relativePath) async =>
      files.contains(relativePath) || jsonFiles.containsKey(relativePath);

  @override
  Future<Map<String, dynamic>> readJsonFile(String relativePath) async {
    final value = jsonFiles[relativePath];
    if (value == null) throw Exception('missing $relativePath');
    return Map<String, dynamic>.from(value);
  }
}

void main() {
  TriggerValidationService makeService(InMemoryTriggerStorage storage) =>
      TriggerValidationService(questId: 'q1', storage: storage);

  group('TriggerValidationService', () {
    test('пустой триггер не считается проблемой', () async {
      final issue = await makeService(InMemoryTriggerStorage()).validateOnAppear(
        itemId: 'item-1',
        rawTrigger: null,
      );
      expect(issue, isNull);
    });

    test('проверяет существование Lua-файла, но не JSON-блоки', () async {
      final storage = InMemoryTriggerStorage();
      storage.files.add('quests/q1/scripts/show.lua');
      final service = makeService(storage);

      expect(
        await service.validateOnAppear(
          itemId: 'item-1',
          rawTrigger: 'scripts/show.lua',
        ),
        isNull,
      );
      expect(
        (await service.validateOnAppear(
          itemId: 'item-1',
          rawTrigger: 'scripts/missing.lua',
        ))?.message,
        'onAppear-скрипт не найден',
      );
    });

    test('принимает JSON onContentAppear с подходящим item', () async {
      final storage = InMemoryTriggerStorage();
      storage.jsonFiles['quests/q1/scripts/show.json'] = {
        'blocks': [
          {
            'type': 'event',
            'eventType': 'onContentAppear',
            'targetContentItemId': 'item-1',
          },
        ],
      };

      final issue = await makeService(storage).validateOnAppear(
        itemId: 'item-1',
        rawTrigger: 'scripts/show.json',
      );
      expect(issue, isNull);
    });

    test('помечает одиночный JSON-триггер с другим item как auto-fix', () async {
      final storage = InMemoryTriggerStorage();
      storage.jsonFiles['quests/q1/scripts/show.json'] = {
        'blocks': [
          {
            'type': 'event',
            'eventType': 'onContentAppear',
            'targetContentItemId': 'old-item',
          },
        ],
      };

      final issue = await makeService(storage).validateOnAppear(
        itemId: 'item-1',
        rawTrigger: 'scripts/show.json',
      );
      expect(issue?.canAutoFix, isTrue);
    });

    test('проверяет именованные function-события', () async {
      final storage = InMemoryTriggerStorage();
      storage.jsonFiles['quests/q1/scripts/functions.json'] = {
        'blocks': [
          {
            'type': 'event',
            'eventType': 'function',
            'functionName': 'heal',
          },
        ],
      };
      final service = makeService(storage);

      expect(
        await service.validateOnAppear(
          itemId: 'item-1',
          rawTrigger: 'scripts/functions.json#fn=heal',
        ),
        isNull,
      );
      expect(
        (await service.validateOnAppear(
          itemId: 'item-1',
          rawTrigger: 'scripts/functions.json#fn=attack',
        ))?.message,
        'В скрипте нет функции "attack"',
      );
    });
  });
}
