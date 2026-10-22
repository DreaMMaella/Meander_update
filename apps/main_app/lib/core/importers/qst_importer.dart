/// Главный класс для импорта квестов из формата URQ (.qst)
/// 
/// Пример использования:
/// ```dart
/// final importer = QstImporter();
/// final result = await importer.importFile('path/to/quest.qst');
/// if (result.success) {
///   // Сохраняем квест
///   await FileStorage.saveQuest(result.data!);
/// }
/// ```

import 'dart:io';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:path/path.dart' as path;
import 'package:mnd_core/models/quest_descriptor.dart';
import 'package:mnd_core/models/saved_node.dart';
import 'qst_parser.dart';
import 'qst_converter.dart';
import 'package:canvas_app/core/utils/error_text.dart';

export 'qst_models.dart';
export 'qst_parser.dart';
export 'qst_converter.dart';

class QstImporter {
  /// Импортировать файл .qst
  Future<QstImportResult> importFile(String filePath) async {
    // Проверяем существование
    final file = File(filePath);
    if (!await file.exists()) {
      return QstImportResult.error(
        trf('Файл не найден: {p0}', {'p0': filePath}),
      );
    }

    // Проверяем расширение
    final ext = path.extension(filePath).toLowerCase();
    if (ext != '.qst' && ext != '.txt' && ext != '.urq') {
      return QstImportResult.error(
        trf(
          'Неподдерживаемый формат: {p0}. Ожидаются .qst, .txt или .urq',
          {'p0': ext},
        ),
      );
    }

    try {
      // Парсим файл
      final parseResult = await QstParser.parseFile(filePath);
      if (!parseResult.success) {
        return QstImportResult.error(parseResult.error ?? tr('Неизвестная ошибка парсинга'));
      }

      // Конвертируем в формат Meander
      final meanderData = QstToMeanderConverter().convert(parseResult.quest!);

      return QstImportResult.success(
        quest: meanderData.quest,
        nodes: meanderData.nodes,
        warnings: parseResult.warnings,
        variables: meanderData.variables,
        inventoryItems: meanderData.inventoryItems,
        scripts: meanderData.scripts,
      );
    } catch (e) {
      return QstImportResult.error(
        trf('Ошибка импорта: {p0}', {'p0': friendlyError(e)}),
      );
    }
  }

  /// Импортировать из строки
  Future<QstImportResult> importString(String content, {String sourceName = 'quest'}) async {
    try {
      // Парсим строку
      final parseResult = QstParser.parse(content, sourceName);
      if (!parseResult.success) {
        return QstImportResult.error(parseResult.error ?? tr('Неизвестная ошибка парсинга'));
      }

      // Конвертируем в формат Meander
      final meanderData = QstToMeanderConverter().convert(parseResult.quest!);

      return QstImportResult.success(
        quest: meanderData.quest,
        nodes: meanderData.nodes,
        warnings: parseResult.warnings,
        variables: meanderData.variables,
        inventoryItems: meanderData.inventoryItems,
        scripts: meanderData.scripts,
      );
    } catch (e) {
      return QstImportResult.error(
        trf('Ошибка импорта: {p0}', {'p0': friendlyError(e)}),
      );
    }
  }
}

/// Результат импорта
class QstImportResult {
  final bool success;
  final Quest? quest;
  final List<SavedNode>? nodes;
  final String? error;
  final List<String> warnings;
  final List<String> variables;
  final List<String> inventoryItems;

  /// Сгенерированные скрипты (путь → JSON) — пишутся при сохранении квеста.
  final Map<String, dynamic> scripts;

  const QstImportResult({
    required this.success,
    this.quest,
    this.nodes,
    this.error,
    this.warnings = const [],
    this.variables = const [],
    this.inventoryItems = const [],
    this.scripts = const {},
  });

  factory QstImportResult.success({
    required Quest quest,
    required List<SavedNode> nodes,
    List<String>? warnings,
    List<String>? variables,
    List<String>? inventoryItems,
    Map<String, dynamic>? scripts,
  }) =>
    QstImportResult(
      success: true,
      quest: quest,
      nodes: nodes,
      warnings: warnings ?? const [],
      variables: variables ?? const [],
      inventoryItems: inventoryItems ?? const [],
      scripts: scripts ?? const {},
    );

  factory QstImportResult.error(String error) =>
    QstImportResult(success: false, error: error);

  /// Получить сводку импорта
  String get summary {
    if (!success) {
      return trf('Ошибка: {p0}', {'p0': friendlyError(error ?? tr('Неизвестная ошибка'))});
    }
    
    final lines = <String>[
      'Успешно импортировано: ${quest?.title}',
      'Нод: ${nodes?.length ?? 0}',
      'Переменных: ${variables.length}',
      'Предметов: ${inventoryItems.length}',
    ];
    
    if (warnings.isNotEmpty) {
      lines.add('Предупреждений: ${warnings.length}');
    }
    
    return lines.join('\n');
  }
}
