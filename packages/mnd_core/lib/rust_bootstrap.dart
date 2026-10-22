// Условный экспорт: на нативных платформах это `dart:ffi`-вариант, в веб-сборке
// — wasm-вариант. Прямой импорт `..._io.dart` выключал бы `dart:ffi` из
// компиляции браузера (dart2js падает на `dart:ffi is not available`).
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:mnd_core/src/gen/frb_generated.dart' show RustLib;

/// Инициализировать нативное Rust-ядро (FFI). Тонкая обёртка над
/// сгенерированным `RustLib.init` — приложение не должно импортировать
/// внутренний `mnd_core/src/gen` напрямую.
///
/// [externalLibrary] требуется на iOS (искать библиотеку в процессе),
/// на остальных платформах можно передать `null` — FRB сам найдёт `.so`.
Future<void> initRustCore({ExternalLibrary? externalLibrary}) {
  return RustLib.init(externalLibrary: externalLibrary);
}
