class AppNotification {
  final String id;
  final String type;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? archivedAt;
  final String? actorId;
  final String? actorName;
  final String? actorAvatarUrl;

  /// id предметов из каталога оформления: ник красим, аватар обводим.
  final String? actorNameStyle;
  final String? actorAvatarFrame;
  final String? questId;
  final String? questTitle;
  final String? questPreviewImageUrl;
  final String? postId;
  final Map<String, dynamic>? payload;

  AppNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    this.readAt,
    this.archivedAt,
    this.actorId,
    this.actorName,
    this.actorAvatarUrl,
    this.actorNameStyle,
    this.actorAvatarFrame,
    this.questId,
    this.questTitle,
    this.questPreviewImageUrl,
    this.postId,
    this.payload,
  });

  bool get isRead => readAt != null;
  bool get isArchived => archivedAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'unknown',
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      archivedAt: json['archived_at'] != null
          ? DateTime.tryParse(json['archived_at'] as String)
          : null,
      actorId: json['actor_id'] as String?,
      actorName: json['actor_name'] as String?,
      actorAvatarUrl: json['actor_avatar_url'] as String?,
      actorNameStyle: json['actor_name_style'] as String?,
      actorAvatarFrame: json['actor_avatar_frame'] as String?,
      questId: json['quest_id'] as String?,
      questTitle: json['quest_title'] as String?,
      questPreviewImageUrl: json['quest_preview_image_url'] as String?,
      postId: json['post_id'] as String?,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : null,
    );
  }
}
