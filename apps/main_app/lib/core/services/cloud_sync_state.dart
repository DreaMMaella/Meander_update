// Локальный кэш облачной синхронизации: какие байты квеста уже лежат на
// сервере и менялись ли они с того момента.
//
// Мотивация: `syncAll` на каждом прогоне паковал каждый пользовательский квест
// в `.mnd` (Rust-стрим по всему каталогу, включая ассеты) и считает SHA-256
// готового архива в главном isolate — только чтобы сервер ответил
// `sameFingerprint`. Для библиотеки из десятков квестов это и есть «синхронизация
// пиздец долгая»: работа пропорциональна объёму ассетов, а не объёму изменений.
//
// Здесь хранится подпись каталога и отпечаток, который сервер подтверждал. Если
// подпись не изменилась И сервер по-прежнему держит тот же отпечаток — квест не
// пакуется вообще.
//
// Пропуск реального изменения хуже лишней паковки, поэтому подпись избыточна:
// (путь, размер, mtime) всех файлов архива + содержимое текстовых файлов,
// которые правляются не только из приложения.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:path/path.dart' as p;

/// Один файл каталога квеста, как его видит подписчик.
class QuestFileEntry {
  final String relPath;
  final int lengthBytes;
  final int mtimeMicros;

  /// SHA-1 содержимого — только для файлов из [contentHashedRelPaths].
  final String? contentHash;

  const QuestFileEntry({
    required this.relPath,
    required this.lengthBytes,
    required this.mtimeMicros,
    this.contentHash,
  });

  String get signaturePart =>
      '$relPath|$lengthBytes|$mtimeMicros|${contentHash ?? ''}';
}

/// Файлы, чьему mtime мы не верим: их может перезаписать внешний инструмент,
/// сохранив дату. Содержимое таких файлов хешается целиком.
const Set<String> contentHashedRelPaths = {
  'config.json',
  'nodes.json',
  'nodes/nodes.json',
};

/// Относительный путь `saves/` — в `.mnd` не попадает (см.
/// `create_zip_streaming_full`), значит и в подписи его быть не должно:
/// иначе каждая игровая сессия сбрасывала бы кэш.
bool isArchivedRelPath(String relPath) =>
    relPath != 'saves' && !relPath.startsWith('saves/');

/// Чистая часть подписи: порядок файлов не важен, любое изменение пути,
/// размера, даты или контрольного содержимого меняет результат.
String signatureOfFiles(Iterable<QuestFileEntry> entries) {
  final parts = entries.map((e) => e.signaturePart).toList()..sort();
  return sha1.convert(utf8.encode(parts.join('\n'))).toString();
}

/// Подпись каталога квеста по абсолютному пути. `null` — каталога нет или он
/// пуст (тогда консервировать нечего, пакуем как раньше).
Future<String?> questSignature(String questDirAbsPath) async {
  final dir = Directory(questDirAbsPath);
  if (!await dir.exists()) return null;

  final entries = <QuestFileEntry>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = p
        .relative(entity.path, from: questDirAbsPath)
        .replaceAll(r'\', '/');
    if (!isArchivedRelPath(rel)) continue;
    final stat = await entity.stat();
    entries.add(
      QuestFileEntry(
        relPath: rel,
        lengthBytes: stat.size,
        mtimeMicros: stat.modified.microsecondsSinceEpoch,
        contentHash: contentHashedRelPaths.contains(rel)
            ? sha1.convert(await entity.readAsBytes()).toString()
            : null,
      ),
    );
  }
  if (entries.isEmpty) return null;
  return signatureOfFiles(entries);
}

/// Запись о том, что сервер подтвердил: у квеста лежит вот эти байты.
class CloudQuestRecord {
  final String signature;
  final String fingerprint;

  const CloudQuestRecord({required this.signature, required this.fingerprint});

  Map<String, dynamic> toMap() => {
    'signature': signature,
    'fingerprint': fingerprint,
  };

  static CloudQuestRecord? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final signature = raw['signature']?.toString();
    final fingerprint = raw['fingerprint']?.toString();
    if (signature == null || fingerprint == null) return null;
    return CloudQuestRecord(signature: signature, fingerprint: fingerprint);
  }
}

class CloudSyncCache {
  static const _path = 'app/sync/cloud_sync_state.json';

  final Map<String, CloudQuestRecord> _records;

  CloudSyncCache([Map<String, CloudQuestRecord>? records])
    : _records = records ?? <String, CloudQuestRecord>{};

  int get length => _records.length;

  /// Отпечаток, который сервер подтверждал для этого же содержимого.
  ///
  /// Возвращает строку только когда совпадают три вещи: локальная подпись
  /// каталога, подпись из кэша и отпечаток из свежего списка облака. Любая
  /// неопределённость (нет каталога, сервер не прислал отпечаток, квест в
  /// облаке другой версии) — `null`, то есть пакуем по-старому.
  String? confirmedFingerprint({
    required String questId,
    required String? signature,
    required String? remoteFingerprint,
  }) {
    if (signature == null || remoteFingerprint == null) return null;
    final record = _records[questId];
    if (record == null) return null;
    if (record.signature != signature) return null;
    if (record.fingerprint != remoteFingerprint) return null;
    return record.fingerprint;
  }

  void remember(
    String questId, {
    required String? signature,
    required String fingerprint,
  }) {
    if (signature == null) return;
    _records[questId] = CloudQuestRecord(
      signature: signature,
      fingerprint: fingerprint,
    );
  }

  void forget(String questId) => _records.remove(questId);

  /// Записи удалённых/переехавших квестов не должны вечно жить в файле.
  void prune(Iterable<String> keepQuestIds) {
    final keep = keepQuestIds.toSet();
    _records.removeWhere((id, _) => !keep.contains(id));
  }

  static Future<CloudSyncCache> load() async {
    try {
      if (!await FileStorage.exists(_path)) return CloudSyncCache();
      final json = await FileStorage.readJsonFile(_path);
      final quests = json['quests'];
      if (quests is! Map) return CloudSyncCache();
      final records = <String, CloudQuestRecord>{};
      quests.forEach((rawId, raw) {
        final record = CloudQuestRecord.fromMap(raw);
        if (record != null) records[rawId.toString()] = record;
      });
      return CloudSyncCache(records);
    } catch (_) {
      return CloudSyncCache();
    }
  }

  Future<void> save() async {
    try {
      await FileStorage.writeJsonFile(_path, {
        'version': 1,
        'quests': _records.map((id, r) => MapEntry(id, r.toMap())),
      });
    } catch (_) {}
  }
}

/// Абсолютный путь каталога квеста — чтобы подписчик не знал про FileStorage.
Future<String> questDirAbsPath(String questId) =>
    FileStorage.getFilePath(QuestPaths.questRoot(questId));

/// Подпись каталога квеста по его id. Ошибка чтения = `null` (пакуем как
/// раньше): кэш не должен уметь блокировать синхронизацию.
Future<String?> questSignatureById(String questId) async {
  try {
    return await questSignature(await questDirAbsPath(questId));
  } catch (_) {
    return null;
  }
}
