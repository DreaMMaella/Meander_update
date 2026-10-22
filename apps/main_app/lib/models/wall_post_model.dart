import '../features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

class WallPost {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;

  /// id стиля ника из каталога оформления: лента красит автора так же,
  /// как это выглядит у него в профиле.
  final String? authorNameStyle;

  /// Экипировка автора целиком: в ленте видна и рамка аватара, и цветной ник.
  final EquippedCosmetics authorCosmetics;
  final bool isAuthorVerified;

  /// Заголовок есть только у топика форума: пост стены по-прежнему начинается
  /// сразу с текста.
  final String? title;
  final String content;
  final int likesCount;
  final int commentsCount;
  final int viewsCount;
  final bool isLikedByViewer;
  final DateTime createdAt;
  final List<String> mediaUrls;
  final List<String> tags;

  const WallPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorAvatarUrl,
    this.authorNameStyle,
    this.authorCosmetics = EquippedCosmetics.none,
    this.isAuthorVerified = false,
    this.title,
    required this.content,
    required this.likesCount,
    required this.commentsCount,
    required this.viewsCount,
    required this.isLikedByViewer,
    required this.createdAt,
    this.mediaUrls = const [],
    this.tags = const [],
  });

  factory WallPost.fromJson(Map<String, dynamic> json) {
    return WallPost(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      authorName: json['author_name'] as String? ?? tr('Автор'),
      authorAvatarUrl: json['author_avatar_url'] as String?,
      authorNameStyle: json['author_name_style'] as String?,
      authorCosmetics: equippedOf(json),
      isAuthorVerified: json['author_is_verified'] == true,
      title: _titleOf(json['title']),
      content: json['content'] as String,
      likesCount: int.tryParse(json['likes_count'].toString()) ?? 0,
      commentsCount: int.tryParse(json['comments_count'].toString()) ?? 0,
      viewsCount: int.tryParse(json['views_count'].toString()) ?? 0,
      isLikedByViewer: json['is_liked_by_viewer'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
      mediaUrls:
          (json['media_urls'] as List?)?.map((e) => e as String).toList() ?? [],
      tags: (json['tags'] as List?)?.map((e) => e as String).toList() ?? [],
    );
  }

  WallPost copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? authorAvatarUrl,
    String? authorNameStyle,
    EquippedCosmetics? authorCosmetics,
    bool? isAuthorVerified,
    String? title,
    String? content,
    int? likesCount,
    int? commentsCount,
    int? viewsCount,
    bool? isLikedByViewer,
    DateTime? createdAt,
    List<String>? mediaUrls,
    List<String>? tags,
  }) {
    return WallPost(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      authorNameStyle: authorNameStyle ?? this.authorNameStyle,
      authorCosmetics: authorCosmetics ?? this.authorCosmetics,
      isAuthorVerified: isAuthorVerified ?? this.isAuthorVerified,
      title: title ?? this.title,
      content: content ?? this.content,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      viewsCount: viewsCount ?? this.viewsCount,
      isLikedByViewer: isLikedByViewer ?? this.isLikedByViewer,
      createdAt: createdAt ?? this.createdAt,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      tags: tags ?? this.tags,
    );
  }
}

/// Заголовок носится только с топиком форума, и пустая строка для стены — то же
/// самое, что и отсутствие колонки: иначе в шапке треда висит пустая строка.
String? _titleOf(Object? raw) {
  final value = raw?.toString().trim();
  return (value == null || value.isEmpty) ? null : value;
}
