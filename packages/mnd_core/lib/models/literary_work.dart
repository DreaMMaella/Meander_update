/// Литературная работа: комикс, книга, аудиокнига, стихи (план 023).
///
/// Только модель и её JSON — ни файлов, ни виджетов. Разложение по типам
/// намеренно не общее: у книги глава ссылается на файл текста, у комикса
/// страница на картинку, у аудиокниги дорожка на аудио, и «универсальная
/// страница» свела бы все три к худшему общему.
///
/// Паритет путей: `../utils/work_paths.dart`.
library;

enum WorkKind {
  book('book', 'Книга'),
  poem('poem', 'Стихи'),
  comic('comic', 'Комикс'),
  audiobook('audiobook', 'Аудиокнига');

  const WorkKind(this.wireName, this.label);

  /// Как тип лежит в JSON.
  final String wireName;

  /// Подпись для списков и диалога создания.
  final String label;

  static WorkKind parse(Object? raw) => switch (raw?.toString()) {
    'poem' => WorkKind.poem,
    'comic' => WorkKind.comic,
    'audiobook' || 'audio' => WorkKind.audiobook,
    _ => WorkKind.book,
  };
}

/// Что нужно, чтобы открыть работу: тип + обложка + куда смотреть дальше.
class WorkMeta {
  const WorkMeta({
    required this.id,
    required this.kind,
    required this.title,
    this.author,
    this.description,
    this.genres = const [],
    this.coverPath,
    this.authorId,
    this.fontPath,
    this.created,
    this.schemaVersion = 1,
  });

  final String id;
  final WorkKind kind;
  final String title;
  final String? author;
  final String? description;
  final List<String> genres;

  /// Путь обложки относительно корня работы (`res/cover.png`).
  final String? coverPath;
  final String? authorId;

  /// Шрифт, выбранный автором для всей работы (`res/fonts/….ttf`).
  final String? fontPath;
  final DateTime? created;
  final int schemaVersion;

  factory WorkMeta.fromJson(Map<String, dynamic> j) => WorkMeta(
    id: (j['id'] ?? '').toString(),
    kind: WorkKind.parse(j['kind']),
    title: (j['title'] ?? 'Без названия').toString(),
    author: j['author']?.toString(),
    description: j['description']?.toString(),
    genres: stringList(j['genres']),
    coverPath: (j['cover'] ?? j['coverPath'] ?? j['cover_path'])?.toString(),
    authorId: (j['authorId'] ?? j['author_id'])?.toString(),
    fontPath: (j['font'] ?? j['fontPath'])?.toString(),
    created: DateTime.tryParse(j['created']?.toString() ?? ''),
    schemaVersion: int.tryParse(j['schemaVersion']?.toString() ?? '') ?? 1,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.wireName,
    'title': title,
    if (author != null) 'author': author,
    if (description != null) 'description': description,
    if (genres.isNotEmpty) 'genres': genres,
    if (coverPath != null) 'cover': coverPath,
    if (authorId != null) 'authorId': authorId,
    if (fontPath != null) 'font': fontPath,
    if (created != null) 'created': created!.toIso8601String(),
    'schemaVersion': schemaVersion,
  };

  WorkMeta copyWith({String? title, String? author, String? description}) =>
      WorkMeta(
        id: id,
        kind: kind,
        title: title ?? this.title,
        author: author ?? this.author,
        description: description ?? this.description,
        genres: genres,
        coverPath: coverPath,
        authorId: authorId,
        fontPath: fontPath,
        created: created,
        schemaVersion: schemaVersion,
      );
}

/// Глава книги или стихотворение. Тело — отдельный markdown-файл, чтобы
/// повреждение одной главы не превращало в мусор всю рукопись.
class TextChapter {
  const TextChapter({
    required this.id,
    required this.title,
    required this.file,
    this.audio,
  });

  final String id;
  final String title;

  /// Путь к markdown-файлу относительно корня работы (`text/01.md`).
  final String file;

  /// Опциональная озвучка главы: та же книга, но читать её можно слушая.
  final String? audio;

  factory TextChapter.fromJson(Map<String, dynamic> j) => TextChapter(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? 'Без названия').toString(),
    file: (j['file'] ?? '').toString(),
    audio: j['audio']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'file': file,
    if (audio != null) 'audio': audio,
  };

  TextChapter copyWith({String? title, String? file, String? audio}) =>
      TextChapter(
        id: id,
        title: title ?? this.title,
        file: file ?? this.file,
        audio: audio ?? this.audio,
      );
}

class ComicPage {
  const ComicPage({required this.id, required this.image, this.caption});

  final String id;

  /// Путь картинки относительно корня работы (`res/images/p001.png`).
  final String image;
  final String? caption;

  factory ComicPage.fromJson(Map<String, dynamic> j) => ComicPage(
    id: (j['id'] ?? '').toString(),
    image: (j['image'] ?? '').toString(),
    caption: j['caption']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'image': image,
    if (caption != null && caption!.isNotEmpty) 'caption': caption,
  };

