import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Сервис для асинхронной работы с бэкапами, поддерживающий большие файлы
class AsyncBackupService {
  /// Создает ZIP-архив со всеми квестами и предлагает его сохранить.
  static Future<bool> createBackup({
    required Function(String status) onProgress,
    required Function(double progress) onProgressUpdate,
  }) async {
    try {
      onProgress(tr('Поиск локальных квестов...'));

      final questsPath = await FileStorage.getFilePath(QuestPaths.questsDir);
      final questsDir = Directory(questsPath);

      if (!await questsDir.exists() || await questsDir.list().isEmpty) {
        throw Exception(tr('Нет квестов для создания резервной копии.'));
      }

      final questDirs = await questsDir.list(recursive: false).toList();
      final totalQuests = questDirs.length;

      onProgress(tr('Создание архива...'));
      final archive = Archive();

      for (int i = 0; i < questDirs.length; i++) {
        final entity = questDirs[i];
        if (entity is Directory) {
          final questId = p.basename(entity.path);
          onProgress(trf('Добавление квеста "{questId}"...', {'questId': questId}));

          await _addDirectoryToArchiveAsync(archive, entity, questId);

          // Обновляем прогресс
          onProgressUpdate((i + 1) / totalQuests);

          // Даем возможность UI обновиться
          await Future.delayed(Duration.zero);
        }
      }

      onProgress(tr('Сжатие данных...'));
      onProgressUpdate(0.95);

      final zipData = ZipEncoder().encode(archive);

      onProgress(tr('Сохранение файла...'));
      onProgressUpdate(0.98);

      final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
      final fileName = 'meander_backup_$timestamp.zip';

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final result = await FilePicker.saveFile(
          dialogTitle: 'Save backup',
          fileName: fileName,
          bytes: Uint8List.fromList(zipData),
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );

        if (result == null) {
          return false;
        }

        onProgressUpdate(1.0);
        return true;
      }

      final tempDir = await getTemporaryDirectory();
      final tempFilePath = p.join(tempDir.path, fileName);
      final tempFile = File(tempFilePath);
      await tempFile.writeAsBytes(zipData);

      final params = SaveFileDialogParams(
        sourceFilePath: tempFile.path,
        fileName: fileName,
      );
      final result = await FlutterFileDialog.saveFile(params: params);

      await tempFile.delete();
      onProgressUpdate(1.0);

      return result != null;
    } catch (e) {
      print('❌ Ошибка создания бэкапа: $e');
      rethrow;
    }
  }

  /// Восстанавливает квесты из выбранного ZIP-архива.
  static Future<bool> restoreFromBackup({
    required Function(String status) onProgress,
    required Function(double progress) onProgressUpdate,
    required Future<bool> Function(String questTitle) onConflict,
  }) async {
    // Шаг 1: Выбор файла
    onProgress(tr('Выберите файл бэкапа (.zip)...'));
    onProgressUpdate(0.0);

    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (files.isEmpty || files.single.path == null) {
      return false; // Пользователь отменил выбор
    }
    final filePath = files.single.path!;

    // Шаг 2: Распаковка и подготовка
    onProgress(tr('Чтение архива...'));
    onProgressUpdate(0.05);

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final questsPath = await FileStorage.getFilePath(QuestPaths.questsDir);
    final localQuestIds = await FileStorage.listFolders(QuestPaths.questsDir);

    // Шаг 3: Анализ конфликтов и восстановление
    // Группируем файлы по директориям квестов
    final Map<String, List<ArchiveFile>> questsInArchive = {};
    for (final file in archive) {
      final parts = p.split(file.name);
      if (parts.isNotEmpty) {
        final questId = parts.first;
        questsInArchive.putIfAbsent(questId, () => []).add(file);
      }
    }

    final totalQuests = questsInArchive.length;
    int processedQuests = 0;

    for (final entry in questsInArchive.entries) {
      final questId = entry.key;
      final questFiles = entry.value;

      // Ищем конфиг, чтобы узнать название
      ArchiveFile? configEntry;
      try {
        configEntry = questFiles.firstWhere(
          (f) => p.basename(f.name) == 'config.json',
        );
      } catch (_) {}

      String questTitle = questId;
      if (configEntry != null) {
        try {
          final config = jsonDecode(
            utf8.decode(configEntry.content as List<int>),
          );
          questTitle = config['title'] ?? questId;
        } catch (_) {}
      }

      if (localQuestIds.contains(questId)) {
        // Конфликт!
        onProgress(trf('Обнаружен конфликт: "{questTitle}"', {'questTitle': questTitle}));

        final shouldReplace = await onConflict(questTitle);
        if (!shouldReplace) {
          onProgress(trf('Пропуск квеста "{questTitle}"...', {'questTitle': questTitle}));
          processedQuests++;
          onProgressUpdate(
            processedQuests / totalQuests * 0.9,
          ); // 90% на восстановление
          continue;
        }

        onProgress(trf('Замена квеста "{questTitle}"...', {'questTitle': questTitle}));
        // Удаляем старую папку целиком перед записью новой
        final targetDir = Directory(p.join(questsPath, questId));
        if (await targetDir.exists()) {
          await targetDir.delete(recursive: true);
        }
      } else {
        onProgress(trf('Восстановление "{questTitle}"...', {'questTitle': questTitle}));
      }

      // Восстановление файлов
      final questFileCount = questFiles.length;
      for (int i = 0; i < questFileCount; i++) {
        final file = questFiles[i];
        final targetPath = p.join(questsPath, file.name);

        if (file.isFile) {
          final outFile = File(targetPath);
          await outFile.parent.create(recursive: true);

          // Исправление бага: принудительно удаляем файл, если он есть (на всякий случай)
          if (await outFile.exists()) {
            await outFile.delete();
          }

          // ВАЖНО: flush: true гарантирует запись на диск, решая проблему кэширования
          await outFile.writeAsBytes(file.content as List<int>, flush: true);
        } else {
          await Directory(targetPath).create(recursive: true);
        }

        // Обновляем прогресс внутри восстановления квеста
        if ((i + 1) % 50 == 0) {
          // Обновляем каждые 50 файлов
          double questProgress = (i + 1) / questFileCount;
          double overallProgress =
              (processedQuests + questProgress / totalQuests) /
              totalQuests *
              0.9;
          onProgressUpdate(overallProgress);

          // Даем возможность UI обновиться
          await Future.delayed(Duration.zero);
        }
      }

      processedQuests++;
      onProgressUpdate(
        processedQuests / totalQuests * 0.9,
      ); // 90% на восстановление
    }

    onProgress(tr('Завершено!'));
    onProgressUpdate(1.0);

    return true;
  }

  /// Вспомогательная рекурсивная функция для добавления директории в архив асинхронно.
  static Future<void> _addDirectoryToArchiveAsync(
    Archive archive,
    Directory dir,
    String parentPath,
  ) async {
    final entities = await dir.list(recursive: false).toList();

    for (final entity in entities) {
      final entityName = p.basename(entity.path);
      final archivePath = p.join(parentPath, entityName);

      if (entity is File) {
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
      } else if (entity is Directory) {
        await _addDirectoryToArchiveAsync(archive, entity, archivePath);
      }
    }
  }
}
