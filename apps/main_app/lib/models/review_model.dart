import 'package:flutter/foundation.dart';

import '../features/profile/cosmetics/cosmetic_model.dart';

@immutable
class Review {
  final String id;
  final String questId;
  final String authorId;
  final String textContent;
  final DateTime createdAt;
  final String? authorName;
  final String? authorAvatarUrl;

  /// id стиля ника автора отзыва из каталога оформления.
  final String? authorNameStyle;

  /// Экипировка автора отзыва целиком: в списках видна и рамка аватара.
  final EquippedCosmetics authorCosmetics;
  final String? questTitle;
  final int? rating;
  final String? authorReply;
  final String? authorReplyAt;

  const Review({
    required this.id,
    required this.questId,
    required this.authorId,
    required this.textContent,
    required this.createdAt,
    this.authorName,
    this.authorAvatarUrl,
    this.authorNameStyle,
    this.authorCosmetics = EquippedCosmetics.none,
    this.questTitle,
    this.rating,
    this.authorReply,
    this.authorReplyAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    // Поддержка вложенных объектов (legacy API)
    final questObj = json['quests'] as Map<String, dynamic>?;
    final profileObj = json['profiles'] as Map<String, dynamic>?;
    final equipped = equippedOf(json);

    return Review(
      id: json['id'] as String? ?? '',
      questId: json['quest_id'] as String,
      authorId: json['author_id'] as String,
      textContent: json['text_content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),

      // Сначала ищем поле из нового SQL запроса, затем из старой структуры
      authorName:
          json['author_name'] as String? ?? profileObj?['full_name'] as String?,
      authorAvatarUrl:
          json['author_avatar_url'] as String? ??
          profileObj?['avatar_url'] as String?,
      authorNameStyle:
          json['author_name_style'] as String? ??
          (profileObj?['cosmetics'] is Map
              ? (profileObj!['cosmetics'] as Map)['name_style'] as String?
              : null),
      authorCosmetics: equipped.isEmpty
          ? EquippedCosmetics.fromJson(profileObj?['cosmetics'])
          : equipped,
      questTitle:
          json['quest_title'] as String? ?? questObj?['title'] as String?,

      rating: json['rating'] as int?,
      authorReply: json['author_reply'] as String?,
      authorReplyAt: json['author_reply_at'] as String?,
    );
  }

  // --- ДОБАВЛЕНО: Метод для клонирования объекта с заменой полей ---
  Review copyWith({
    String? id,
    String? questId,
    String? authorId,
    String? textContent,
    DateTime? createdAt,
    String? authorName,
    String? authorAvatarUrl,
    String? authorNameStyle,
    EquippedCosmetics? authorCosmetics,
    String? questTitle,
    int? rating,
    String? authorReply,
    String? authorReplyAt,
  }) {
    return Review(
      id: id ?? this.id,
      questId: questId ?? this.questId,
      authorId: authorId ?? this.authorId,
      textContent: textContent ?? this.textContent,
      createdAt: createdAt ?? this.createdAt,
      authorName: authorName ?? this.authorName,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      authorNameStyle: authorNameStyle ?? this.authorNameStyle,
      authorCosmetics: authorCosmetics ?? this.authorCosmetics,
      questTitle: questTitle ?? this.questTitle,
      rating: rating ?? this.rating,
      authorReply: authorReply ?? this.authorReply,
      authorReplyAt: authorReplyAt ?? this.authorReplyAt,
    );
  }
}
