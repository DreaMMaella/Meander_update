import 'dart:math';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/market/providers/market_provider.dart';
import 'package:canvas_app/models/market_quest_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ключ для хранения недавно открытых квестов (для "Похожие на ваши любимые").
const String _kRecentlyViewedQuestsKey = 'recently_viewed_quests_v1';

final userGenrePrefsProvider = FutureProvider<List<String>>((ref) async {
  try {
    final api = ref.read(apiServiceProvider);
    final response = await api.get('quests/liked-genres');
    if (response is List) {
      return response.map((e) => e.toString()).toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

/// Менеджер недавно просмотренных квестов (id) — основа для рекомендаций
/// "Похожие на ваши любимые".
class RecentlyViewedQuestsNotifier extends StateNotifier<List<String>> {
  RecentlyViewedQuestsNotifier() : super(const []) {
    _load();
  }

  static const int _maxItems = 25;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kRecentlyViewedQuestsKey) ?? const [];
    if (mounted) state = list;
  }

  Future<void> push(String questId) async {
    if (questId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final next = <String>[questId, ...state.where((id) => id != questId)];
    if (next.length > _maxItems) {
      next.removeRange(_maxItems, next.length);
    }
    state = next;
    await prefs.setStringList(_kRecentlyViewedQuestsKey, next);
  }
}

final recentlyViewedQuestsProvider =
    StateNotifierProvider<RecentlyViewedQuestsNotifier, List<String>>(
      (ref) => RecentlyViewedQuestsNotifier(),
    );

/// 1. "Для вас" — смешанная персональная лента.
/// Алгоритм (клиентский, без серверного эндпоинта):
///   • если пользователь выбрал жанры — берём квесты этих жанров с высоким рейтингом;
///   • добавляем популярных авторов (verified);
///   • подмешиваем "скрытые алмазы" для разнообразия;
///   • если предпочтений нет — это микс topPopular + hidden gems.
final personalRecommendsProvider = FutureProvider.autoDispose<List<MarketQuest>>(
  (ref) async {
    final all = await ref.watch(marketQuestsProviderNew.future);
    final visible = all.where((q) => !q.isDemo).toList();
    if (visible.isEmpty) return const [];

    final likedGenresAsync = ref.watch(userGenrePrefsProvider);
    final likedGenres = likedGenresAsync.maybeWhen(data: (d) => d, orElse: () => const <String>[]);
    final recent = ref.watch(recentlyViewedQuestsProvider);

    // Соберём набор предпочитаемых жанров: жанры лайкнутых квестов + жанры
    // недавно просмотренных квестов.
    final preferredGenres = <String>{...likedGenres};
    if (recent.isNotEmpty) {
      final recentSet = recent.toSet();
      for (final q in visible) {
        if (recentSet.contains(q.id)) {
          if (q.category != null && q.category!.isNotEmpty) {
            preferredGenres.add(q.category!);
          }
          preferredGenres.addAll(q.genres);
        }
      }
    }

    double scoreFor(MarketQuest q) {
      double s = 0;
      s += q.averageRating * 2.0;
      s += (q.downloadsCount.clamp(0, 5000)) / 1000.0;
      s += q.likeCount * 0.05;
      if (q.authorIsVerified) s += 1.5;
      if (q.isFeatured == true) s += 2.0;

      if (preferredGenres.isNotEmpty) {
        var genreMatch = false;
        if (q.category != null && preferredGenres.contains(q.category)) {
          genreMatch = true;
        }
        if (q.genres.any(preferredGenres.contains)) {
          genreMatch = true;
        }
        if (genreMatch) s += 5.0;
      }

      return s;
    }

    final scored = visible.map((q) => MapEntry(q, scoreFor(q))).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Берём топ-20 по скору, перемешиваем хвост, чтобы лента не была статичной.
    final topN = scored.take(20).map((e) => e.key).toList();
    final tail = topN.length > 6 ? topN.sublist(6) : <MarketQuest>[];
    final head = topN.length > 6 ? topN.sublist(0, 6) : topN;

    final rng = Random();
    tail.shuffle(rng);
    return [...head, ...tail].take(15).toList();
  },
);

/// 2. "Похожие на ваши любимые" — на основе жанров недавно открытых квестов.
final similarToFavoritesProvider =
    FutureProvider.autoDispose<List<MarketQuest>>((ref) async {
      final recent = ref.watch(recentlyViewedQuestsProvider);
      if (recent.isEmpty) return const [];

      final all = await ref.watch(marketQuestsProviderNew.future);
      if (all.isEmpty) return const [];

      final recentSet = recent.toSet();
      final seedGenres = <String>{};
      for (final q in all) {
        if (recentSet.contains(q.id)) {
          if (q.category != null && q.category!.isNotEmpty) {
            seedGenres.add(q.category!);
          }
          seedGenres.addAll(q.genres);
        }
      }
      if (seedGenres.isEmpty) return const [];

      final similar = all.where((q) {
        if (q.isDemo) return false;
        if (recentSet.contains(q.id)) return false;
        if (q.category != null && seedGenres.contains(q.category)) return true;
        return q.genres.any(seedGenres.contains);
      }).toList();

      similar.sort((a, b) {
        final ra = a.averageRating + a.downloadsCount / 1000.0;
        final rb = b.averageRating + b.downloadsCount / 1000.0;
        return rb.compareTo(ra);
      });

      return similar.take(12).toList();
    });
