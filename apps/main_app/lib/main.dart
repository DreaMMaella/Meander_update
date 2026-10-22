import 'dart:io' show Platform;
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'package:canvas_app/app/bootstrap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Точка входа.
///
/// ⚠️ WidgetsFlutterBinding.ensureInitialized() вызывается ЗДЕСЬ, в корневой
/// зоне, до любых async-вызовов. runApp тоже в корневой зоне — поэтому
/// zone mismatch не возникает и GL-контекст чистится корректно.
Future<void> main(List<String> args) async {
  // mpv/libmpv требует LC_NUMERIC=C иначе `Non-C locale detected` → abort (Arch en_US.UTF-8)
  if (Platform.isLinux) {
    try {
      final lib = ffi.DynamicLibrary.open('libc.so.6');
      final setlocale = lib.lookupFunction<
          ffi.Pointer<ffi.Char> Function(ffi.Int32, ffi.Pointer<ffi.Char>),
          ffi.Pointer<ffi.Char> Function(int, ffi.Pointer<ffi.Char>)>('setlocale');
      final cStr = 'C'.toNativeUtf8();
      setlocale(1, cStr.cast<ffi.Char>());
      calloc.free(cStr);
    } catch (_) {}
  }
  WidgetsFlutterBinding.ensureInitialized();

  // Инит оконного менеджера (только десктоп: Windows/macOS/Linux).
  // На Android/iOS/Web у плагина нет реализации — без гарда старт
  // падает с MissingPluginException на канале window_manager.
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await WindowManager.instance.ensureInitialized();
  }

  // Вся остальная инициализация в bootstrap.
  await bootstrap();
}
