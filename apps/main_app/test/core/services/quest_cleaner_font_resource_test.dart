// «Очистка квеста» решала, какой файл неиспользуемый, по заготовленному
// списку полей: resourcePath, фоновые id, уголки кнопки. Шрифт же живёт в
// `buttonStyle.fontFamily`, в `item.fontFamily`, в инлайн-теге `[font=…]`
// внутри текста, в пресетах конфига и в мастерах шаблонов — и ни одно из этих
// мест очистка не смотрела. Файл уезжал с диска вместе с пунктом
// «Неиспользуемый ресурс», а квест оставался с кнопками без шрифта
// (жалоба тестера #283).
import 'dart:io';

import 'package:canvas_app/core/services/quest_cleaner_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';

const String _questId = '22222222-2222-4222-8222-222222222222';
const String _chapterId = 'chapter-1';
const String _nodeId = 'node-1';

/// Имена файлов шрифтов, каждый из которых нода использует по-своему.
const String _buttonFont = 'button.ttf';
const String _itemFont = 'item.ttf';
const String _inlineFont = 'inline.ttf';
const String _layerFont = 'layer.ttf';
const String _presetFont = 'preset.ttf';
const String _templateFont = 'template.ttf';
const String _bareFont = 'bare.ttf';
const String _orphanFont = 'orphan.ttf';

Future<void> _writeFont(String name) async {
  final path = await FileStorage.getFilePath(
    QuestPaths.resFont(_questId, name),
  );
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(List<int>.filled(64, 0));
}

void main() {
  late Directory appDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    appDir = await Directory.systemTemp.createTemp('mnd_cleaner_fonts_test');
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
      // Шрифт всего квеста редактор хранит голым именем файла, без `res/`.
      'customFontFileName': _bareFont,
      'buttonStylePresets': [
        {'presetName': 'Основной', 'fontFamily': 'res/fonts/$_presetFont'},
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
                'type': 'button',
                'buttonText': 'Идти',
                'buttonStyle': {'fontFamily': 'res/fonts/$_buttonFont'},
              },
              {
                'id': 'item-2',
                'type': 'text',
                'fontFamily': 'res/fonts/$_itemFont',
              },
              {
                'id': 'item-3',
                'type': 'text',
                'contentMarkdown':
                    '[font=res/fonts/$_inlineFont]Заголовок[/font]',
              },
              {
                'id': 'item-4',
                'type': 'stack',
                'children': [
                  {
                    'id': 'layer-1',
                    'type': 'button',
                    'buttonStyle': {'fontFamily': 'res/fonts/$_layerFont'},
                  },
                ],
              },
              // Инстанс шаблона: в ноде только ссылка на мастера.
              {'id': 'item-5', 'type': 'button', 'templateRef': 'tpl-1'},
            ],
          },
        },
      ],
    });

    await FileStorage.writeJsonFile(QuestPaths.templates(_questId), {
      'schemaVersion': 1,
      'templates': [
        {
          'id': 'tpl-1',
          'name': 'Плашка',
          'items': [
            {
              'id': 'master-1',
              'type': 'button',
              'buttonStyle': {'fontFamily': 'res/fonts/$_templateFont'},
            },
          ],
        },
      ],
    });

    for (final name in [
      _buttonFont,
      _itemFont,
      _inlineFont,
      _layerFont,
      _presetFont,
      _templateFont,
      _bareFont,
      _orphanFont,
    ]) {
      await _writeFont(name);
    }
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  test('шрифт, на который ссылается кнопка, очистка не удаляет', () async {
    final report = await QuestCleanerService().scanQuest(_questId);
    final toDelete = report.issues
        .where((issue) => issue.type == 'delete_resource')
        .map((issue) => issue.payload['resourcePath'].toString())
        .toSet();

    for (final used in [
      _buttonFont,
      _itemFont,
      _inlineFont,
      _layerFont,
      _presetFont,
      _templateFont,
      _bareFont,
    ]) {
      expect(
        toDelete,
        isNot(contains('res/fonts/$used')),
        reason: 'используемый шрифт $used помечен к удалению: $toDelete',
      );
    }

    // Негативный контроль: чистка не превратилась в «ничего не удалять».
    expect(toDelete, contains('res/fonts/$_orphanFont'));
  });
}
