import '../../profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

class CommunityUser {
  final String id;
  final String fullName;
  final String? avatarUrl;
  final DateTime? lastSeenAt;
  final int? metricCount;
  final int? streakCount;
  final bool isVerified;
  final String? role;

  /// Экипировка профиля человека: в списках сообщества видны и рамка аватара,
  /// и цветной ник, а не только «голая» картинка.
  final EquippedCosmetics equipped;

  const CommunityUser({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    this.lastSeenAt,
    this.metricCount,
    this.streakCount,
    this.isVerified = false,
    this.role,
    this.equipped = EquippedCosmetics.none,
  });

  /// id стиля ника из каталога оформления профиля.
  String? get nameStyle => equipped.nameStyle;

  factory CommunityUser.fromJson(Map<String, dynamic> json) {
    return CommunityUser(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? tr('Неизвестно'),
      avatarUrl: json['avatar_url'] as String?,
      lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at']) : null,
      metricCount: json['metric_count'] as int?,
      streakCount: json['streak_count'] as int?,
      isVerified: json['is_verified'] == true,
      role: json['role'] as String?,
      equipped: equippedOf(json),
    );
  }
}
