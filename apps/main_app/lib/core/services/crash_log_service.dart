/// Запись ошибок приложения в файл — чтобы причина падения/зависания
/// всегда была доступна для анализа (даже если приложение вылетело
/// и консоль недоступна).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mnd_player/utils/file_storage.dart';

class CrashLogService {
  CrashLogService._();

  static final List<String> _pending = [];
  static String? _filePath;
  static bool _writing = false;
  static bool _inLog = false;

  static const int _maxFileBytes = 2 * 1024 * 1024;

  static Future<String?> _ensureFile() async {
    if (_filePath != null) return _filePath;
    try {
      final dir = await FileStorage.getAppDirectory();
      final file = File('${dir.path}/crash_log.txt');
      _filePath = file.path;
      return _filePath;
    } catch (e) {
      debugPrint('[CrashLog] не удалось открыть файл: $e');
      return null;
    }
  }

  /// Синхронная запись в буфер + асинхронный flush на диск.
  static void log(String message, {Object? error, StackTrace? stack}) {
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer('[$now] $message');
    if (error != null) {
      buffer.write('\n  error: $error');
    }
    if (stack != null) {
      final lines = stack.toString().split('\n').take(15).join('\n');
      buffer.write('\n  stack:\n$lines');
    }
    _pending.add(buffer.toString());
    // Защита от рекурсии log→debugPrint→(перехваченный debugPrint)→log:
    // если log уже исполняется, вложенный вызов пишет только в буфер и НЕ
    // трогает debugPrint — иначе при подмене debugPrint это бесконечный цикл
    // с раздуванием _pending до гигабайтов (именно он и вешал приложение).
    if (_inLog) {
      unawaited(_flush());
      return;
    }
    _inLog = true;
    try {
      debugPrint('[CrashLog] $message${error != null ? ' → $error' : ''}');
    } finally {
      _inLog = false;
    }
    unawaited(_flush());
  }

  /// Пишет строку в лог-файл БЕЗ echo в debugPrint.
  ///
  /// Нужен для перехвата debugPrint в обработчике ошибок: [log] сам вызывает
  /// debugPrint, поэтому перехват обязан писать напрямую, а не через [log],
  /// иначе получится log→debugPrint→log (бесконечная рекурсия).
  static void writeRaw(String message) {
    final now = DateTime.now().toIso8601String();
    _pending.add('[$now] $message');
    unawaited(_flush());
  }

  static Future<void> _flush() async {
    if (_writing) return;
    _writing = true;
    try {
      final path = await _ensureFile();
      if (path == null) return;
      while (_pending.isNotEmpty) {
        final entry = _pending.removeAt(0);
        final file = File(path);
        try {
          if (await file.exists() && await file.length() > _maxFileBytes) {
            final backup = File('$path.old');
            await file.copy(backup.path);
            await file.delete();
          }
          await file.writeAsString('$entry\n', mode: FileMode.append);
        } catch (e) {
          debugPrint('[CrashLog] ошибка записи: $e');
        }
      }
    } finally {
      _writing = false;
    }
  }

  /// Точка входа для FlutterError.onError / PlatformDispatcher.onError.
  static void handle(Object error, StackTrace? stack, String source) {
    log('$source: $error', error: error, stack: stack);
  }

  static String? get currentFilePath => _filePath;

  static Future<void> flushNow() => _flush();
}