// Кэш облачной синхронизации: «этот квест уже лежит на сервере в этих байтах».
//
// Без него syncAll пакует каждый квест в .mnd и хешует весь архив (включая
// ассеты) на каждом прогоне — отсюда жалоба «синхронизация пиздец долгая, хотя
// сервер быстрый». Пропуск изменения при этом хуже лишней паковки, поэтому
// здесь проверяется именно чувствительность подписи: любые правки — в том
// числе сохранённые внешним инструментом с прежней датой и длиной — должны
// сбрасывать кэш.

import 'dart:io';

import 'package:canvas_app/core/services/cloud_sync_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _questId = '11111111-2222-4333-8444-555555555555';

QuestFileEntry _entry(
  String relPath, {
  int length = 10,
  int mtime = 1000,
  String? contentHash,
}) => QuestFileEntry(
  relPath: relPath,
  lengthBytes: length,
  mtimeMicros: mtime,
  contentHash: contentHash,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('подпись каталога', () {
    test('порядок файлов не важен, состав важен', () {
      final a = signatureOfFiles([
        _entry('config.json', contentHash: 'x'),
        _entry('res/a.png', contentHash: null),
      ]);
      final b = signatureOfFiles([
        _entry('res/a.png'),
        _entry('config.json', contentHash: 'x'),
      ]);
      expect(a, b);
      expect(
        signatureOfFiles([_entry('config.json', contentHash: 'x')]),
        isNot(a),
      );
    });

    test('любая перемена одного поля меняет подпись', () {
      final base = signatureOfFiles([
        _entry('config.json', length: 10, mtime: 1000, contentHash: 'x'),
      ]);
      expect(
        signatureOfFiles([
          _entry('config.json', length: 11, mtime: 1000, contentHash: 'x'),
        ]),
        isNot(base),
        reason: 'длина файла не повлияла на подпись',
      );
      expect(
        signatureOfFiles([
          _entry('config.json', length: 10, mtime: 1001, contentHash: 'x'),
        ]),
        isNot(base),
        reason: 'дата файла не повлияла на подпись',
      );
      expect(
        signatureOfFiles([
          _entry('config.json', length: 10, mtime: 1000, contentHash: 'y'),
        ]),
        isNot(base),
        reason: 'содержимое не повлияло на подпись',
      );
    });

    test('имя пути отличается — подпись отличается', () {
      expect(
        signatureOfFiles([_entry('nodes.json')]),
        isNot(signatureOfFiles([_entry('nodes/nodes.json')])),
      );
    });
  });

  group('сбор подписи с диска', () {
    late Directory appDir;
    late String questDir;

    setUp(() async {
      appDir = await Directory.systemTemp.createTemp('mnd_cloud_sync_state');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return appDir.path;
            }
            return null;
          });
      questDir = p.join(appDir.path, 'quests', _questId);
      await Directory(questDir).create(recursive: true);
      await _write(p.join(questDir, 'config.json'), '{"title":"A"}');
      await _write(p.join(questDir, 'nodes', 'nodes.json'), '[1,2,3]');
      await _write(p.join(questDir, 'res', 'bg.png'), 'PNG' * 100);
    });

    tearDown(() async {
      await appDir.delete(recursive: true);
    });

    test('одинаковый каталог — одинаковая подпись', () async {
      expect(await questSignature(questDir), await questSignature(questDir));
    });

    test('нет каталога — нет подписи', () async {
      expect(
        await questSignature(p.join(appDir.path, 'quests', 'nope')),
        isNull,
      );
    });

    test(
      'правка config.json с прежней датой и длиной всё равно видна',
      () async {
        final before = await questSignature(questDir);
        final config = File(p.join(questDir, 'config.json'));
        final originalMtime = config.statSync().modified;
        // «{"title":"B"}»: тот же размер, другой байт, дата возвращена —
        // как если бы файл восстановили из архива с сохранением меток.
        await config.writeAsString('{"title":"B"}');
        config.setLastModifiedSync(originalMtime);
        expect(await questSignature(questDir), isNot(before));
      },
    );

    test('новый ассет меняет подпись', () async {
      final before = await questSignature(questDir);
      await _write(p.join(questDir, 'res', 'snd.ogg'), 'OGG');
      expect(await questSignature(questDir), isNot(before));
    });

    test('сохранение игры в saves/ подпись не сбрасывает', () async {
      final before = await questSignature(questDir);
      await _write(p.join(questDir, 'saves', 'slot1.json'), '{"hp":1}');
      expect(await questSignature(questDir), before);
    });
  });

  group('хэш подтверждённых отпечатков', () {
    test('совпали подпись и отпечаток сервера — есть консервация', () {
      final state = CloudSyncCache();
      state.remember(_questId, signature: 'sig-1', fingerprint: 'fp-1');
      expect(
        state.confirmedFingerprint(
          questId: _questId,
          signature: 'sig-1',
          remoteFingerprint: 'fp-1',
        ),
        'fp-1',
      );
    });

    test('любое расхождение — не консервируем', () {
      final state = CloudSyncCache();
      state.remember(_questId, signature: 'sig-1', fingerprint: 'fp-1');
      expect(
        state.confirmedFingerprint(
          questId: _questId,
          signature: 'sig-2',
          remoteFingerprint: 'fp-1',
        ),
        isNull,
        reason: 'локальный квест изменился, но кэш позволил его пропустить',
      );
      expect(
        state.confirmedFingerprint(
          questId: _questId,
          signature: 'sig-1',
          remoteFingerprint: 'fp-other',
        ),
        isNull,
        reason: 'на сервере другая версия, но кэш позволил её пропустить',
      );
      expect(
        state.confirmedFingerprint(
          questId: 'other',
          signature: 'sig-1',
          remoteFingerprint: 'fp-1',
        ),
        isNull,
      );
      expect(
        state.confirmedFingerprint(
          questId: _questId,
          signature: null,
          remoteFingerprint: 'fp-1',
        ),
        isNull,
      );
      expect(
        state.confirmedFingerprint(
          questId: _questId,
          signature: 'sig-1',
          remoteFingerprint: null,
        ),
        isNull,
      );
    });

    test('remember без подписи ничего не записывает', () {
      final state = CloudSyncCache();
      state.remember(_questId, signature: null, fingerprint: 'fp-1');
      expect(state.length, 0);
    });

    test('forget и prune чистят записи', () {
      final state = CloudSyncCache();
      state.remember('a', signature: 'sa', fingerprint: 'fa');
      state.remember('b', signature: 'sb', fingerprint: 'fb');
      state.forget('a');
      expect(state.length, 1);
      state.prune(['b', 'c']);
      expect(state.length, 1);
      state.prune(['c']);
      expect(state.length, 0);
    });
  });

  group('файл состояния', () {
    late Directory appDir;

    setUp(() async {
      appDir = await Directory.systemTemp.createTemp('mnd_cloud_sync_store');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return appDir.path;
            }
            return null;
          });
    });

    tearDown(() async {
      await appDir.delete(recursive: true);
    });

    test('save/load — круговой', () async {
      final state = CloudSyncCache();
      state.remember(_questId, signature: 'sig-1', fingerprint: 'fp-1');
      await state.save();

      final reloaded = await CloudSyncCache.load();
      expect(
        reloaded.confirmedFingerprint(
          questId: _questId,
          signature: 'sig-1',
          remoteFingerprint: 'fp-1',
        ),
        'fp-1',
      );
    });

    test('без файла — пустое состояние, не падает', () async {
      expect((await CloudSyncCache.load()).length, 0);
    });

    test(
      'битый файл — пустое состояние, синхронизация не блокируется',
      () async {
        final file = File(
          p.join(appDir.path, 'app', 'sync', 'cloud_sync_state.json'),
        );
        await file.create(recursive: true);
        await file.writeAsString('это не json');
        expect((await CloudSyncCache.load()).length, 0);
      },
    );
  });
}

Future<void> _write(String path, String content) async {
  final file = File(path);
  await file.create(recursive: true);
  await file.writeAsString(content);
}
