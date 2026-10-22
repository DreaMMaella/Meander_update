import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/services/refactoring_service.dart';
import 'package:canvas_app/features/resources/models/resource_file.dart';
import 'package:canvas_app/features/resources/services/quest_storage.dart';

import 'resource_service_test.dart';

ResourceFile scriptResource({
  required String questId,
  String fileName = 's1.json',
  String friendlyName = 'Открыть дверь',
}) {
  return ResourceFile(
    id: fileName,
    name: fileName,
    path: QuestStorage(questId: questId).scriptFilePath(fileName),
    type: 'script',
    friendlyName: friendlyName,
  );
}

void main() {
  group('ResourceService.renameResource', () {
    test('пустое и «без изменений» имя — ни записи, ни события', () async {
      final s = makeService();
      final storage = QuestStorage(questId: 'q1');
      final resource = scriptResource(questId: 'q1');
      s.adapter.jsonFiles[resource.path] = {'name': 'Открыть дверь'};

      final events = <ResourceRenameEvent>[];
      final sub = RefactoringService.resourceRenameEvents.listen(events.add);
      addTearDown(sub.cancel);

      await s.service.renameResource(resource, '   ');
      await s.service.renameResource(resource, 'Открыть дверь');
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      expect(s.adapter.jsonFiles[storage.metadataPath], isNull);
      expect(s.adapter.jsonFiles[resource.path], {'name': 'Открыть дверь'});
    });

    test(
      'новое имя: metadata + name в JSON скрипта + событие редактору',
      () async {
        final s = makeService();
        final storage = QuestStorage(questId: 'q1');
        final resource = scriptResource(questId: 'q1');
        s.adapter.jsonFiles[resource.path] = {
          'name': 'Открыть дверь',
          'blocks': [],
        };

        final events = <ResourceRenameEvent>[];
        final sub = RefactoringService.resourceRenameEvents.listen(events.add);
        addTearDown(sub.cancel);

        await s.service.renameResource(resource, '  Пнуть стража  ');
        await Future<void>.delayed(Duration.zero);

        expect(
          (s.adapter.jsonFiles[resource.path] as Map)['name'],
          'Пнуть стража',
        );
        final metadata = s.adapter.jsonFiles[storage.metadataPath] as Map;
        expect(
          QuestStorage.fileNameFromMetadata(
            Map<String, dynamic>.from(metadata),
            resource.name,
          ),
          'Пнуть стража',
        );

        expect(events, hasLength(1));
        expect(events.single.questId, 'q1');
        expect(events.single.fileName, 's1.json');
        expect(events.single.newName, 'Пнуть стража');
      },
    );
  });
}
