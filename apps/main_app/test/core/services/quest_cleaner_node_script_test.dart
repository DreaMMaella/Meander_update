// «Очистка квеста» собирала ссылки на скрипты только из scriptAssetId и
// scriptTriggers. Скрипт, прикреплённый к ноде content-элементом
// (type: 'script' + resourcePath), оказывался «неиспользуемым» — а применённая
// очистка удаляет такой файл с диска, хотя нода запускает его на входе.
// То же касалось нового формата `behaviours`.
import 'dart:io';

import 'package:canvas_app/core/services/quest_cleaner_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';

const String _questId = '11111111-1111-4111-8111-111111111111';
const String _chapterId = 'chapter-1';
const String _nodeId = 'node-1';
const String _attached = 'node-script';
const String _behaviour = 'behaviour-script';
const String _boot = 'boot-script';
const String _bootLegacy = 'boot-script-legacy';
const String _orphan = 'unused-script';

Future<void> _writeScript(String name) => FileStorage.writeJsonFile(
  '${QuestPaths.scriptsDir(_questId)}/$name.json',
  {
    'id': name,
    'blocks': [
      {'type': 'event', 'key': 'onNodeEnter'},
    ],
  },
);

/// Скрипт, объявляющий событие «При запуске квеста»: явным `eventType` или,
/// как хранили старые файлы, только русским заголовком.
Future<void> _writeBootScript(String name, {required bool byTitle}) =>
    FileStorage.writeJsonFile(
      '${QuestPaths.scriptsDir(_questId)}/$name.json',
      {
        'id': name,
        'blocks': [
          {
            'type': 'event',
            if (!byTitle) 'eventType': 'onQuestStart',
            'title': 'При запуске квеста',
            'children': [
              {'type': 'assign_variable', 'variable': 'boot', 'value': 1},
            ],
          },
        ],
      },
    );

void main() {
  late Directory appDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    appDir = await Directory.systemTemp.createTemp('mnd_quest_cleaner_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return appDir.path;
          }
          return null;
        });

    await FileStorage.writeJsonFile(QuestPaths.config(_questId), {
      'id': _questId,
      'title': 'Тестовый квест',
      'startNodeId': _nodeId,
      'tags': [
        {'id': _chapterId, 'name': 'Глава 1'},
      ],
    });

    await FileStorage.writeJsonFile(QuestPaths.nodesLegacy(_questId), {
      'nodes': [
        {
          'id': _nodeId,
          'chapterId': _chapterId,
          'title': 'Нода 1',
          'content': {
            'items': [
              {
                'id': 'item-1',
                'type': 'script',
                'resourcePath': 'scripts/$_attached.json',
              },
              {
                'id': 'item-2',
                'type': 'button',
                'behaviours': [
                  {
                    'event': 'onPress',
                    'kind': 'action',
                    'script': 'scripts/$_behaviour.json',
                  },
                ],
              },
              // Модалка с авто-закрытием: цель `_CLOSE_MODAL` обслуживает
              // плеер, а флаг отсчёта в старых файлах лежал в scriptTriggers.
              {
                'id': 'item-3',
                'type': 'modal',
                'targetNodeId': '_CLOSE_MODAL',
                'scriptTriggers': {'showTimer': 'true'},
              },
            ],
          },
        },
      ],
    });

    await _writeScript(_attached);
    await _writeScript(_behaviour);
    await _writeBootScript(_boot, byTitle: false);
    await _writeBootScript(_bootLegacy, byTitle: true);
    await _writeScript(_orphan);
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  test('скрипт из content-элемента ноды не помечается к удалению', () async {
    final report = await QuestCleanerService().scanQuest(_questId);
    final toDelete =
        report.issues
            .where((issue) => issue.type == 'delete_script')
            .map((issue) => issue.payload['scriptPath'])
            .toSet();

    // Скрипт запуска квеста не вызывает ни одна нода: без правила «событие
    // объявлено — скрипт используется» очистка удалила бы стартовый файл.
    expect(toDelete, isNot(contains('scripts/$_boot.json')));
    expect(toDelete, isNot(contains('scripts/$_bootLegacy.json')));
    expect(toDelete, contains('scripts/$_orphan.json'));
    expect(toDelete, isNot(contains('scripts/$_attached.json')));
    // Скрипт, привязанный новым форматом, — тоже рабочий.
    expect(toDelete, isNot(contains('scripts/$_behaviour.json')));
  });

  /// `_CLOSE_MODAL` в `targetNodeId` — служебная цель плеера, ноды с таким id
  /// в квесте и не должно быть; «Ссылка на несуществующую ноду» на неё
  /// ложная. Флаг отсчёта модалки, который в старых файлах лежал в
  /// `scriptTriggers`, — тоже не ссылка на скрипт.
  test('служебные поля модалки не дают ложных находок', () async {
    final report = await QuestCleanerService().scanQuest(_questId);
    final titles = report.issues.map((issue) => issue.title).toList();

    expect(
      titles.where((t) => t.contains('несуществующую ноду')),
      isEmpty,
      reason: '$titles',
    );
    expect(
      titles.where((t) => t.startsWith('Отсутствующий скрипт')),
      isEmpty,
      reason: '$titles',
    );
  });
}
