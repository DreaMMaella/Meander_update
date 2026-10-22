import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Выставить LC_NUMERIC=C до инициализации mpv (иначе на Arch с en_US.UTF-8
/// падает `Non-C locale detected` → abort). Вызывать до `MediaKit.ensureInitialized()`
/// и создания `Player`.
void ensureCNumericLocale() {
  if (!Platform.isLinux) return;
  try {
    final lib = ffi.DynamicLibrary.open('libc.so.6');
    final setlocale = lib.lookupFunction<
        ffi.Pointer<ffi.Char> Function(ffi.Int32, ffi.Pointer<ffi.Char>),
        ffi.Pointer<ffi.Char> Function(int, ffi.Pointer<ffi.Char>)>('setlocale');
    const lcNumeric = 1; // LC_NUMERIC
    final cStr = 'C'.toNativeUtf8();
    setlocale(lcNumeric, cStr.cast<ffi.Char>());
    calloc.free(cStr);
  } catch (_) {
    // fallback: пробуем через процессную либу
    try {
      final lib2 = ffi.DynamicLibrary.process();
      final setlocale2 = lib2.lookupFunction<
          ffi.Pointer<ffi.Char> Function(ffi.Int32, ffi.Pointer<ffi.Char>),
          ffi.Pointer<ffi.Char> Function(int, ffi.Pointer<ffi.Char>)>('setlocale');
      const lcNumeric = 1;
      final cStr = 'C'.toNativeUtf8();
      setlocale2(lcNumeric, cStr.cast<ffi.Char>());
      calloc.free(cStr);
    } catch (_) {}
  }
}
