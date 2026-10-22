// ============================================================================
//  МОДЕЛЬ СТАТИСТИКИ КВЕСТА
//
//  Зеркалит ответ `GET /quests/:id/analytics`. Важная деталь: node-postgres
//  отдаёт `COUNT` и `BIGINT` строкой, поэтому каждое число проходит через
//  `_asInt`/`_asDouble` — иначе экран падал бы ровно на тех квестах, где
//  статистика уже есть.
// ============================================================================

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Один день выбранного окна. Нули — это «никто не заходил», а не «нет данных».
class QuestAnalyticsDay {
  const QuestAnalyticsDay({
    required this.date,
    required this.views,
    required this.viewers,
    required this.downloads,
    required this.likes,
    required this.dislikes,
    required this.ratings,
    required this.ratingAvg,
    required this.reviews,
    required this.players,
    required this.playtimeSeconds,
  });

  final DateTime date;
  final int views;
  final int viewers;
  final int downloads;
  final int likes;
  final int dislikes;
  final int ratings;

  /// Средняя оценка за день; null — в этот день не оценивали.
  final double? ratingAvg;
  final int reviews;
  final int players;
  final int playtimeSeconds;

  factory QuestAnalyticsDay.fromJson(Map<String, dynamic> json) =>
      QuestAnalyticsDay(
        date:
            DateTime.tryParse(json['day']?.toString() ?? '') ?? DateTime.now(),
        views: _asInt(json['views']),
        viewers: _asInt(json['viewers']),
        downloads: _asInt(json['downloads']),
        likes: _asInt(json['likes']),
        dislikes: _asInt(json['dislikes']),
        ratings: _asInt(json['ratings']),
        ratingAvg: _asDouble(json['rating_avg']),
        reviews: _asInt(json['reviews']),
        players: _asInt(json['players']),
        playtimeSeconds: _asInt(json['playtime_seconds']),
      );
}

/// Итог за окно (текущее или предыдущее той же длины).
class QuestAnalyticsWindow {
  const QuestAnalyticsWindow({
    required this.views,
    required this.viewers,
    required this.downloads,
    required this.downloaders,
    required this.likes,
    required this.dislikes,
    required this.ratings,
    required this.ratingAvg,
    required this.reviews,
    required this.players,
    required this.playtimeSeconds,
  });

  final int views;
  final int viewers;
  final int downloads;
  final int downloaders;
  final int likes;
  final int dislikes;
  final int ratings;
  final double ratingAvg;
  final int reviews;
  final int players;
  final int playtimeSeconds;

  static const empty = QuestAnalyticsWindow(
    views: 0,
    viewers: 0,
    downloads: 0,
    downloaders: 0,
    likes: 0,
    dislikes: 0,
    ratings: 0,
    ratingAvg: 0,
    reviews: 0,
    players: 0,
    playtimeSeconds: 0,
  );

  factory QuestAnalyticsWindow.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return QuestAnalyticsWindow(
      views: _asInt(json['views']),
      viewers: _asInt(json['viewers']),
      downloads: _asInt(json['downloads']),
      downloaders: _asInt(json['downloaders']),
      likes: _asInt(json['likes']),
      dislikes: _asInt(json['dislikes']),
      ratings: _asInt(json['ratings']),
      ratingAvg: _asDouble(json['rating_avg']) ?? 0,
      reviews: _asInt(json['reviews']),
      players: _asInt(json['players']),
      playtimeSeconds: _asInt(json['playtime_seconds']),
    );
  }

  int get votes => likes + dislikes;

  /// Доля положительных среди тех, кто проголосовал. null голосов — не 0%.
  double? get positiveShare => votes == 0 ? null : likes / votes;

  /// «Посмотрели → скачали». Больше 1 быть не может по смыслу, но данные
  /// живут разное время: скачали вчера, а считать просмотры начали сегодня.
  double? get downloadRate =>
      views == 0 ? null : (downloads / views).clamp(0.0, 1.0).toDouble();

  double? get playRate =>
      downloads == 0 ? null : (players / downloads).clamp(0.0, 1.0).toDouble();

  double get avgPlaytimePerPlayer =>
      players == 0 ? 0 : playtimeSeconds / players;
}

class QuestAnalyticsLifetime {
  const QuestAnalyticsLifetime({
    required this.views,
    required this.viewers,
    required this.playSeconds,
    required this.players,
    required this.reviews,
    required this.reviewsApproved,
    required this.reviewsAnswered,
    required this.lastViewedDay,
    required this.lastDownloadedAt,
    required this.lastPlayedAt,
  });

  final int views;
  final int viewers;
  final int playSeconds;
  final int players;
  final int reviews;
  final int reviewsApproved;
  final int reviewsAnswered;
  final DateTime? lastViewedDay;
  final DateTime? lastDownloadedAt;
  final DateTime? lastPlayedAt;

