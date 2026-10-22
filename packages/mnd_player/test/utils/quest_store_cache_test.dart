// Ядро пишет файлы мимо FileStorage, а его кэш JSON этого не замечает.
// Переименование переменной коммитится именно транзакцией ядра
// (`RefactoringService` → `QuestStore.transact`), поэтому без сброса кэша
// экран переменных продолжал показывать старое имя — а следующая запись
// config.json возвращала на диск старый снимок.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/quest_store.dart';

final String? _soPath = () {
  final env = Platform.environment['MND_FFI_SO'];
  if (env != null && File(env).existsSync()) return env;
  for (final candidate in [
    '../../target/release/libmnd_ffi.so',
    '../../crates/mnd-ffi/target/release/libmnd_ffi.so',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}();

void main() {
  late Directory appDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (_soPath != null) {
      await initRustCore(externalLibrary: ExternalLibrary.open(_soPath!));
    }
    appDir = await Directory.systemTemp.createTemp('mnd_store_cache_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? appDir.path
              : null,
        );
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  test('транзакция ядра обновляет кэш FileStorage', () async {
    const path = 'quests/q1/config.json';
    await FileStorage.writeJsonFile(path, {
      'variables': [
        {'name': 'старое'},
      ],
    });
    // Разогреть кэш чтением — именно он и оставлял старое имя.
    final before = await FileStorage.readJsonFile(path);
    expect(
      ((before['variables'] as List).first as Map)['name'],
      'старое',
    );

    final store = await QuestStore.forRoot(appDir.path);
    expect(store.rustBackend, isTrue, reason: 'нужен собранный .so');
    await store.transact([
      QuestOp.writeJson(path, {
        'variables': [
          {'name': 'новое'},
        ],
      }),
    ]);

    final after = await FileStorage.readJsonFile(path);
    expect(((after['variables'] as List).first as Map)['name'], 'новое');
  }, skip: _soPath == null);

  test('мутация metadata обновляет кэш FileStorage', () async {
    const questId = 'q2';
    final path = QuestPaths.metadata(questId);
    await FileStorage.writeJsonFile(path, {'a.png': {'name': 'раз'}});
    await FileStorage.readJsonFile(path);

    final store = await QuestStore.forRoot(appDir.path);
    await store.metadataMutate(questId, [
      const MetaMut.set('a.png', {'name': 'два'}),
    ]);

    final after = await FileStorage.readJsonFile(path);
    expect((after['a.png'] as Map)['name'], 'два');
  }, skip: _soPath == null);
}
