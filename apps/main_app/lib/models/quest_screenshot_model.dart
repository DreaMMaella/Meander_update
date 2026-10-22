// lib/models/quest_screenshot_model.dart
import 'package:flutter/foundation.dart';

@immutable
class QuestScreenshot {
  final String id;
  final String questId;
  final String imageUrl;
  final int sortOrder;

  const QuestScreenshot({
    required this.id,
    required this.questId,
    required this.imageUrl,
    required this.sortOrder,
  });

  factory QuestScreenshot.fromJson(Map<String, dynamic> json) {
    return QuestScreenshot(
      id: json['id'] as String,
      questId: json['quest_id'] as String,
      imageUrl: json['image_url'] as String,
      sortOrder: (json['sort_order'] as num? ?? 0).toInt(),
    );
  }
}
