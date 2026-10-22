import 'package:canvas_app/core/l10n/l10n.dart';

class MarketActivityItem {
  final String id;
  final String eventType;
  final DateTime createdAt;
  final String actorId;
  final String actorName;
  final String? actorAvatarUrl;
  final bool actorIsVerified;

  /// id стиля ника из каталога оформления: в ленте ник красится им.
  final String? actorNameStyle;
  final String? actorFrame;
  final String questId;
  final String questTitle;
  final String? targetUserId;
  final String? targetUserName;

  const MarketActivityItem({
    required this.id,
    required this.eventType,
    required this.createdAt,
    required this.actorId,
    required this.actorName,
    required this.actorAvatarUrl,
    required this.actorIsVerified,
    this.actorNameStyle,
    this.actorFrame,
    required this.questId,
    required this.questTitle,
    required this.targetUserId,
    required this.targetUserName,
  });

  factory MarketActivityItem.fromJson(Map<String, dynamic> json) {
    return MarketActivityItem(
      id: (json['id'] as String?) ?? '',
      eventType: (json['event_type'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      actorId: (json['actor_id'] as String?) ?? '',
      actorName: (json['actor_name'] as String?) ?? tr('Игрок'),
      actorAvatarUrl: json['actor_avatar_url'] as String?,
      actorIsVerified: json['actor_is_verified'] == true,
      actorNameStyle: json['actor_name_style'] as String?,
      actorFrame: json['actor_avatar_frame'] as String?,
      questId: (json['quest_id'] as String?) ?? '',
      questTitle: (json['quest_title'] as String?) ?? tr('Без названия'),
      targetUserId: json['target_user_id'] as String?,
      targetUserName: json['target_user_name'] as String?,
    );
  }
}
