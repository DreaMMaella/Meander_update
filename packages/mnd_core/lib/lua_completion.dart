/// Dart-обёртка над контекстным автодополнением Lua (FFI).
///
/// Вызывает [`lua_complete`] в Rust-ядре и парсит список подсказок.
/// Размещено в отдельном файле, т.к. не требует создания движка — чистая
/// функция над буфером и позицией курсора.
library;

import 'dart:convert';

import 'package:mnd_core/src/gen/api/lua.dart' as gen;

/// Одна подсказка автодополнения Lua.
class LuaSuggestion {
  final String label;
  final String kind;
  final String insertText;
  final String? detail;

  const LuaSuggestion({
    required this.label,
    required this.kind,
    required this.insertText,
    this.detail,
  });

  factory LuaSuggestion.fromJson(Map<String, dynamic> json) => LuaSuggestion(
    label: (json['label'] as String?) ?? '',
    kind: (json['kind'] as String?) ?? '',
    insertText: (json['insertText'] as String?) ?? '',
    detail: json['detail'] as String?,
  );
}

/// Контекстное автодополнение Lua для позиции курсора.
///
/// [source] — текущий текст буфера, [cursorByte] — байтовая позиция курсора.
/// Если FFI недоступен (например, на вебе без .so) — возвращает пустой
/// список, редактор продолжает жить без всплывающей подсказки.
Future<List<LuaSuggestion>> fetchLuaCompletions(
  String source,
  int cursorByte,
) async {
  try {
    final json = await gen.luaComplete(
      source: source,
      cursorByte: BigInt.from(cursorByte),
    );
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => LuaSuggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    // FFI-слой может быть не готов (нет .so) — тихо деградируем.
    return const <LuaSuggestion>[];
  }
}