import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/models/wall_post_model.dart';

/// Человек, показанный рядом с форумом: создатель в каталоге, модер в лобби,
/// автор в топике. Везде одна и та же четвёрка «ник / аватар / оформление /
/// роль», потому что оформление профиля должно читаться в сообществе так же,
/// как в профиле.
class ForumPerson {
  const ForumPerson({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.equipped = EquippedCosmetics.none,
    this.role = 'user',
    this.isVerified = false,
    this.moderator = false,
    this.joinedAt,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final EquippedCosmetics equipped;
  final String role;
  final bool isVerified;

  /// Роль именно в этом форуме, а не в приложении.
  final bool moderator;
  final DateTime? joinedAt;

  bool get isStaff => role == 'admin' || isVerified;

  static ForumPerson fromCreator(Map<dynamic, dynamic> json) =>
      ForumPerson._read(json, 'creator_');

  static ForumPerson fromProfile(Map<dynamic, dynamic> json) =>
      ForumPerson._read(json, '');

  static ForumPerson fromAuthor(Map<dynamic, dynamic> json) =>
      ForumPerson._read(json, 'author_');

  /// Префикс — потому что каталог отдаёт создателя колонками `creator_*`, а
  /// модераторов лобби — обычными полями профиля. Разбор один, иначе два
  /// почти одинаковых читателя разошлись бы при первой новой колонке.
  static ForumPerson _read(Map<dynamic, dynamic> json, String prefix) {
    Object? pick(String field) => json['$prefix$field'] ?? json[field];
    return ForumPerson(
      id: (pick('id') ?? '').toString(),
      name: (pick('name') ?? pick('full_name') ?? tr('Пользователь')).toString(),
      avatarUrl: pick('avatar_url')?.toString(),
      equipped: EquippedCosmetics.fromJson(pick('cosmetics')),
      role: (pick('role') ?? 'user').toString(),
      isVerified: pick('is_verified') == true,
      moderator: json['forum_role'] == 'mod',
      joinedAt: DateTime.tryParse('${json['joined_at'] ?? ''}'),
    );
  }
}

/// Строка каталога и шапка лобби — одни и те же колонки `forums`, только
/// лобби знает про бан и вступление зрителя.
class Forum {
  const Forum({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.kind = 'user',
    this.questId,
    this.questTitle,
    this.creatorId = '',
    this.isRestricted = false,
    this.memberCount = 0,
    this.topicsCount = 0,
    this.lastActivityAt,
    this.createdAt,
    this.creator,
    this.joined = false,
    this.banned = false,
  });

  final String id;
  final String slug;
  final String name;
  final String? description;

  /// `user` — сообщество собрал человек, `quest` — обсуждение квеста.
  final String kind;
  final String? questId;
  final String? questTitle;
  final String creatorId;

  /// Пишут только участники; читают по-прежнему все.
  final bool isRestricted;
  final int memberCount;
  final int topicsCount;
  final DateTime? lastActivityAt;
  final DateTime? createdAt;
  final ForumPerson? creator;
  final bool joined;
  final bool banned;

  bool get isQuestForum => kind == 'quest';

  factory Forum.fromCatalog(Map<dynamic, dynamic> json) => Forum(
    id: (json['id'] ?? '').toString(),
    slug: (json['slug'] ?? '').toString(),
    name: (json['name'] ?? tr('Сообщество')).toString(),
    description: json['description']?.toString(),
    kind: (json['kind'] ?? 'user').toString(),
    questId: json['quest_id']?.toString(),
    creatorId: (json['creator_id'] ?? '').toString(),
    isRestricted: json['is_restricted'] == true,
    memberCount: _int(json['member_count']),
    topicsCount: _int(json['topics_count']),
    lastActivityAt: _date(json['last_activity_at']),
    createdAt: _date(json['created_at']),
    creator: json['creator_id'] == null ? null : ForumPerson.fromCreator(json),
  );

  factory Forum.fromLobby(Map<dynamic, dynamic> json) => Forum(
    id: (json['id'] ?? '').toString(),
    slug: (json['slug'] ?? '').toString(),
    name: (json['name'] ?? tr('Сообщество')).toString(),
    description: json['description']?.toString(),
    kind: (json['kind'] ?? 'user').toString(),
    questId: json['quest_id']?.toString(),
    questTitle: json['quest_title']?.toString(),
    creatorId: (json['creator_id'] ?? '').toString(),
    isRestricted: json['is_restricted'] == true,
    memberCount: _int(json['member_count']),
    topicsCount: _int(json['topics_count']),
    createdAt: _date(json['created_at']),
    joined: json['joined'] == true,
    banned: json['banned'] == true,
  );

  Forum copyWith({bool? joined, int? memberCount, bool? isRestricted}) {
    return Forum(
      id: id,
      slug: slug,
      name: name,
      description: description,
      kind: kind,
      questId: questId,
      questTitle: questTitle,
      creatorId: creatorId,
      isRestricted: isRestricted ?? this.isRestricted,
      memberCount: memberCount ?? this.memberCount,
      topicsCount: topicsCount,
      lastActivityAt: lastActivityAt,
      createdAt: createdAt,
      creator: creator,
      joined: joined ?? this.joined,
      banned: banned,
    );
  }
}

/// Ограничение в сообществе: модератор обязан видеть, кого именно он забанил,
/// иначе «забанить» из клиента стало бы действием без отмены.
class ForumBan {
  const ForumBan({
    required this.person,
    required this.reason,
    required this.bannedAt,
  });

  final ForumPerson person;
  final String reason;
  final DateTime? bannedAt;

  factory ForumBan.fromJson(Map<dynamic, dynamic> json) => ForumBan(
    person: ForumPerson.fromProfile(json),
    reason: (json['reason'] ?? '').toString(),
    bannedAt: _date(json['banned_at']),
  );
}

/// Топик — это обычный пост сообщества, легший на полку форума. Поэтому здесь
/// нет второй модели комментария или лайка: `toWallPost` отдаёт тот же
/// `WallPost`, с которым работает экран комментариев.
class ForumTopic {
  const ForumTopic({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.likesCount,
    required this.commentsCount,
    required this.isLikedByViewer,
    this.createdAt,
    this.mediaUrls = const [],
    this.tags = const [],
  });

  final String id;
  final String title;
  final String body;
  final ForumPerson author;
  final int likesCount;
  final int commentsCount;
  final bool isLikedByViewer;
  final DateTime? createdAt;
  final List<String> mediaUrls;
  final List<String> tags;

  factory ForumTopic.fromJson(Map<dynamic, dynamic> json) {
    return ForumTopic(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['content'] ?? '').toString(),
      author: ForumPerson.fromAuthor(json),
      likesCount: _int(json['likes_count']),
      commentsCount: _int(json['comments_count']),
      isLikedByViewer: json['is_liked_by_viewer'] == true,
      createdAt: _date(json['created_at']),
      mediaUrls: _strings(json['media_urls']),
      tags: _strings(json['tags']),
    );
  }

  /// Лайк топика приходит ответом на тот же запрос, что и у поста сообщества, —
  /// строке в ленте не нужна перечитка всего списка ради одной галочки.
  ForumTopic copyWith({int? likesCount, bool? isLikedByViewer}) {
    return ForumTopic(
      id: id,
      title: title,
      body: body,
      author: author,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount,
      isLikedByViewer: isLikedByViewer ?? this.isLikedByViewer,
      createdAt: createdAt,
      mediaUrls: mediaUrls,
      tags: tags,
    );
  }

  WallPost toWallPost() => WallPost(
    id: id,
    authorId: author.id,
    authorName: author.name,
    authorAvatarUrl: author.avatarUrl,
    authorCosmetics: author.equipped,
    isAuthorVerified: author.isVerified,
    content: body,
    title: title,
    likesCount: likesCount,
    commentsCount: commentsCount,
    viewsCount: 0,
    isLikedByViewer: isLikedByViewer,
    createdAt: createdAt ?? DateTime.now(),
    mediaUrls: mediaUrls,
    tags: tags,
  );
}

/// Топик вместе с полкой, на которой он лежит. Общая лента сообщества
/// показывает обсуждения со всех сообществ разом, и без названия форума
/// карточке некуда вести тапом по «где это обсуждают».
class ForumHotTopic {
  const ForumHotTopic({
    required this.topic,
    required this.forumSlug,
    required this.forumName,
  });

  final ForumTopic topic;
  final String forumSlug;
  final String forumName;

  factory ForumHotTopic.fromJson(Map<dynamic, dynamic> json) {
    return ForumHotTopic(
      topic: ForumTopic.fromJson(json),
      forumSlug: (json['forum_slug'] ?? '').toString(),
      forumName: (json['forum_name'] ?? '').toString(),
    );
  }

  ForumHotTopic withTopic(ForumTopic next) => ForumHotTopic(
    topic: next,
    forumSlug: forumSlug,
    forumName: forumName,
  );
}

int _int(Object? value) => int.tryParse(value.toString()) ?? 0;

DateTime? _date(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value.map((e) => e.toString()).toList();
}
