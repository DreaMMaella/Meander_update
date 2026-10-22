// saveNodes склеивает старую запись ноды из nodes.json со свежей. Если
// старое значение ключа модели не перечистить, снятая настройка воскресает
// при следующем открытии квеста — это тихая потеря данных.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_app/features/editor/providers/node_provider.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _questId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const _nodesRel = 'quests/$_questId/nodes.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;
  late File nodesFile;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    appDir = await Directory.systemTemp.createTemp('mnd_nodes_save_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return appDir.path;
      }
      return null;
    });
    nodesFile = File('${appDir.path}/$_nodesRel');
  });

  tearDownAll(() async {
    if (appDir.existsSync()) {
      await appDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await File('${appDir.path}/quests/$_questId/config.json').parent
        .create(recursive: true);
    await File(
      '${appDir.path}/quests/$_questId/config.json',
    ).writeAsString(jsonEncode({'id': _questId, 'title': 'Тест'}));
  });

  /// Записать nodes.json «как после старой версии редактора».
  /// Пишем в обход QuestStore — его JSON-кэш надо сбросить, иначе
  /// saveNodes прочитает прошлый тест, а не диск.
  Future<void> seedStoredNode(Map<String, dynamic> fields) async {
    final node = <String, dynamic>{
      'id': 'n1',
      'chapterId': 'c1',
      'title': 'Нода',
      'content': {'items': []},
      'x': 10.0,
      'y': 20.0,
    }..addAll(fields);
    await nodesFile.writeAsString(
      jsonEncode({'nodes': [node], 'groups': [], 'comments': []}),
    );
    FileStorage.invalidateJsonCache([_nodesRel]);
  }

  Future<Map<String, dynamic>> storedNode() async {
    final decoded = jsonDecode(await nodesFile.readAsString())
        as Map<String, dynamic>;
    final list = decoded['nodes'] as List<dynamic>;
    return (list.single as Map).cast<String, dynamic>();
  }

  SavedNode nodeWithoutSettings() => SavedNode(
    id: 'n1',
    chapterId: 'c1',
    title: 'Нода',
    content: const {'items': []},
    x: 10,
    y: 20,
  );

  test('снятая настройка не воскресает из старой копии файла', () async {
    await seedStoredNode({
      'backgroundBlur': 12.0,
      'backgroundVideoAssetId': 'vid-1',
      'backgroundVideoFit': 'cover',
      'backgroundVideoMuted': true,
      'toolbarMode': 'enabled',
      'toolbarPosition': 'top',
      'toolbarStyle': {'opacity': 0.5},
      'allowSave': false,
      'allowInventoryAccess': false,
      'allowToolbarInteractions': false,      'transitionMode': 'fade',
      'itemSpacing': 8.0,
      'imageRoundedCorners': false,
      'timerHidden': true,
      'templateRef': 'master-1',
      'templateVersion': 3,
      'isTemplateMaster': true,
    });

    final ok = await saveNodes(_questId, [nodeWithoutSettings()]);
    expect(ok, isTrue, reason: 'сохранение не должно падать');

    final stored = await storedNode();
    for (final key in SavedNode.modelKeys) {
      if (const {'id', 'chapterId', 'title', 'content', 'x', 'y'}.contains(key)) {
        continue;
      }
      expect(
        stored.containsKey(key),
        isFalse,
        reason: '$key снят до дефолта, но остался в nodes.json',
      );
    }
    expect(stored['title'], 'Нода');
  });

  // HUD-панель вырезана из модели: её ключи больше не читаются, и старая
  // запись в nodes.json должна умереть при первом же сохранении. Без
  // чистки legacy-ключей в _mergeNodeJson тест падает — ключи остаются.
  test('ключи HUD-панели вычищаются из файла ноды', () async {
    await seedStoredNode({
      'toolbarMode': 'enabled',
      'toolbarPosition': 'top',
      'toolbarStyle': {'opacity': 0.5},
      'allowToolbarInteractions': false,
    });

    final ok = await saveNodes(_questId, [nodeWithoutSettings()]);
    expect(ok, isTrue);

    final stored = await storedNode();
    for (final key in SavedNode.legacyKeys) {
      expect(
        stored.containsKey(key),
        isFalse,
        reason: '$key остался в nodes.json, хотя модель его не читает',
      );
    }
  });

  test('ключ, которого нет в модели, сохраняется', () async {
    await seedStoredNode({'futureField': 7});

    final ok = await saveNodes(_questId, [nodeWithoutSettings()]);
    expect(ok, isTrue);

    final stored = await storedNode();
    expect(stored['futureField'], 7);
  });

  test('значение, которое модель сериализует, перезаписывается', () async {
    await seedStoredNode({'backgroundBlur': 12.0, 'transitionMode': 'fade'});

    final ok = await saveNodes(
      _questId,
      [
        SavedNode(
          id: 'n1',
          chapterId: 'c1',
          title: 'Нода',
          content: const {'items': []},
          x: 10,
          y: 20,
          backgroundBlur: 0,
          transitionMode: 'slide',
        ),
      ],
    );
    expect(ok, isTrue);

    final stored = await storedNode();
    expect(stored['backgroundBlur'], 0.0);
    expect(stored['transitionMode'], 'slide');
  });
}
