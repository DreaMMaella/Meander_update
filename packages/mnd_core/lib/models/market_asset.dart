import '../utils/cosmetic_ids.dart';

class MarketAsset {
  final String id;
  final String kind;
  final String title;
  final String? description;
  final String? genre;
  final List<String> genres;
  final String fileUrl;
  final String? coverUrl;
  final String? previewUrl;
  final String license;
  final String? fileHash;
  final int fileSizeBytes;
  final String status;
  final String? authorId;
  final String? authorName;
  final bool authorIsVerified;

  /// id стиля ника автора из каталога оформления профиля (косметика).
  final String? authorNameStyle;

  /// id рамки аватара автора — та же косметика, что в его профиле.
  final String? authorAvatarFrame;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MarketAsset({
    required this.id,
    required this.kind,
    required this.title,
    this.description,
    this.genre,
    this.genres = const [],
    required this.fileUrl,
    this.coverUrl,
    this.previewUrl,
    required this.license,
    this.fileHash,
    this.fileSizeBytes = 0,
    this.status = 'published',
    this.authorId,
    this.authorName,
    this.authorIsVerified = false,
    this.authorNameStyle,
    this.authorAvatarFrame,
    this.createdAt,
    this.updatedAt,
  });

  factory MarketAsset.fromJson(Map<String, dynamic> j) {
    List<String> genres = [];
    if (j['genres'] is List) genres = (j['genres'] as List).map((e) => e.toString()).toList();
    else if (j['genre'] != null) genres = [j['genre'].toString()];
    return MarketAsset(
      id: (j['id'] ?? '').toString(),
      kind: (j['kind'] ?? 'image').toString(),
      title: (j['title'] ?? 'Без названия').toString(),
      description: j['description']?.toString(),
      genre: j['genre']?.toString(),
      genres: genres,
      fileUrl: (j['file_url'] ?? j['fileUrl'] ?? j['download_url'] ?? '').toString(),
      coverUrl: j['cover_url']?.toString() ?? j['coverUrl']?.toString(),
      previewUrl: j['preview_url']?.toString() ?? j['previewUrl']?.toString(),
      license: (j['license'] ?? 'CC-BY').toString(),
      fileHash: j['file_hash']?.toString() ?? j['fileHash']?.toString(),
      fileSizeBytes: j['file_size_bytes'] is int ? j['file_size_bytes'] as int : int.tryParse((j['file_size_bytes'] ?? '0').toString()) ?? 0,
      status: (j['status'] ?? 'published').toString(),
      authorId: j['author_id']?.toString() ?? j['authorId']?.toString(),
      authorName: j['author_name']?.toString() ?? j['authorName']?.toString(),
      authorNameStyle: j['author_name_style']?.toString() ?? j['authorNameStyle']?.toString(),
      authorAvatarFrame: cosmeticSlotId(j['author_cosmetics'], 'avatar_frame'),
      authorIsVerified: j['author_is_verified'] == true || j['authorIsVerified'] == true,
      createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'].toString()) : null,
      updatedAt: j['updated_at'] != null ? DateTime.tryParse(j['updated_at'].toString()) : null,
    );
  }

  String get downloadUrl => fileUrl;
}
