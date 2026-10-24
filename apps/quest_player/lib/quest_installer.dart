import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/key_derivation_service.dart';
import 'package:path/path.dart' as p;

/// Распаковывает вшитый в APK `assets/quest/quest.mnd` в хранилище плеера.
///
/// Распаковка повторяется только при смене файла квеста (сверка по sha256),
/// поэтому сохранения игрока переживают перезапуски и обновления APK с тем
/// же квестом.
class QuestInstaller {
  QuestInstaller._();

  static const String assetPath = 'assets/quest/quest.mnd';
  static const String _markerPath = 'quest_player/installed.json';
  static const int _headerLength = 8;
  static final List<int> _securedHeader = utf8.encode('MND_SEC_');
  static final List<int> _legacyEncryptedHeader = utf8.encode('MND_ENC_');
  static final List<int> _zipHeader = utf8.encode('MND_ZIP_');

  static Future<String> installBundledQuest({bool force = false}) async {
    final Uint8List bytes;
    try {
      final data = await rootBundle.load(assetPath);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      throw const QuestInstallException(
        'В сборку не вложен квест. Соберите APK через '
        'scripts/build_quest_apk.sh путь/к/квесту.mnd',
      );
    }

    final hash = sha256.convert(bytes).toString();
    if (!force) {
      final installedId = await _readInstalledQuestId(hash);
      if (installedId != null) return installedId;
    }

    final archive = _decodeArchive(bytes);
    final questId = await _extract(archive);
    await FileStorage.createFolder(p.posix.dirname(_markerPath));
    await FileStorage.writeJsonFile(_markerPath, {
      'questId': questId,
      'sha256': hash,
    });
    return questId;
  }

  static Future<String?> _readInstalledQuestId(String hash) async {
    try {
      if (!await FileStorage.exists(_markerPath)) return null;
      final marker = await FileStorage.readJsonFile(_markerPath);
      final questId = marker['questId'] as String?;
      if (marker['sha256'] != hash || questId == null) return null;
      if (!await FileStorage.exists(QuestPaths.config(questId))) return null;
      return questId;
    } catch (_) {
      return null;
    }
  }

  static Archive _decodeArchive(Uint8List bytes) {
    const listEquals = ListEquality<int>();
    final header = bytes.length > _headerLength
        ? bytes.sublist(0, _headerLength)
        : null;

    if (header != null && listEquals.equals(header, _legacyEncryptedHeader)) {
      throw const QuestInstallException(
        'Квест сохранён в устаревшем формате MND_ENC_. '
        'Пересохраните его в актуальной версии Meander.',
      );
    }

    final isPlainZip = header != null && listEquals.equals(header, _zipHeader);
    final isSecured =
        header != null && listEquals.equals(header, _securedHeader);
    final payload = (isPlainZip || isSecured)
        ? bytes.sublist(_headerLength)
        : bytes;

    if (!isPlainZip) {
      try {
        final decrypted = KeyDerivationService.decryptProtectedQuestData(
          payload,
        );
        return ZipDecoder().decodeBytes(decrypted);
      } catch (_) {
        // Не зашифрован — пробуем как обычный ZIP ниже.
      }
    }

    try {
      return ZipDecoder().decodeBytes(payload);
    } catch (_) {
      throw const QuestInstallException(
        'Файл квеста повреждён или не является квестом Meander.',
      );
    }
  }

  static Future<String> _extract(Archive archive) async {
    String normalize(String name) => name.replaceAll('\\', '/');

    final configEntry = archive.files.firstWhereOrNull(
      (f) => f.isFile && p.posix.basename(normalize(f.name)) == 'config.json',
    );
    if (configEntry == null) {
      throw const QuestInstallException(
        'В архиве нет config.json — это не квест Meander.',
      );
    }

    final config = jsonDecode(utf8.decode(configEntry.content as List<int>));
    final questId = config is Map ? config['id'] as String? : null;
    if (questId == null || questId.isEmpty) {
      throw const QuestInstallException('В config.json не указан id квеста.');
    }

    final rootPrefix = p.posix.dirname(normalize(configEntry.name));
    final questRootRelative = QuestPaths.questRoot(questId);
    final questRoot = await FileStorage.getFilePath(questRootRelative);
    final questRootDir = Directory(questRoot);
    if (await questRootDir.exists()) {
      await questRootDir.delete(recursive: true);
    }
    await questRootDir.create(recursive: true);
    final canonicalRoot = p.canonicalize(questRoot);

    for (final entry in archive.files) {
      var name = normalize(entry.name);
      if (rootPrefix != '.') {
        if (!name.startsWith('$rootPrefix/')) continue;
        name = name.substring(rootPrefix.length + 1);
      }
      if (name.isEmpty) continue;

      final target = p.canonicalize(p.join(questRoot, name));
      // Защита от zip-slip: записи с «../» не должны выходить за каталог.
      if (!p.isWithin(canonicalRoot, target)) continue;

      if (entry.isFile) {
        final file = File(target);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content as List<int>, flush: true);
      } else {
        await Directory(target).create(recursive: true);
      }
    }

    final configRelative = QuestPaths.config(questId);
    final storedConfig = await FileStorage.readJsonFile(configRelative);
    storedConfig['lastOpened'] = null;
    await FileStorage.writeJsonFile(configRelative, storedConfig);

    return questId;
  }
}

class QuestInstallException implements Exception {
  const QuestInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}
