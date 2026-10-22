import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/forums/models/forum_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetics_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пороги клиента — те же числа, что в `FORUM_RULES` на бэке. Нужны только для
/// счётчиков и подсказок: настоящая проверка живёт на сервере, и отказ он
/// возвращает готовой русской строкой, которую экран показывает как есть.
class ForumLimits {
  static const int maxNameChars = 60;
  static const int maxDescriptionChars = 600;
  static const int maxTitleChars = 200;
  static const int maxBodyChars = 8000;
  static const int minAccountAgeDaysToCreate = 7;
  static const int maxCreatedByDay = 2;
}

/// Порядок сортировки ленты топиков. Совпадает с `SORTS` на бэке; третий —
/// «обсуждаемые», потому что для форума количество ответов и есть рейтинг.
class ForumSorts {
  static const List<String> values = ['new', 'top', 'discussed'];

  static String title(String sort) => switch (sort) {
    'top' => tr('По лайкам'),
    'discussed' => tr('По ответам'),
    _ => tr('Свежие'),
  };
}

// ============================================================================
//  КАТАЛОГ
// ============================================================================

class ForumsCatalogState {
  const ForumsCatalogState({
    this.forums = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<Forum> forums;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  ForumsCatalogState copyWith({
    List<Forum>? forums,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return ForumsCatalogState(
      forums: forums ?? this.forums,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Ключ каталога — `scope|sort|запрос`. Новый ключ = новый нотифайер, как это
/// уже делает лента сообщества с фильтром: состояние не надо чистить вручную.
class ForumsCatalogNotifier extends StateNotifier<ForumsCatalogState> {
  ForumsCatalogNotifier(this._api, this.key)
    : super(const ForumsCatalogState()) {
    load();
  }

  static const int _limit = 30;

  final ApiService _api;
  final String key;

  String get scope => _part(0, 'all');
  String get sort => _part(1, 'active');
  String get query => _part(2, '');

  String _part(int index, String fallback) {
    final parts = key.split('|');
    final value = index < parts.length ? parts[index] : '';
    return value.isEmpty ? fallback : value;
  }

  static String buildKey({
    String scope = 'all',
    String sort = 'active',
    String query = '',
  }) => '$scope|$sort|${query.trim()}';

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(
        'api/forums',
        queryParams: {
          'scope': scope,
          'sort': sort,
          'limit': '$_limit',
          'offset': '0',
          if (query.isNotEmpty) 'q': query,
        },
      );
      final rows = (response is Map ? response['forums'] : null) ?? const [];
      state = state.copyWith(
        forums: [
          for (final row in rows)
            if (row is Map) Forum.fromCatalog(row),
        ],
        isLoading: false,
        hasMore: rows.length == _limit,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendly(e));
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final response = await _api.get(
        'api/forums',
        queryParams: {
          'scope': scope,
          'sort': sort,
          'limit': '$_limit',
          'offset': '${state.forums.length}',
          if (query.isNotEmpty) 'q': query,
        },
      );
      final rows = (response is Map ? response['forums'] : null) ?? const [];
      state = state.copyWith(
        forums: [
          ...state.forums,
          for (final row in rows)
            if (row is Map) Forum.fromCatalog(row),
        ],
        isLoadingMore: false,
        hasMore: rows.length == _limit,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: _friendly(e));
    }
  }

  /// Создание сообщества. Ошибку возвращает строкой — порог стажа, лимит на
  /// сутки и занятый адрес бэк объясняет сам, и объяснение лучше любой
  /// догадки клиента.
  Future<ForumCreateResult> create({
    required String name,
    String description = '',
    String slug = '',
    bool isRestricted = false,
  }) async {
    try {
      final response = await _api.post(
        'api/forums',
        body: {
          'name': name.trim(),
          'description': description.trim(),
          if (slug.trim().isNotEmpty) 'slug': slug.trim(),
          'is_restricted': isRestricted,
        },
      );
      final id = (response is Map ? response['id'] : null)?.toString() ?? '';
      final newSlug =
          (response is Map ? response['slug'] : null)?.toString() ?? '';
      if (id.isEmpty) {
        return ForumCreateResult.error(tr('Сервер не вернул сообщество'));
      }
      await load(silent: true);
      return ForumCreateResult.created(
        Forum(
          id: id,
          slug: newSlug,
          name: name.trim(),
          description: description.trim(),
          isRestricted: isRestricted,
          joined: true,
          memberCount: 1,
        ),
      );
    } catch (e) {
      return ForumCreateResult.error(_friendly(e));
    }
  }
}

/// Результат создания: нужен и id, и slug, чтобы сразу открыть лобби.
class ForumCreateResult {
  const ForumCreateResult.created(this.forum) : error = null;
  const ForumCreateResult.error(this.error) : forum = null;

  final Forum? forum;
  final String? error;

  bool get ok => forum != null;
}

final forumsCatalogProvider =
    StateNotifierProvider.family<
      ForumsCatalogNotifier,
      ForumsCatalogState,
      String
    >((ref, key) => ForumsCatalogNotifier(ref.read(apiServiceProvider), key));

// ============================================================================
//  ЛОББИ ФОРУМА
// ============================================================================

class ForumLobbyState {
  const ForumLobbyState({
    this.forum,
    this.mods = const [],
    this.topics = const [],
    this.sort = 'new',
    this.viewerId = '',
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final Forum? forum;
  final List<ForumPerson> mods;
  final List<ForumTopic> topics;
  final String sort;
  final String viewerId;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  /// Право модерировать: создатель, модератор этого форума. Админ проходит тот
  /// же тест на сервере — но клиент про его роль ничего не знает, поэтому
  /// кнопки просто не покажет, и это безопаснее, чем угадывать.
  bool get canModerate {
    if (viewerId.isEmpty || forum == null) return false;
    if (forum!.creatorId == viewerId) return true;
    return mods.any((m) => m.id == viewerId && m.moderator);
  }

  /// Создатель отдела ещё и на назначение модераторов — право, которое бэк не
  /// отдаёт никому, кроме него и админа.
  bool get isCreator =>
      viewerId.isNotEmpty && forum != null && forum!.creatorId == viewerId;

  bool get isMember => forum?.joined ?? false;

  ForumLobbyState copyWith({
    Forum? forum,
    List<ForumPerson>? mods,
    List<ForumTopic>? topics,
    String? sort,
    String? viewerId,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return ForumLobbyState(
      forum: forum ?? this.forum,
      mods: mods ?? this.mods,
      topics: topics ?? this.topics,
      sort: sort ?? this.sort,
      viewerId: viewerId ?? this.viewerId,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Лобби — один нотифайер на сообщество: шапка, модеры и список топиков
/// меняются вместе (вступление, новый топик, удаление), и держать их в трёх
/// провайдерах значило бы синхронизировать их вручную.
class ForumLobbyNotifier extends StateNotifier<ForumLobbyState> {
  ForumLobbyNotifier(this._api, this.slug) : super(const ForumLobbyState()) {
    load();
  }

  static const int _limit = 25;

  final ApiService _api;
  final String slug;

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(viewerId: prefs.getString('user_id') ?? '');
    await Future.wait([_loadForum(), _loadTopics(reset: true)]);
    state = state.copyWith(isLoading: false);
  }

  Future<void> _loadForum() async {
    try {
      final response = await _api.get('api/forums/$slug');
      final raw = response is Map ? response['forum'] : null;
      if (raw is! Map) return;
      state = state.copyWith(
        forum: Forum.fromLobby(raw),
        mods: [
          for (final row in (response['mods'] as List?) ?? const [])
            if (row is Map) ForumPerson.fromProfile(row),
        ],
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(error: _friendly(e));
    }
  }

  Future<void> _loadTopics({required bool reset}) async {
    try {
      final response = await _api.get(
        'api/forums/$slug/posts',
        queryParams: {
          'sort': state.sort,
          'limit': '$_limit',
          'offset': reset ? '0' : '${state.topics.length}',
        },
      );
      final rows = (response is Map ? response['topics'] : null) ?? const [];
      final fetched = [
        for (final row in rows)
          if (row is Map) ForumTopic.fromJson(row),
      ];
      state = state.copyWith(
        topics: reset ? fetched : [...state.topics, ...fetched],
        hasMore: rows.length == _limit,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(error: _friendly(e));
    }
  }

  /// Лайк тодика. Отдельного эндпоинта форумам не нужен: топик — это пост
  /// сообщества на полке форума, и `author_post_likes` принимает его как есть.
  /// Без этой кнопки лента знала рейтинг, но не давала на него влиять.
  Future<String?> toggleTopicLike(ForumTopic topic) async {
    final wasLiked = topic.isLikedByViewer;
    _replaceTopic(
      topic.id,
      topic.copyWith(
        isLikedByViewer: !wasLiked,
        likesCount: topic.likesCount + (wasLiked ? -1 : 1),
      ),
    );
    try {
      final response = await _api.post(
        'api/author-walls/posts/${topic.id}/like',
      );
      final liked = response is Map && response['liked'] == true;
      _replaceTopic(
        topic.id,
        topic.copyWith(
          isLikedByViewer: liked,
          likesCount: _likedCount(from: topic, wasLiked: wasLiked, liked: liked),
        ),
      );
      return null;
    } catch (e) {
      _replaceTopic(topic.id, topic);
      return _friendly(e);
    }
  }

  void _replaceTopic(String id, ForumTopic next) {
    state = state.copyWith(
      topics: [
        for (final topic in state.topics)
          if (topic.id == id) next else topic,
      ],
    );
  }

  Future<void> setSort(String sort) async {
    if (!ForumSorts.values.contains(sort) || state.sort == sort) return;
    state = state.copyWith(sort: sort, isLoadingMore: true);
    await _loadTopics(reset: true);
    state = state.copyWith(isLoadingMore: false);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    await _loadTopics(reset: false);
    state = state.copyWith(isLoadingMore: false);
  }

  /// Вступление нужно только для поста в закрытом форуме, но кнопка стоит в
  /// шапке: человеку полезно видеть, участник он или нет.
  Future<String?> toggleJoin() async {
    final forum = state.forum;
    if (forum == null) return tr('Сообщество ещё не загрузилось');
    final joining = !forum.joined;
    state = state.copyWith(forum: forum.copyWith(joined: joining));
    try {
      if (joining) {
        await _api.post('api/forums/$slug/join');
      } else {
        await _api.delete('api/forums/$slug/join');
      }
      await _loadForum();
      return null;
    } catch (e) {
      state = state.copyWith(forum: forum);
      return _friendly(e);
    }
  }

  /// Новый топик. Бэк отдаёт строку поста без автора, поэтому после успеха
  /// список перечитывается молча — зато порядок сортировки не врёт.
  Future<String?> addTopic({
    required String title,
    required String body,
    List<String> mediaUrls = const [],
  }) async {
    try {
      await _api.post(
        'api/forums/$slug/posts',
        body: {
          'title': title.trim(),
          'content': body.trim(),
          'media_urls': mediaUrls,
        },
      );
      await _loadTopics(reset: true);
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Снятие топика. Заголовок отдаём бэку отдельно: он идёт в уведомление
  /// автору, и без него «топик удалён» — это гадание, какой именно.
  Future<String?> removeTopic(
    String postId, {
    String reason = '',
    String title = '',
  }) async {
    try {
      await _api.post(
        'api/forums/$slug/posts/$postId/remove',
        body: {'reason': reason, 'topic_title': title},
      );
      state = state.copyWith(
        topics: state.topics.where((t) => t.id != postId).toList(),
      );
      return null;
    } catch (e) {
      await _loadTopics(reset: true);
      return _friendly(e);
    }
  }

  Future<String?> ban(ForumPerson person, {String reason = ''}) async {
    try {
      await _api.post(
        'api/forums/$slug/ban/${person.id}',
        body: {'reason': reason},
      );
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  Future<String?> unban(String userId) async {
    try {
      await _api.delete('api/forums/$slug/ban/$userId');
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Список ограничений грузится отдельно: он нужен только модератору, и
  /// только когда он открыл этот лист, а не при каждом входе в сообщество.
  /// Ошибку отдаём строкой, а не молча пустым списком: «никто не ограничен»
  /// и «бэк не ответил» модератор обязан различать.
  Future<({List<ForumBan> bans, String? error})> bans() async {
    try {
      final response = await _api.get('api/forums/$slug/bans');
      final rows = (response is Map ? response['bans'] : null) ?? const [];
      return (
        bans: [
          for (final row in rows)
            if (row is Map) ForumBan.fromJson(row),
        ],
        error: null,
      );
    } catch (e) {
      return (
        bans: const <ForumBan>[],
        error: serverErrorMessage(
          e,
          fallback: tr('Не удалось загрузить ограничения'),
        ),
      );
    }
  }

  /// Модератора назначает только создатель форума — бэк это проверяет, и
  /// отказ приходит готовой строкой.
  Future<String?> addModerator(String userId) async {
    try {
      await _api.post('api/forums/$slug/moderators/$userId');
      await _loadForum();
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  Future<String?> saveSettings({
    String? name,
    String? description,
    bool? isRestricted,
  }) async {
    if (state.forum == null) return tr('Сообщество ещё не загрузилось');
    // Отправляем только те поля, которые человек правил: PATCH на бэке
    // подменяет через COALESCE, но пустая строка в теле — это не «не трогать».
    final body = <String, Object?>{};
    if (name != null) body['name'] = name.trim();
    if (description != null) body['description'] = description.trim();
    if (isRestricted != null) body['is_restricted'] = isRestricted;
    try {
      await _api.patch('api/forums/$slug', body: body);
      // Ответ PATCH содержит только изменённые колонки, а лобби показывает ещё
      // и счётчики — поэтому шапка перечитывается целиком.
      await _loadForum();
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  Future<String?> report(String reason) async {
    try {
      await _api.post('api/forums/$slug/report', body: {'reason': reason});
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }
}

final forumLobbyProvider =
    StateNotifierProvider.family<ForumLobbyNotifier, ForumLobbyState, String>(
      (ref, slug) => ForumLobbyNotifier(ref.read(apiServiceProvider), slug),
    );

/// Форум-обсуждение квеста резолвится по месту и заводится первым обращением,
/// поэтому у карточки квеста нет отдельного «создать обсуждение».
Future<ForumRef> openQuestForum(ApiService api, String questId) async {
  final response = await api.get('api/forums/quest/$questId');
  if (response is! Map) {
    throw Exception(tr('Сервер не вернул обсуждение квеста'));
  }
  return ForumRef(
    id: (response['forum_id'] ?? '').toString(),
    slug: (response['slug'] ?? '').toString(),
  );
}

class ForumRef {
  const ForumRef({required this.id, required this.slug});

  final String id;
  final String slug;
}

// ============================================================================
//  ГОРЯЧИЕ ОБСУЖДЕНИЯ — блок общей ленты
// ============================================================================

class ForumHotTopicsState {
  const ForumHotTopicsState({this.topics = const [], this.loaded = false});

  final List<ForumHotTopic> topics;
  final bool loaded;

  ForumHotTopicsState copyWith({
    List<ForumHotTopic>? topics,
    bool? loaded,
  }) => ForumHotTopicsState(
    topics: topics ?? this.topics,
    loaded: loaded ?? this.loaded,
  );
}

/// Обсуждения изо всех сообществ разом. Ленте этот блок нужен затем, чтобы
/// человек наталкивался на разговор, а не искал его через каталог: у ленты
/// своей навигации по сообществам нет.
///
/// Ошибку не показываем намеренно: пустой блок — нормальное состояние ленты,
/// в отличие от упавшего запроса.
class ForumHotTopicsNotifier extends StateNotifier<ForumHotTopicsState> {
  ForumHotTopicsNotifier(this._api) : super(const ForumHotTopicsState()) {
    _load();
  }

  final ApiService _api;

  Future<void> _load() async {
    try {
      final response = await _api.get('api/forums/topics/hot?limit=6');
      final list = response is Map ? response['topics'] : null;
      state = state.copyWith(
        topics: list is List
            ? [
                for (final row in list)
                  if (row is Map) ForumHotTopic.fromJson(row),
              ]
            : const [],
        loaded: true,
      );
    } catch (_) {
      state = state.copyWith(topics: const [], loaded: true);
    }
  }

  Future<String?> toggleLike(ForumHotTopic item) async {
    final topic = item.topic;
    final wasLiked = topic.isLikedByViewer;
    _replace(
      item,
      topic.copyWith(
        isLikedByViewer: !wasLiked,
        likesCount: topic.likesCount + (wasLiked ? -1 : 1),
      ),
    );
    try {
      final response = await _api.post(
        'api/author-walls/posts/${topic.id}/like',
      );
      final liked = response is Map && response['liked'] == true;
      _replace(
        item,
        topic.copyWith(
          isLikedByViewer: liked,
          likesCount: _likedCount(from: topic, wasLiked: wasLiked, liked: liked),
        ),
      );
      return null;
    } catch (e) {
      _replace(item, topic);
      return _friendly(e);
    }
  }

  void _replace(ForumHotTopic item, ForumTopic next) {
    state = state.copyWith(
      topics: [
        for (final current in state.topics)
          if (current.topic.id == item.topic.id) current.withTopic(next) else current,
      ],
    );
  }
}

/// Провайдер не autoDispose: блок нужен один разговор на сессию, а свежеть
/// ему даёт pull-to-refresh в ленте (`ref.invalidate`).
final forumHotTopicsProvider =
    StateNotifierProvider<ForumHotTopicsNotifier, ForumHotTopicsState>(
      (ref) => ForumHotTopicsNotifier(ref.read(apiServiceProvider)),
    );

String _friendly(Object error) =>
    serverErrorMessage(error, fallback: tr('Не удалось загрузить сообщества'));

/// Счётчик пересобираем от исходного числа, а не от оптимистичного: сервер
/// вольен ответить не так, как мы угадали (отказ, гонка), и тогда список
/// должен сойтись с ним, а не накопить ошибку на каждом тапе.
int _likedCount({
  required ForumTopic from,
  required bool wasLiked,
  required bool liked,
}) => from.likesCount + (liked ? 1 : 0) - (wasLiked ? 1 : 0);
