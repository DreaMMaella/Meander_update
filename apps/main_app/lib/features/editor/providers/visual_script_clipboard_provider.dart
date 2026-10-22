import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/visual_script_editor/block_models.dart';
import 'dart:convert';

// Структура для хранения информации о скопированных блоках скрипта в буфере обмена
class VisualScriptClipboardItem {
  final List<VisualScriptBlock> blocks;
  final String operation; // 'copy' или 'cut'

  VisualScriptClipboardItem({required this.blocks, required this.operation});
}

// Глобальный провайдер для буфера обмена блоков визуального скрипта
final visualScriptClipboardProvider = StateProvider<VisualScriptClipboardItem?>(
  (ref) => null,
);

// Рекурсивная функция для удаления ID из JSON объекта блока и всех его вложенных блоков
Map<String, dynamic> _removeIdsRecursively(Map<String, dynamic> json) {
  final result = Map<String, dynamic>.from(json);
  // Удаляем ID текущего блока
  result.remove('id');

  // Обрабатываем вложенные списки блоков
  if (result.containsKey('children')) {
    final children = result['children'] as List<dynamic>?;
    if (children != null) {
      result['children'] = children.map((child) {
        if (child is Map<String, dynamic>) {
          return _removeIdsRecursively(child);
        }
        return child;
      }).toList();
    }
  }

  if (result.containsKey('then_blocks')) {
    final thenBlocks = result['then_blocks'] as List<dynamic>?;
    if (thenBlocks != null) {
      result['then_blocks'] = thenBlocks.map((block) {
        if (block is Map<String, dynamic>) {
          return _removeIdsRecursively(block);
        }
        return block;
      }).toList();
    }
  }

  if (result.containsKey('else_blocks')) {
    final elseBlocks = result['else_blocks'] as List<dynamic>?;
    if (elseBlocks != null) {
      result['else_blocks'] = elseBlocks.map((block) {
        if (block is Map<String, dynamic>) {
          return _removeIdsRecursively(block);
        }
        return block;
      }).toList();
    }
  }

  return result;
}

// Функция для глубокого клонирования списка блоков
List<VisualScriptBlock> cloneBlocks(List<VisualScriptBlock> originalBlocks) {
  // Create a deep copy by serializing to JSON and back
  // This ensures all nested structures are properly copied
  final jsonStr = jsonEncode(
    originalBlocks.map((block) => block.toJson()).toList(),
  );
  final parsedJson = jsonDecode(jsonStr) as List<dynamic>;

  // Remove IDs from all blocks and nested blocks to ensure new ones are generated
  final processedJson = parsedJson.cast<Map<String, dynamic>>().map((
    blockJson,
  ) {
    return _removeIdsRecursively(blockJson);
  }).toList();

  return processedJson.map((json) => VisualScriptBlock.fromJson(json)).toList();
}

// Методы расширения для клонирования блоков
extension BlockCloneExtension on VisualScriptBlock {
  VisualScriptBlock clone() {
    final jsonStr = jsonEncode(this.toJson());
    final parsedJson = jsonDecode(jsonStr) as Map<String, dynamic>;
    // Удаляем оригинальный ID, чтобы при создании нового блока генерировался новый ID
    final processedJson = _removeIdsRecursively(parsedJson);
    return VisualScriptBlock.fromJson(processedJson);
  }
}
