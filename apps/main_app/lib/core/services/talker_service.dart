import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // Нужно для kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Глобальный инстанс Talker
final talker = TalkerFlutter.init(
  settings: TalkerSettings(
    // --- ИСПРАВЛЕНИЕ ---
    // Talker будет включен ТОЛЬКО если это НЕ дебаг режим.
    // В Debug режиме он отключится, и логи будут нормально видны в консоли VS Code
    // благодаря parent.print в main.dart.
    enabled: !kDebugMode,

    maxHistoryItems: 1000,

    // Оставляем false, так как в main.dart есть свой перехватчик print,
    // и мы не хотим дублирования в релизе.
    useConsoleLogs: false,
  ),
);

final talkerProvider = Provider((ref) => talker);

class TalkerExportService {
  static Future<void> exportAndShareLogs(BuildContext context) async {
    try {
      final history = talker.history;
      final StringBuffer buffer = StringBuffer();

      buffer.writeln('=== MEANDER APP LOGS ===');
      buffer.writeln('Generated: ${DateTime.now()}');
      buffer.writeln('Total logs: ${history.length}');
      buffer.writeln('========================\n');

      for (final log in history) {
        buffer.writeln(log.generateTextMessage());
        buffer.writeln('-' * 20);
      }

      final dir = await getTemporaryDirectory();
      final fileName =
          'meander_logs_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('${dir.path}/$fileName');

      await file.writeAsString(buffer.toString());

      // share_plus на десктопе файлы не отдаёт: Linux кидает
      // UnimplementedError, ошибка проваливалась в общий catch ниже, и
      // человек не видел ничего. Тот же путь, что у экспорта .mnd —
      // системный «сохранить как».
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final saved = await FilePicker.saveFile(
          dialogTitle: tr('Сохранить логи'),
          fileName: fileName,
          bytes: await file.readAsBytes(),
          type: FileType.custom,
          allowedExtensions: ['txt'],
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                saved == null
                    ? tr('Сохранение отменено')
                    : trf('Логи сохранены: {saved}', {'saved': saved}),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final xFile = XFile(file.path);

      if (context.mounted) {
        await Share.shareXFiles([xFile], text: tr('Логи приложения Meander'));
      }
    } catch (e, st) {
      // Используем handle, он безопасен
      talker.handle(e, st, 'Ошибка экспорта логов');
    }
  }
}
