// Очистка нод без chapterId переписывала nodes.json целиком, но собирала новый
// файл из одного ключа 'nodes' — группы и комментарии из той же главы исчезали.
// Удаление одной «мусорной» ноды стоило всех накладных групп и заметок квеста.
import 'dart:io';

import 'package:canvas_app/features/editor/providers/tag_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';

const String _questId = '33333333-3333-4333-8333-333333333333';
const String _chapterId = 'chapter-1';

const Map<String, dynamic> _group = {
  'id': 'group-1',
  'chapterId': _chapterId,
  'nodeIds': ['node-a'],
  'x': 40.0,
  'y': 40.0,
  'width': 400.0,
  'height': 300.0,
};

const Map<String, dynamic> _comment = {
  'id': 'comment-1',
  'chapterId': _chapterId,
  'text': 'Не забыть дописать финал',
  'x': 60.0,
  'y': 60.0,
};

Future<void> _writeQuestFiles() async {
  await FileStorage.writeJsonFile(QuestPaths.config(_questId), {
    'id': _questId,
    'title': 'Тестовый квест',
    'startNodeId': 'node-a',
    'tags': [
      {'id': _chapterId, 'name': 'Глава 1', 'questId': _questId},
    ],
    'connections': [
      {'id': 'conn-1', 'fromId': 'node-a', 'toId': 'node-stray'},
      {'id': 'conn-2', 'fromId': 'node-a', 'toId': 'node-a'},
    ],
  });

  await FileStorage.writeJsonFile(QuestPaths.nodesLegacy(_questId), {
    'nodes': [
      {
        'id': 'node-a',
        'chapterId': _chapterId,
        'title': 'Нода A',
        'x': 100.0,
        'y': 100.0,
        'content': {'items': []},
      },
      {
        // Остаток после копирования главы: ни главы, ни связей.
        'id': 'node-stray',
        'title': 'Сирота',
        'x': 500.0,
        'y': 500.0,
        'content': {'items': []},
      },
    ],
    'groups': [_group],
    'comments': [_comment],
  });
}

void main() {
  late Directory appDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    appDir = await Directory.systemTemp.createTemp('mnd_cleanup_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return appDir.path;
          }
          return null;
        });
  });

  setUp(() async {
    await _writeQuestFiles();
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  test('очистка убирает только ноды без chapterId', () async {
    final removed = await cleanupNodesWithoutChapter(_questId);
    expect(removed, 1);

    final data = await FileStorage.readJsonFile(
      QuestPaths.nodesLegacy(_questId),
    );
    final ids = (data['nodes'] as List)
        .map((n) => (n as Map)['id'].toString())
        .toList();
    expect(ids, ['node-a']);
  });

  test('группы и комментарии остаются в nodes.json после очистки', () async {
    await cleanupNodesWithoutChapter(_questId);

    final data = await FileStorage.readJsonFile(
      QuestPaths.nodesLegacy(_questId),
    );
    expect(data['groups'], isNotNull);
    expect(data['comments'], isNotNull);
    expect((data['groups'] as List), hasLength(1));
    expect((data['comments'] as List), hasLength(1));
    expect((data['comments'] as List).first['text'], 'Не забыть дописать финал');
  });

  test('из nodes.json уходят связи с удалённой нодой', () async {
    await cleanupNodesWithoutChapter(_questId);

    final config = await FileStorage.readJsonFile(QuestPaths.config(_questId));
    final connections = (config['connections'] as List)
        .map((c) => (c as Map)['id'].toString())
        .toList();
    expect(connections, ['conn-2']);
    // Остальные поля конфига не должны пострадать от точечной правки.
    expect(config['title'], 'Тестовый квест');
    expect(config['startNodeId'], 'node-a');
  });
}
