import 'dart:typed_data';

/// Глава квеста (одна группа нод).
class QuestChapter {
  final String id;
  final String name;
  final List<Map<String, dynamic>> nodes;
  QuestChapter({required this.id, required this.name, required this.nodes});
}

/// «Слепок» квеста, собранный из файлов, для экспорта в HTML/PDF.
class QuestBook {
  final String id;
  final String title;
  final String? author;
  final String? description;
  final String? startNodeId;
  final Map<String, Map<String, dynamic>> nodesById;
  final List<QuestChapter> chapters;
  final Uint8List? previewBytes;
  final String? previewMime;
  final String? customFontFileName;
  final Uint8List? customFontBytes;

  QuestBook({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.startNodeId,
    required this.nodesById,
    required this.chapters,
    required this.previewBytes,
    required this.previewMime,
    required this.customFontFileName,
    required this.customFontBytes,
  });
}
