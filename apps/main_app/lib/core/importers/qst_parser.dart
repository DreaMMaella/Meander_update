/// Парсер формата URQ (.qst/.qst.txt)
/// 
/// Формат команд:
/// - :номер - ID ноды
/// - pln текст - описание
/// - btn номер,текст - кнопка с переходом
/// - inv+ предмет / inv- предмет - инвентарь
/// - goto номер - переход
/// - if условие then btn/goto - условие
/// - end - конец ноды

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'qst_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

class QstParser {
  /// Распарсить файл
  static Future<QstParseResult> parseFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return QstParseResult.error(
          trf('Файл не найден: {p0}', {'p0': filePath}),
        );
      }

      // Читаем байты для определения кодировки
      final bytes = await file.readAsBytes();
      
      // Пытаемся определить кодировку по первым байтам
      String content;
      
      // Пробуем UTF-8 сначала (наши конвертированные файлы)
      try {
        content = utf8.decode(bytes, allowMalformed: false);
        // Проверяем валидность - если есть русские буквы, должно быть нормально
        if (content.contains(RegExp(r'[а-яА-ЯёЁ]'))) {
          // UTF-8 валиден
        }
      } catch (_) {
        // Не UTF-8, пробуем CP866 (DOS)
        try {
          content = latin1.decode(bytes); // Сначала в latin1
          // Проверяем на "кракозябры" типичные для CP866->UTF-8
          if (content.contains(RegExp(r'[╧Ёшъы■ўхэш ]'))) {
            // Это CP866, декодируем правильно
            content = await _decodeCP866(bytes);
          }
        } catch (_) {
          // Пробуем Windows-1251
          content = latin1.decode(bytes);
        }
      }
      
      return parse(content, filePath);
    } catch (e) {
      return QstParseResult.error(
        trf('Ошибка чтения файла: {p0}', {'p0': friendlyError(e)}),
      );
    }
  }

  /// Декодировать CP866 (DOS кодировка)
  static Future<String> _decodeCP866(Uint8List bytes) async {
    // Таблица соответствия CP866 -> Unicode для русских букв
    const cp866Table = {
      0x80: 0x0410, 0x81: 0x0411, 0x82: 0x0412, 0x83: 0x0413,
      0x84: 0x0414, 0x85: 0x0415, 0x86: 0x0416, 0x87: 0x0417,
      0x88: 0x0418, 0x89: 0x0419, 0x8A: 0x041A, 0x8B: 0x041B,
      0x8C: 0x041C, 0x8D: 0x041D, 0x8E: 0x041E, 0x8F: 0x041F,
      0x90: 0x0420, 0x91: 0x0421, 0x92: 0x0422, 0x93: 0x0423,
      0x94: 0x0424, 0x95: 0x0425, 0x96: 0x0426, 0x97: 0x0427,
      0x98: 0x0428, 0x99: 0x0429, 0x9A: 0x042A, 0x9B: 0x042B,
      0x9C: 0x042C, 0x9D: 0x042D, 0x9E: 0x042E, 0x9F: 0x042F,
      0xA0: 0x0430, 0xA1: 0x0431, 0xA2: 0x0432, 0xA3: 0x0433,
      0xA4: 0x0434, 0xA5: 0x0435, 0xA6: 0x0436, 0xA7: 0x0437,
      0xA8: 0x0438, 0xA9: 0x0439, 0xAA: 0x043A, 0xAB: 0x043B,
      0xAC: 0x043C, 0xAD: 0x043D, 0xAE: 0x043E, 0xAF: 0x043F,
      0xB0: 0x0440, 0xB1: 0x0441, 0xB2: 0x0442, 0xB3: 0x0443,
      0xB4: 0x0444, 0xB5: 0x0445, 0xB6: 0x0446, 0xB7: 0x0447,
      0xB8: 0x0448, 0xB9: 0x0449, 0xBA: 0x044A, 0xBB: 0x044B,
      0xBC: 0x044C, 0xBD: 0x044D, 0xBE: 0x044E, 0xBF: 0x044F,
    };
    
    final result = StringBuffer();
    for (final byte in bytes) {
      if (byte >= 0x80 && byte <= 0xBF && cp866Table.containsKey(byte)) {
        result.writeCharCode(cp866Table[byte]!);
      } else if (byte >= 0xC0 && byte <= 0xFF) {
        // Ё ё и другие символы
        result.writeCharCode(byte);
      } else {
        result.writeCharCode(byte);
      }
    }
    return result.toString();
  }

  /// Распарсить строку
  static QstParseResult parse(String content, String sourceName) {
    try {
      final lines = content.split('\n');
      final nodes = <QstNode>[];
      final variables = <String>{};
      final inventoryItems = <String>{};
      final warnings = <String>[];

      QstNode? currentNode;
      String? startNodeId;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        // ID ноды: :номер
        if (line.startsWith(':')) {
          // Сохраняем предыдущую ноду
          if (currentNode != null) {
            nodes.add(currentNode);
          }

          final nodeId = line.substring(1).trim();
          currentNode = QstNode(
            id: nodeId,
            commands: [],
          );

          // Первая нода - стартовая
          if (startNodeId == null) {
            startNodeId = nodeId;
          }
          continue;
        }

        // Конец ноды
        if (line.toLowerCase() == 'end') {
          if (currentNode != null) {
            nodes.add(currentNode);
            currentNode = null;
          }
          continue;
        }

        // Пропускаем если нет текущей ноды
        if (currentNode == null) {
          warnings.add('Строка $i: команда вне ноды: $line');
          continue;
        }

        // Парсим команду
        final command = _parseCommand(line, variables, inventoryItems);
        if (command != null) {
          currentNode.commands.add(command);
        }
      }

      // Добавляем последнюю ноду
      if (currentNode != null) {
        nodes.add(currentNode);
      }

      if (nodes.isEmpty) {
        return QstParseResult.error(tr('Не найдено ни одной ноды'));
      }

      final quest = QstQuest(
        title: sourceName.split('/').last.replaceAll('.txt', ''),
        nodes: nodes,
        startNodeId: startNodeId,
        variables: variables,
        inventoryItems: inventoryItems,
      );

      return QstParseResult.success(quest, warnings: warnings);
    } catch (e) {
      return QstParseResult.error(
        trf('Ошибка парсинга: {p0}', {'p0': friendlyError(e)}),
      );
    }
  }

  /// Распарсить одну команду
  static QstCommand? _parseCommand(
    String line,
    Set<String> variables,
    Set<String> inventoryItems,
  ) {
    // pln текст
    if (line.toLowerCase().startsWith('pln ')) {
      return QstCommand(
        type: QstCommandType.pln,
        rawLine: line,
        argument: line.substring(4).trim(),
      );
    }

    // btn номер,текст
    if (line.toLowerCase().startsWith('btn ')) {
      final rest = line.substring(4).trim();
      final commaIndex = rest.indexOf(',');
      if (commaIndex == -1) {
        return QstCommand(
          type: QstCommandType.btn,
          rawLine: line,
          argument: rest,
          extraArgument: 'Кнопка',
        );
      }
      return QstCommand(
        type: QstCommandType.btn,
        rawLine: line,
        argument: rest.substring(0, commaIndex).trim(),
        extraArgument: rest.substring(commaIndex + 1).trim(),
      );
    }

    // inv+ предмет / inv- предмет
    if (line.toLowerCase().startsWith('inv')) {
      final isAdd = line.contains('inv+');
      final item = line.replaceAll('inv+', '').replaceAll('inv-', '').trim();
      inventoryItems.add(item);
      return QstCommand(
        type: QstCommandType.inv,
        rawLine: line,
        argument: item,
        extraArgument: isAdd ? 'add' : 'remove',
      );
    }

    // goto номер
    if (line.toLowerCase().startsWith('goto ')) {
      return QstCommand(
        type: QstCommandType.goto,
        rawLine: line,
        argument: line.substring(5).trim(),
      );
    }

    // if условие then btn/goto
    if (line.toLowerCase().startsWith('if ')) {
      final thenIndex = line.toLowerCase().indexOf(' then ');
      if (thenIndex == -1) {
        return QstCommand(
          type: QstCommandType.unknown,
          rawLine: line,
        );
      }

      final condition = line.substring(3, thenIndex).trim();
      final thenPart = line.substring(thenIndex + 6).trim();

      // Извлекаем переменные из условия
      _extractVariables(condition, variables);

      // Парсим часть после then
      if (thenPart.toLowerCase().startsWith('btn ')) {
        final rest = thenPart.substring(4).trim();
        final commaIndex = rest.indexOf(',');
        return QstCommand(
          type: QstCommandType.ifn,
          rawLine: line,
          argument: commaIndex == -1 ? rest : rest.substring(0, commaIndex).trim(),
          extraArgument: commaIndex == -1 ? 'Кнопка' : rest.substring(commaIndex + 1).trim(),
          condition: condition,
        );
      } else if (thenPart.toLowerCase().startsWith('goto ')) {
        return QstCommand(
          type: QstCommandType.ifn,
          rawLine: line,
          argument: thenPart.substring(5).trim(),
          condition: condition,
        );
      }

      return QstCommand(
        type: QstCommandType.ifn,
        rawLine: line,
        condition: condition,
      );
    }

    // Присваивание: переменная=значение
    if (line.contains('=') && !line.contains(' ')) {
      final parts = line.split('=');
      if (parts.length == 2) {
        variables.add(parts[0].trim());
        return QstCommand(
          type: QstCommandType.unknown,
          rawLine: line,
          argument: parts[0].trim(),
          extraArgument: parts[1].trim(),
        );
      }
    }

    // Неизвестная команда
    return QstCommand(
      type: QstCommandType.unknown,
      rawLine: line,
    );
  }

  /// Извлечь переменные из условия
  static void _extractVariables(String condition, Set<String> variables) {
    // if переменная=значение then
    // if переменная then
    // if not переменная then
    
    final parts = condition.split(RegExp(r'\s+'));
    for (final part in parts) {
      if (part.contains('=')) {
        final varName = part.split('=').first.trim();
        if (varName.isNotEmpty) {
          variables.add(varName);
        }
      } else if (part.toLowerCase() != 'not' && part.isNotEmpty) {
        variables.add(part);
      }
    }
  }
}
