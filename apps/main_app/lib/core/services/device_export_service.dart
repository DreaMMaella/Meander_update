import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Один файл, который автор просит вынести на устройство.
class DeviceExportItem {
  /// Как положить файл в папке/архиве — с расширением, чтобы ОС узнала тип.
  final String fileName;

  /// Абсолютный путь внутри песочницы приложения.
  final String sourcePath;

  const DeviceExportItem({required this.fileName, required this.sourcePath});
}

/// Экспорт ресурсов из песочницы квеста наружу (#149): картинку, звук или
/// видео можно забрать к себе, не выкачивая весь квест в .mnd.
///
/// Десктоп выбирает папку и копирует стримом — ассеты весят сотни мегабайт,
/// а `FilePicker.saveFile(bytes:)` положил бы весь файл в RAM. На телефоне
/// работает системный диалог сохранения.
class DeviceExportService {
  const DeviceExportService._();

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Сохранить один файл. `false` — автор отменил диалог или файл пропал.
  static Future<bool> exportOne(DeviceExportItem item) async {
    if (!await File(item.sourcePath).exists()) return false;
    if (_isDesktop) {
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: tr('Куда сохранить файлы'),
      );
      if (dir == null) return false;
      return _copyStream(
        item.sourcePath,
        p.join(dir, await freeNameInDir(dir, item.fileName)),
      );
    }
    final saved = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        sourceFilePath: item.sourcePath,
        fileName: item.fileName,
      ),
    );
    return saved != null;
  }

  /// Сохранить несколько файлов одним архивом: на телефоне диалог один за раз,
  /// а россыпь файлов на десктопе перемешалась бы с чужими.
  static Future<bool> exportZip(
    List<DeviceExportItem> items, {
    required String zipName,
  }) async {
    final present = <DeviceExportItem>[];
    for (final item in items) {
      if (await File(item.sourcePath).exists()) present.add(item);
    }
    // Ни одного файла не добавилось (всё удалили из квеста, пока выбирали) —
    // пустой архив предлагать нельзя.
    if (present.isEmpty) return false;

    final tempDir = await getTemporaryDirectory();
    final tempZip = File(
      p.join(
        tempDir.path,
        'export_${DateTime.now().millisecondsSinceEpoch}.zip',
      ),
    );
    final names = uniqueNames(present.map((i) => i.fileName));
    final encoder = ZipFileEncoder();
    encoder.createWithStream(OutputFileStream(tempZip.path));
    try {
      for (var i = 0; i < present.length; i++) {
        await encoder.addFile(File(present[i].sourcePath), names[i]);
      }
      await encoder.close();
      return await exportOne(
        DeviceExportItem(fileName: zipName, sourcePath: tempZip.path),
      );
    } finally {
      try {
        await encoder.close();
      } catch (_) {}
      try {
        if (await tempZip.exists()) await tempZip.delete();
      } catch (_) {}
    }
  }

  /// Имя для файла внутри архива: виртуальная папка квеста сохраняется,
  /// иначе двенадцать «1.png» из разных папок нечем было бы различить.
  static String archiveName({
    required String folder,
    required String fileName,
  }) {
    final clean = folder.replaceAll(RegExp(r'^/+|/+$'), '');
    return clean.isEmpty ? fileName : '$clean/$fileName';
  }

  /// «1.png», «1.png» → «1.png», «1 (2).png» — и в архиве, и в выбранной
  /// папке: перезапись чужого файла молча стоила бы автору работы.
  static List<String> uniqueNames(Iterable<String> names) {
    final taken = <String>{};
    return [for (final name in names) dedupeName(taken, name)].toList();
  }

  static String dedupeName(Set<String> taken, String fileName) {
    if (taken.add(fileName)) return fileName;
    final ext = p.extension(fileName);
    final base = fileName.substring(0, fileName.length - ext.length);
    for (var n = 2; ; n++) {
      if (taken.add('$base ($n)$ext')) return '$base ($n)$ext';
    }
  }

  static Future<String> freeNameInDir(String dir, String fileName) async {
    final taken = <String>{};
    try {
      await for (final entity in Directory(dir).list()) {
        taken.add(p.basename(entity.path));
      }
    } catch (_) {
      return fileName;
    }
    return dedupeName(taken, fileName);
  }

  static Future<bool> _copyStream(String from, String to) async {
    final sink = File(to).openWrite();
    try {
      await sink.addStream(File(from).openRead());
      return true;
    } finally {
      await sink.close();
    }
  }
}
