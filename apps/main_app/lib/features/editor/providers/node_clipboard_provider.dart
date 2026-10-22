import 'package:flutter_riverpod/flutter_riverpod.dart';

// Структура для хранения информации о ноде в буфере обмена
class NodeClipboardItem {
  final String nodeId;
  final String questId;
  final String operation; // 'copy' или 'cut'

  NodeClipboardItem({
    required this.nodeId,
    required this.questId,
    required this.operation,
  });
}

// Глобальный провайдер для буфера обмена нод
final nodeClipboardProvider = StateProvider<NodeClipboardItem?>((ref) => null);