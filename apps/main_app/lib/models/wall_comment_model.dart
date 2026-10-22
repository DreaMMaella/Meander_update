import '../features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

class WallComment {
  final String id;
  final String postId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;

  /// id стиля ника автора комментария (оформление профиля).
  final String? userNameStyle;

  /// Экипировка автора комментария целиком: рамка аватара тоже видна.
  final EquippedCosmetics userCosmetics;
  final String content;
  final int likesCount;
  final bool isLikedByViewer;
  final DateTime createdAt;
  final String? parentId;

  const WallComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    this.userNameStyle,
    this.userCosmetics = EquippedCosmetics.none,
    required this.content,
    required this.likesCount,
    required this.isLikedByViewer,
    required this.createdAt,
    this.parentId,
  });

  factory WallComment.fromJson(Map<String, dynamic> json) {
    return WallComment(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String? ?? tr('Пользователь'),
      userAvatarUrl: json['user_avatar_url'] as String?,
      userNameStyle: json['user_name_style'] as String?,
      userCosmetics: equippedOf(json),
      content: json['content'] as String,
      likesCount: int.tryParse(json['likes_count'].toString()) ?? 0,
      isLikedByViewer: json['is_liked_by_viewer'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
      parentId: json['parent_id'] as String?,
    );
  }

  WallComment copyWith({
    String? id,
    String? postId,
    String? userId,
    String? userName,
    String? userAvatarUrl,
    String? userNameStyle,
    EquippedCosmetics? userCosmetics,
    String? content,
    int? likesCount,
    bool? isLikedByViewer,
    DateTime? createdAt,
    String? parentId,
  }) {
    return WallComment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      userNameStyle: userNameStyle ?? this.userNameStyle,
      userCosmetics: userCosmetics ?? this.userCosmetics,
      content: content ?? this.content,
      likesCount: likesCount ?? this.likesCount,
      isLikedByViewer: isLikedByViewer ?? this.isLikedByViewer,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId ?? this.parentId,
    );
  }
}