  static const empty = QuestAnalyticsLifetime(
    views: 0,
    viewers: 0,
    playSeconds: 0,
    players: 0,
    reviews: 0,
    reviewsApproved: 0,
    reviewsAnswered: 0,
    lastViewedDay: null,
    lastDownloadedAt: null,
    lastPlayedAt: null,
  );

  factory QuestAnalyticsLifetime.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return QuestAnalyticsLifetime(
      views: _asInt(json['views']),
      viewers: _asInt(json['viewers']),
      playSeconds: _asInt(json['plays_total_seconds']),
      players: _asInt(json['players']),
      reviews: _asInt(json['reviews']),
      reviewsApproved: _asInt(json['reviews_approved']),
      reviewsAnswered: _asInt(json['reviews_answered']),
      lastViewedDay: DateTime.tryParse(
        json['last_viewed_day']?.toString() ?? '',
      ),
      lastDownloadedAt: DateTime.tryParse(
        json['last_downloaded_at']?.toString() ?? '',
      ),
      lastPlayedAt: DateTime.tryParse(json['last_played_at']?.toString() ?? ''),
    );
  }

  /// Сколько отзывов автор разобрал — единственная метрика здесь, которая
  /// целиком про поведение самого автора, а не аудитории.
  double get replyShare =>
      reviewsApproved == 0 ? 0 : reviewsAnswered / reviewsApproved;
}

class QuestAnalytics {
  const QuestAnalytics({
    required this.questId,
    required this.title,
    required this.status,
    required this.publishedAt,
    required this.lifetimeDownloads,
    required this.lifetimeLikes,
    required this.lifetimeDislikes,
    required this.days,
    required this.from,
    required this.to,
    required this.series,
    required this.window,
    required this.previous,
    required this.lifetime,
    required this.histogram,
  });

  final String questId;
  final String title;
  final String status;
  final DateTime? publishedAt;

  /// Числа, которые маркет показывает на карточке всегда: их берём из
  /// `quests`, а не из окна, чтобы «всего» не зависело от фильтра.
  final int lifetimeDownloads;
  final int lifetimeLikes;
  final int lifetimeDislikes;

  final int days;
  final DateTime from;
  final DateTime to;
  final List<QuestAnalyticsDay> series;
  final QuestAnalyticsWindow window;
  final QuestAnalyticsWindow previous;
  final QuestAnalyticsLifetime lifetime;

  /// Оценки от 5 к 1 — как в Play Console, чтобы худшие были видны рядом.
  final List<int> histogram;

  bool get isEmpty =>
      lifetime.views == 0 &&
      lifetimeDownloads == 0 &&
      lifetime.playSeconds == 0 &&
      lifetime.reviews == 0;

  /// Динамика сигнала: сколько добавил текущий минус предыдущее окно.
  int deltaViews() => window.views - previous.views;
  int deltaDownloads() => window.downloads - previous.downloads;
  int deltaLikes() => window.likes - previous.likes;
  int deltaPlayers() => window.players - previous.players;
  int deltaPlaytime() => window.playtimeSeconds - previous.playtimeSeconds;
  int deltaReviews() => window.reviews - previous.reviews;

  List<int> get viewsSeries => series.map((d) => d.views).toList();
  List<int> get viewersSeries => series.map((d) => d.viewers).toList();
  List<int> get downloadsSeries => series.map((d) => d.downloads).toList();
  List<int> get likesSeries => series.map((d) => d.likes).toList();
  List<int> get dislikesSeries => series.map((d) => d.dislikes).toList();
  List<int> get reviewsSeries => series.map((d) => d.reviews).toList();
  List<int> get playersSeries => series.map((d) => d.players).toList();
  List<int> get playtimeSeries => series.map((d) => d.playtimeSeconds).toList();
  List<DateTime> get dates => series.map((d) => d.date).toList();

