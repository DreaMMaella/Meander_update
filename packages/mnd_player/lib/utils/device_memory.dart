import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Физическая память устройства, байты; 0 — определить не удалось.
///
/// dart:io память не отдаёт (`Platform.totalPhysicalMemory` в SDK нет), а
/// `device_info_plus` ради одного числа тащить нельзя — ещё один pod/gradle
/// плагин в цепочке сборки.
///
/// - iOS / macOS: `sysctlbyname("hw.memsize")` — обычный POSIX-вызов из
///   libSystem.
/// - Android: `MemTotal` из `/proc/meminfo` (тем же читает его и сам
///   `ActivityManager`). На glibc/Bionic `sysctlbyname` не экспортируется.
/// - Linux / Windows: 0 — «не определилась», и вызывающий трактует это как
///   «не резать» (см. `PlatformPerformance.backgroundBlurDisabledForMemory`).
int physicalMemoryBytes() {
  if (Platform.isAndroid) return _procMemTotalBytes();
  if (!Platform.isIOS && !Platform.isMacOS) return 0;
  final name = 'hw.memsize'.toNativeUtf8();
  // `size` как oldlenp: первый вызов с пустым буфером сообщает размер значения,
  // второй — пишет само значение в `value`.
  final size = calloc<ffi.Uint64>();
  final value = calloc<ffi.Uint64>();
  try {
    final sysctlbyname = ffi.DynamicLibrary.process()
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint64>,
            ffi.Pointer<ffi.Void>,
            ffi.Uint64,
          ),
          int Function(
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint64>,
            ffi.Pointer<ffi.Void>,
            int,
          )
        >('sysctlbyname');

    final namePtr = name.cast<ffi.Char>();
    if (sysctlbyname(namePtr, ffi.nullptr, size, ffi.nullptr, 0) != 0) return 0;
    if (size.value != 8) return 0;
    if (sysctlbyname(namePtr, value.cast<ffi.Void>(), size, ffi.nullptr, 0) !=
        0) {
      return 0;
    }
    return value.value;
  } catch (_) {
    return 0;
  } finally {
    calloc.free(name);
    calloc.free(size);
    calloc.free(value);
  }
}

int _procMemTotalBytes() {
  try {
    return parseProcMemTotalBytes(File('/proc/meminfo').readAsStringSync());
  } catch (_) {
    return 0;
  }
}

/// `MemTotal` из `/proc/meminfo`, в байтах; 0 — ключа нет или он не число.
///
/// Ядро пишет строку как `MemTotal:        3812340 kB` — килобайты с
/// суффиксом, и без `* 1024` ответ был бы в тысячу раз меньше реального.
int parseProcMemTotalBytes(String procMeminfoContents) {
  final match = RegExp(
    r'^MemTotal:\s+(\d+)',
    multiLine: true,
  ).firstMatch(procMeminfoContents);
  final kilobytes = int.tryParse(match?.group(1) ?? '');
  if (kilobytes == null || kilobytes <= 0) return 0;
  return kilobytes * 1024;
}
