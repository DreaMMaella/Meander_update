import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:mnd_core/src/gen/frb_generated.dart' as gen;

/// Путь к собранному libmnd_ffi.so: env MND_FFI_SO либо репозиторий.
String? resolveFfiSoPath() {
  final env = Platform.environment['MND_FFI_SO'];
  if (env != null && File(env).existsSync()) return env;
  const candidates = [
    '../../target/release/libmnd_ffi.so',
    '../target/release/libmnd_ffi.so',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return File(c).absolute.path;
  }
  return null;
}

/// Инициализация FRB-моста на внешней библиотеке.
Future<void> soInit(String soPath) async {
  await gen.RustLib.init(
    externalLibrary: ExternalLibrary.open(soPath),
  );
}

/// Декодер для удобства тестов.
dynamic decodeJson(String s) => jsonDecode(s);