  factory QuestAnalytics.fromJson(Map<String, dynamic> json) {
    final quest = (json['quest'] as Map?)?.cast<String, dynamic>();
    return QuestAnalytics(
      questId: quest?['id']?.toString() ?? '',
      title: quest?['title']?.toString() ?? '',
      status: quest?['status']?.toString() ?? '',
      publishedAt: DateTime.tryParse(quest?['created_at']?.toString() ?? ''),
      lifetimeDownloads: _asInt(quest?['downloads_count']),
      lifetimeLikes: _asInt(quest?['like_count']),
      lifetimeDislikes: _asInt(quest?['dislike_count']),
      days: _asInt(json['days']),
      from: DateTime.tryParse(json['from']?.toString() ?? '') ?? DateTime.now(),
      to: DateTime.tryParse(json['to']?.toString() ?? '') ?? DateTime.now(),
      series: ((json['series'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(QuestAnalyticsDay.fromJson)
          .toList(),
      window: QuestAnalyticsWindow.fromJson(
        (json['window'] as Map?)?.cast<String, dynamic>(),
      ),
      previous: QuestAnalyticsWindow.fromJson(
        (json['previous'] as Map?)?.cast<String, dynamic>(),
      ),
      lifetime: QuestAnalyticsLifetime.fromJson(
        (json['lifetime'] as Map?)?.cast<String, dynamic>(),
      ),
      // Порядок берём из самой оценки, а не из порядка строк: без оценок
      // какого-то достоинства в ответе просто нет, и ряд сдвинулся бы на них.
      histogram: () {
        final byRating = <int, int>{};
        for (final row
            in ((json['rating_histogram'] as List?) ?? const [])
                .whereType<Map<String, dynamic>>()) {
          byRating[_asInt(row['rating'])] = _asInt(row['count']);
        }
        return [5, 4, 3, 2, 1].map((r) => byRating[r] ?? 0).toList();
      }(),
    );
  }
}

/// Одна строка сводки автора: квест и его числа за выбранное окно.
class AuthorAnalyticsQuest {
  const AuthorAnalyticsQuest({
    required this.id,
    required this.title,
    required this.status,
    required this.views,
    required this.viewers,
    required this.downloads,
    required this.players,
    required this.playtimeSeconds,
    required this.likes,
    required this.ratingAvg,
  });

  final String id;
  final String title;
  final String status;
  final int views;
  final int viewers;
  final int downloads;
  final int players;
  final int playtimeSeconds;
  final int likes;

  /// Средняя оценка квеста за всё время; null — оценок нет вовсе.
  final double? ratingAvg;

  factory AuthorAnalyticsQuest.fromJson(Map<String, dynamic> json) =>
      AuthorAnalyticsQuest(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        views: _asInt(json['views']),
        viewers: _asInt(json['viewers']),
        downloads: _asInt(json['downloads']),
        players: _asInt(json['players']),
        playtimeSeconds: _asInt(json['playtime_seconds']),
        likes: _asInt(json['likes']),
        ratingAvg: _asDouble(json['rating_avg']),
      );
}

/// Сводка по всем квестам автора. Те же поля и то же окно, что и в карточке
/// одного квеста, — сервер считает их одними и теми же запросами, и экран не
/// имеет права показывать «игрока» иначе, чем он показан в самом квесте.
class AuthorAnalytics {
  const AuthorAnalytics({
    required this.days,
    required this.from,
    required this.to,
    required this.questsTotal,
    required this.questsPublished,
    required this.window,
    required this.previous,
    required this.series,
    required this.quests,
  });

  final int days;
  final DateTime from;
  final DateTime to;
  final int questsTotal;
  final int questsPublished;
  final QuestAnalyticsWindow window;
  final QuestAnalyticsWindow previous;
  final List<QuestAnalyticsDay> series;
  final List<AuthorAnalyticsQuest> quests;

  int deltaViews() => window.views - previous.views;
  int deltaDownloads() => window.downloads - previous.downloads;
  int deltaPlayers() => window.players - previous.players;
  int deltaPlaytime() => window.playtimeSeconds - previous.playtimeSeconds;

  List<int> get viewsSeries => series.map((d) => d.views).toList();
  List<int> get downloadsSeries => series.map((d) => d.downloads).toList();
  List<int> get playersSeries => series.map((d) => d.players).toList();
  List<int> get playtimeSeries => series.map((d) => d.playtimeSeconds).toList();
  List<DateTime> get dates => series.map((d) => d.date).toList();

  /// Ни одного касания аудитории за окно и ни одного скачивания.
  bool get isEmpty =>
      window.views == 0 && window.downloads == 0 && window.playtimeSeconds == 0;

  factory AuthorAnalytics.fromJson(Map<String, dynamic> json) {
    return AuthorAnalytics(
      days: _asInt(json['days']),
      from: DateTime.tryParse(json['from']?.toString() ?? '') ?? DateTime.now(),
      to: DateTime.tryParse(json['to']?.toString() ?? '') ?? DateTime.now(),
      questsTotal: _asInt(json['quests_total']),
      questsPublished: _asInt(json['quests_published']),
      window: QuestAnalyticsWindow.fromJson(
        (json['window'] as Map?)?.cast<String, dynamic>(),
      ),
      previous: QuestAnalyticsWindow.fromJson(
        (json['previous'] as Map?)?.cast<String, dynamic>(),
      ),
      series: ((json['series'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(QuestAnalyticsDay.fromJson)
          .toList(),
      quests: ((json['quests'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AuthorAnalyticsQuest.fromJson)
          .toList(),
    );
  }
}