  ComicPage copyWith({String? image, String? caption}) => ComicPage(
    id: id,
    image: image ?? this.image,
    caption: caption ?? this.caption,
  );
}

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.title,
    required this.file,
    this.durationSeconds = 0,
  });

  final String id;
  final String title;
  final String file;
  final int durationSeconds;

  factory AudioTrack.fromJson(Map<String, dynamic> j) => AudioTrack(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? 'Дорожка').toString(),
    file: (j['file'] ?? '').toString(),
    durationSeconds: int.tryParse(j['durationSeconds']?.toString() ?? '') ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'file': file,
    if (durationSeconds > 0) 'durationSeconds': durationSeconds,
  };

  AudioTrack copyWith({String? title, String? file, int? durationSeconds}) =>
      AudioTrack(
        id: id,
        title: title ?? this.title,
        file: file ?? this.file,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );
}

/// Оглавление работы. Держится одним файлом (`book.json` / `comic.json` /
/// `audio.json`) и содержит только порядок и ссылки на файлы.
class WorkOutline {
  const WorkOutline({
    this.chapters = const [],
    this.pages = const [],
    this.tracks = const [],
  });

  static const WorkOutline empty = WorkOutline();

  final List<TextChapter> chapters;
  final List<ComicPage> pages;
  final List<AudioTrack> tracks;

  /// Позиции, между которыми листает читалка: глава, страница или дорожка.
  int get pageCount => switch ((chapters, pages, tracks)) {
    (final c, _, _) when c.isNotEmpty => c.length,
    (_, final p, _) when p.isNotEmpty => p.length,
    (_, _, final t) => t.length,
  };

  /// Для книг со стихами файл один и тот же — различается только рендер.
  factory WorkOutline.fromJson(WorkKind kind, Map<String, dynamic> j) {
    final items = mapList(
      j[switch (kind) {
        WorkKind.book || WorkKind.poem => 'chapters',
        WorkKind.comic => 'pages',
        WorkKind.audiobook => 'tracks',
      }],
    );
    return switch (kind) {
      WorkKind.book || WorkKind.poem => WorkOutline(
        chapters: [for (final e in items) TextChapter.fromJson(e)],
      ),
      WorkKind.comic => WorkOutline(
        pages: [for (final e in items) ComicPage.fromJson(e)],
      ),
      WorkKind.audiobook => WorkOutline(
        tracks: [for (final e in items) AudioTrack.fromJson(e)],
      ),
    };
  }

  Map<String, dynamic> toJson(WorkKind kind) => {
    'chapters': [for (final c in chapters) c.toJson()],
    'pages': [for (final p in pages) p.toJson()],
    'tracks': [for (final t in tracks) t.toJson()],
    'kind': kind.wireName,
  };

  WorkOutline withChapters(List<TextChapter> next) =>
      WorkOutline(chapters: next, pages: pages, tracks: tracks);

  WorkOutline withPages(List<ComicPage> next) =>
      WorkOutline(chapters: chapters, pages: next, tracks: tracks);

  WorkOutline withTracks(List<AudioTrack> next) =>
      WorkOutline(chapters: chapters, pages: pages, tracks: next);
}

/// Где человек остановился. Пишется редко и атомарно; на доступ никуда не
/// влияет — недочитанная работа открывается с первой страницы так же легко.
class ReadingProgress {
  const ReadingProgress({
    this.pageIndex = 0,
    this.scrollFraction = 0,
    this.trackIndex = 0,
    this.positionSeconds = 0,
    this.updatedAt,
  });

  static const ReadingProgress start = ReadingProgress();

  /// Номер главы у книги и номер полосы у комикса — смысл один.
  final int pageIndex;

  /// Доля прокрутки текущей главы, 0..1; нужна книге, комиксу — не мешает.
  final double scrollFraction;
  final int trackIndex;
  final int positionSeconds;
  final DateTime? updatedAt;

  factory ReadingProgress.fromJson(Map<String, dynamic> j) => ReadingProgress(
    pageIndex: int.tryParse(j['page']?.toString() ?? '') ?? 0,
    scrollFraction: double.tryParse(j['scroll']?.toString() ?? '') ?? 0,
    trackIndex: int.tryParse(j['track']?.toString() ?? '') ?? 0,
    positionSeconds: int.tryParse(j['position']?.toString() ?? '') ?? 0,
    updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'page': pageIndex,
    if (scrollFraction > 0) 'scroll': scrollFraction,
    'track': trackIndex,
    'position': positionSeconds,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  ReadingProgress copyWith({
    int? pageIndex,
    double? scrollFraction,
    int? trackIndex,
    int? positionSeconds,
    DateTime? updatedAt,
  }) => ReadingProgress(
    pageIndex: pageIndex ?? this.pageIndex,
    scrollFraction: scrollFraction ?? this.scrollFraction,
    trackIndex: trackIndex ?? this.trackIndex,
    positionSeconds: positionSeconds ?? this.positionSeconds,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Перестановка элемента drag-and-drop'ом: индекс `from` уезжает на `to`,
/// остальные сдвигаются. Границы жмутся к допустимым — палец часто мажет.
List<T> reorder<T>(List<T> items, int from, int to) {
  if (items.isEmpty) return items;
  final next = List<T>.of(items);
  final start = from.clamp(0, next.length - 1);
  final moved = next.removeAt(start);
  next.insert(to.clamp(0, next.length), moved);
  return next;
}

/// Список из JSON-массива: всё, что не объект, выбрасываем по дороге, чтобы
/// испорченная строка не роняла открытие работы.
List<Map<String, dynamic>> mapList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

List<String> stringList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw) e.toString(),
  ].where((e) => e.isNotEmpty).toList();
}
