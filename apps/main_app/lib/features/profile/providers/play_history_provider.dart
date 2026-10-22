import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/services/api_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
//  ИГРОВАЯ ИСТОРИЯ — «во что и сколько играл», как в Steam
// ============================================================================

/// Одна строка: суммарное время в конкретном квесте.
class PlayHistoryEntry {
  const PlayHistoryEntry({
    required this.questId,
    required this.title,
    required this.seconds,
    required this.days,
    required this.status,
    this.previewImageUrl,
    this.authorId,
    this.authorName,
    this.authorNameStyle,
    this.lastPlayedAt,
  });

  final String questId;
  final String title;

  /// Всего секунд наиграно в этом квесте.
  final int seconds;

  /// Сколько разных дней к квесту возвращались.
  final int days;

  /// Статус публикации квеста: сняли из маркета — показываем это честно.
  final String status;
  final String? previewImageUrl;
  final String? authorId;
  final String? authorName;
  final String? authorNameStyle;
  final DateTime? lastPlayedAt;

  bool get isPublished => status == 'published';

  factory PlayHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PlayHistoryEntry(
      questId: json['quest_id'] as String,
      title: json['title'] as String? ?? tr('Без названия'),
      seconds: _asInt(json['seconds']),
      days: _asInt(json['days']),
      status: json['status'] as String? ?? 'published',
      previewImageUrl: json['preview_image_url'] as String?,
      authorId: json['author_id'] as String?,
      authorName: json['author_name'] as String?,
      authorNameStyle: json['author_name_style'] as String?,
      lastPlayedAt: DateTime.tryParse(json['last_played_at'] as String? ?? ''),
    );
  }
}

class PlayHistory {
  const PlayHistory({
    required this.items,
    required this.totalSeconds,
    required this.questsPlayed,
    required this.activeDays,
    this.activity = const [],
    this.windowDays = 0,
  });

  final List<PlayHistoryEntry> items;

  /// Сумма по всем квестам — из бэка, а не с одного устройства.
  final int totalSeconds;
  final int questsPlayed;

  /// Дней, в которые хоть раз открывали квест.
  final int activeDays;

  /// Дни с активностью за последние `windowDays` — по ним рисуется полоска
  /// «как в GitHub». Пустых дней в списке нет, их дописывает виджет.
  final List<PlayActivityDay> activity;
  final int windowDays;

  static const empty = PlayHistory(
    items: [],
    totalSeconds: 0,
    questsPlayed: 0,
    activeDays: 0,
  );

  factory PlayHistory.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawActivity = json['activity'];
    final summary = json['summary'];
    final s = summary is Map ? summary : const <String, dynamic>{};
    return PlayHistory(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(PlayHistoryEntry.fromJson)
                .toList()
          : const [],
      totalSeconds: _asInt(s['total_seconds']),
      questsPlayed: _asInt(s['quests_played']),
      activeDays: _asInt(s['active_days']),
      activity: rawActivity is List
          ? rawActivity.whereType<Map<String, dynamic>>().map(
              PlayActivityDay.fromJson).toList()
          : const [],
      windowDays: _asInt(s['window_days']),
    );
  }
}

/// Один день игровой активности.
class PlayActivityDay {
  const PlayActivityDay({required this.day, required this.seconds});

  final DateTime day;
  final int seconds;

  factory PlayActivityDay.fromJson(Map<String, dynamic> json) =>
      PlayActivityDay(
        day: DateTime.tryParse(json['day'] as String? ?? '') ??
            DateTime.now().toUtc(),
        seconds: _asInt(json['seconds']),
      );
}

/// BIGINT из node-postgres приезжает строкой — без этого `as int` падал бы.
int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Ключ — `me` для своей библиотеки или id другого человека: оба маршрута
/// (`/profiles/me/playhistory` и `/profiles/:id/playhistory`) отдают один и
/// тот же JSON, поэтому экрану хватает просто строки из URL.
final playHistoryProvider = FutureProvider.autoDispose
    .family<PlayHistory, String>((ref, subjectId) async {
      final api = ref.watch(apiServiceProvider);
      final response = await api.get('profiles/$subjectId/playhistory');
      if (response is! Map<String, dynamic>) return PlayHistory.empty;
      return PlayHistory.fromJson(response);
    });
