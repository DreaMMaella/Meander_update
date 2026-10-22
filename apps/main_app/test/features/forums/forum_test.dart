// Форум — это полка для обычных постов, поэтому одному и тому же человеку бэк
// даёт то `creator_name`, то `full_name`, то `author_name`. Глазом это видно
// только тапнув по сообществу, а расхождение выглядит как «ник изменился,
// оформление пропало», поэтому зафиксировано ровно то, где клиент обязан
// угадать раскладку колонок: оформление автора, право модерировать и
// оптимистичное вступление с откатом.

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/forums/models/forum_models.dart';
import 'package:canvas_app/features/forums/providers/forum_provider.dart';
import 'package:canvas_app/features/forums/screens/forum_lobby_screen.dart';
import 'package:canvas_app/models/wall_post_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi({
    Map<String, dynamic Function()>? routes,
    Set<String> fail = const {},
  }) : _routes = routes ?? const {},
       _fail = fail;

  final Map<String, dynamic Function()> _routes;
  final Set<String> _fail;
  final List<String> calls = [];
  final List<Map<String, String>> queries = [];
  final List<(String, Map<String, dynamic>?)> writes = [];
  final List<Map<String, dynamic>?> patches = [];

  dynamic _call(String endpoint) {
    if (_fail.contains(endpoint)) {
      throw Exception('Exception: {"error":"Сообщество закрыто для вас"}');
    }
    final route = _routes[endpoint];
    if (route == null) throw Exception('неизвестный эндпоинт $endpoint');
    return route();
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    calls.add(endpoint);
    queries.add(queryParams ?? const {});
    return _call(endpoint);
  }

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    calls.add('POST $endpoint');
    writes.add((endpoint, body));
    return _call('POST $endpoint');
  }

  @override
  Future<dynamic> patch(String endpoint, {Map<String, dynamic>? body}) async {
    patches.add(body);
    return _call('PATCH $endpoint');
  }

  @override
  Future<dynamic> delete(String endpoint, {Map<String, dynamic>? body}) async {
    calls.add('DELETE $endpoint');
    _call('DELETE $endpoint');
  }
}

Map<String, dynamic> _catalogRow({
  String id = 'forum-1',
  String slug = 'games',
  String name = 'Игры',
  String creatorId = 'user-1',
  String creatorName = 'Аня',
  bool joined = false,
  int? memberCount,
}) => {
  'id': id,
  'slug': slug,
  'name': name,
  'description': 'Обо всём игровом',
  'kind': 'user',
  'creator_id': creatorId,
  'creator_name': creatorName,
  'creator_avatar_url': 'https://cdn/a.png',
  'creator_cosmetics': {
    'avatar_frame': 'prism_ring',
    'name_style': 'royal_gold',
  },
  'creator_role': 'user',
  'is_restricted': false,
  'member_count': memberCount ?? 12,
  'topics_count': '8',
  'last_activity_at': '2026-09-20T10:00:00.000Z',
  'joined': joined,
};

Map<String, dynamic> _topicRow({
  String id = 'post-1',
  String title = 'Что играли на выходных?',
  String authorId = 'user-7',
  String authorName = 'Витя',
  int comments = 4,
}) => {
  'id': id,
  'title': title,
  'content': 'Рассказывайте',
  'author_id': authorId,
  'author_name': authorName,
  'author_avatar_url': 'https://cdn/v.png',
  'author_cosmetics': {'name_style': 'royal_gold'},
  'likes_count': 3,
  'comments_count': comments,
  'is_liked_by_viewer': true,
  'created_at': '2026-09-21T08:00:00.000Z',
  'media_urls': ['https://cdn/1.png'],
  'tags': ['обсуждение'],
};

/// Состояние лобби на стороне сервера: живёт в замыкании, чтобы тест мог
/// проверить, что клиент перечитывает шапку после вступления, а не верит себе.
class _Server {
  _Server({bool joined = false, this.creatorId = 'user-1'}) : _joined = joined;

  bool _joined;
  final bool banned = false;
  final String creatorId;
  final List<Map<String, dynamic>> topics = [_topicRow()];

  Map<String, dynamic> Function() get lobbyRoutes =>
      () => {
        'forum': {
          'id': 'forum-1',
          'slug': 'games',
          'name': 'Игры',
          'description': 'Обо всём игровом',
          'kind': 'user',
          'creator_id': creatorId,
          'is_restricted': false,
          'member_count': 12,
          'topics_count': topics.length,
          'joined': _joined,
          'banned': banned,
        },
        'mods': [
          {
            'id': creatorId,
            'full_name': 'Аня',
            'cosmetics': {'avatar_frame': 'prism_ring'},
            'forum_role': 'mod',
            'joined_at': '2026-09-01T10:00:00.000Z',
          },
        ],
      };

  Map<String, dynamic> Function() get postsRoutes =>
      () => {'forum_id': 'forum-1', 'slug': 'games', 'topics': topics};

  Map<String, dynamic Function()> get asRoutes => {
    'api/forums/games': lobbyRoutes,
    'api/forums/games/posts': postsRoutes,
  };

  /// Вступление и выход меняют состояние сервера: иначе тест проверил бы
  /// оптимистичную правку клиента, а не то, что он перечитывает шапку после
  /// ответа.
  Map<String, dynamic Function()> get joinRoutes => {
    'POST api/forums/games/join': () {
      _joined = true;
      return {'joined': true};
    },
    'DELETE api/forums/games/join': () {
      _joined = false;
      return {'joined': false};
    },
  };
}

Future<T> _settled<T>(T Function() read, bool Function(T) busy) async {
  for (var i = 0; i < 100 && busy(read()); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return read();
}

void main() {
  group('ForumPerson', () {
    test(
      'каталог отдаёт создателя колонками creator_ — ник форума не должен стать ником человека',
      () {
        final forum = Forum.fromCatalog(_catalogRow());
        final creator = forum.creator!;
        // `name` в этой же строке — название сообщества.
        expect(forum.name, 'Игры');
        expect(creator.name, 'Аня');
        expect(creator.avatarUrl, 'https://cdn/a.png');
        expect(creator.equipped.avatarFrame, 'prism_ring');
        expect(creator.equipped.nameStyle, 'royal_gold');
        expect(creator.moderator, isFalse);
      },
    );

    test('модеры лобби приходят профилем без префикса, но с ролью форума', () {
      final mod = ForumPerson.fromProfile({
        'id': 'user-1',
        'full_name': 'Аня',
        'cosmetics': {'avatar_frame': 'prism_ring'},
        'role': 'admin',
        'forum_role': 'mod',
        'joined_at': '2026-09-01T10:00:00.000Z',
      });
      expect(mod.name, 'Аня');
      expect(mod.equipped.avatarFrame, 'prism_ring');
      expect(mod.moderator, isTrue);
      expect(mod.isStaff, isTrue);
      expect(mod.joinedAt, DateTime.parse('2026-09-01T10:00:00.000Z'));
    });

    test('автор топика разбирается из author_ и сохраняет цветной ник', () {
      final topic = ForumTopic.fromJson(_topicRow());
      expect(topic.author.id, 'user-7');
      expect(topic.author.name, 'Витя');
      expect(topic.author.equipped.nameStyle, 'royal_gold');
      expect(topic.mediaUrls, ['https://cdn/1.png']);
    });

    test('без имени человек всё равно подписан, а не пустой строкой', () {
      expect(ForumPerson.fromAuthor(const {}).name, 'Пользователь');
    });
  });

  group('Forum', () {
    test('счётчики из строк и чисел читаются одинаково', () {
      final forum = Forum.fromCatalog(_catalogRow());
      expect(forum.memberCount, 12);
      expect(forum.topicsCount, 8);
      expect(forum.lastActivityAt, DateTime.parse('2026-09-20T10:00:00.000Z'));
    });

    test('лобби знает бан, а каталог не знает', () {
      final lobby = Forum.fromLobby({
        'id': 'forum-1',
        'slug': 'games',
        'name': 'Игры',
        'joined': true,
        'banned': true,
        'quest_title': 'Таблички',
      });
      expect(lobby.joined, isTrue);
      expect(lobby.banned, isTrue);
      expect(Forum.fromCatalog(_catalogRow()).banned, isFalse);
    });

    test('обсуждение квеста отличается от сообщества по kind', () {
      final quest = Forum.fromCatalog({
        'id': 'forum-2',
        'slug': 'q-abc',
        'name': 'Обсуждение',
        'kind': 'quest',
        'quest_id': 'quest-9',
      });
      expect(quest.isQuestForum, isTrue);
    });
  });

  group('ForumsCatalogNotifier', () {
    Future<ForumsCatalogNotifier> openCatalog(
      _FakeApi api, {
      String key = 'all|active|',
    }) async {
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      // Конструктор сам запустил загрузку — ждать надо именно её.
      return _settled(
        () => container.read(forumsCatalogProvider(key).notifier),
        (n) => n.state.isLoading,
      );
    }

    test(
      'ключ несёт фильтры, а пустые части возвращаются к значениям по умолчанию',
      () {
        expect(
          ForumsCatalogNotifier.buildKey(
            scope: 'mine',
            sort: 'new',
            query: '  коты  ',
          ),
          'mine|new|коты',
        );
        final key = ForumsCatalogNotifier.buildKey();
        expect(key, 'all|active|');
      },
    );

    test(
      'поиск уходит на сервер отдельным параметром, а без него его нет',
      () async {
        final empty = _FakeApi(
          routes: {
            'api/forums': () => {'forums': []},
          },
        );
        final search = _FakeApi(
          routes: {
            'api/forums': () => {'forums': []},
          },
        );
        await openCatalog(empty);
        await openCatalog(search, key: 'all|new|коты');

        expect(empty.queries.first, isNot(contains('q')));
        expect(empty.queries.first['sort'], 'active');
        expect(search.queries.first['q'], 'коты');
        expect(search.queries.first['sort'], 'new');
      },
    );

    test('страница целиком — есть что подгружать, неполная — нет', () async {
      final full = List.generate(30, (i) => _catalogRow(id: 'f$i'));
      var hits = 0;
      final api = _FakeApi(
        routes: {
          'api/forums': () {
            hits++;
            return {'forums': hits == 1 ? full : const []};
          },
        },
      );
      final notifier = await openCatalog(api);
      expect(notifier.state.forums.length, 30);
      expect(notifier.state.hasMore, isTrue);

      await notifier.loadMore();
      expect(notifier.state.forums.length, 30);
      expect(notifier.state.hasMore, isFalse);
      expect(api.queries.last['offset'], '30');
    });

    test(
      'отказ бэка показывается его русским объяснением, а не догадкой клиента',
      () async {
        final api = _FakeApi(
          fail: {'api/forums'},
          routes: {
            'api/forums': () => {'forums': []},
          },
        );
        final notifier = await openCatalog(api);
        expect(notifier.state.forums, isEmpty);
        expect(notifier.state.error, 'Сообщество закрыто для вас');
      },
    );

    test(
      'создание возвращает сообщество со слагом сервера и перезагружает ленту',
      () async {
        var hits = 0;
        final api = _FakeApi(
          routes: {
            'api/forums': () {
              hits++;
              return {
                'forums': [
                  _catalogRow(id: 'forum-9', slug: 'kotiki', name: 'Котики'),
                ],
              };
            },
            'POST api/forums': () => {'id': 'forum-9', 'slug': 'kotiki'},
          },
        );
        final notifier = await openCatalog(api);
        final result = await notifier.create(
          name: '  Котики  ',
          description: 'Мур',
          slug: '',
          isRestricted: true,
        );

        expect(result.ok, isTrue);
        expect(result.forum!.slug, 'kotiki');
        expect(result.forum!.joined, isTrue, reason: 'создатель уже участник');
        expect(result.forum!.isRestricted, isTrue);
        // Пустой slug сервер выводит сам — в теле его быть не должно.
        expect(api.writes.first.$2, {
          'name': 'Котики',
          'description': 'Мур',
          'is_restricted': true,
        });
        expect(hits, 2);
      },
    );

    test(
      'создание по порогу стажа отдаёт текст бэка и не трогает ленту',
      () async {
        final api = _FakeApi(
          fail: {'POST api/forums'},
          routes: {
            'api/forums': () => {'forums': []},
          },
        );
        final notifier = await openCatalog(api);
        final before = api.calls.where((c) => c == 'api/forums').length;
        final result = await notifier.create(name: 'Котики');

        expect(result.ok, isFalse);
        expect(result.error, 'Сообщество закрыто для вас');
        expect(
          api.calls.where((c) => c == 'api/forums').length,
          before,
          reason: 'ленту перечитывать незачем',
        );
      },
    );
  });

  group('ForumLobbyNotifier', () {
    Future<ForumLobbyNotifier> openLobby(
      _FakeApi api, {
      String me = 'me',
    }) async {
      SharedPreferences.setMockInitialValues({'user_id': me});
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      return _settled(
        () => container.read(forumLobbyProvider('games').notifier),
        (n) => n.state.isLoading,
      );
    }

    test(
      'модерировать может создатель и модератор из списка, а не любой участник',
      () async {
        final server = _Server(creatorId: 'user-1');
        final owner = await openLobby(
          _FakeApi(routes: server.asRoutes),
          me: 'user-1',
        );
        expect(owner.state.forum!.creatorId, 'user-1');
        expect(owner.state.canModerate, isTrue);

        // Тот же форум, но создатель другой: право теперь только из списка модеров.
        Map<String, dynamic> foreignLobby() {
          final payload = server.lobbyRoutes();
          return {
            ...payload,
            'forum': {...payload['forum'] as Map, 'creator_id': 'someone-else'},
          };
        }

        final mod = await openLobby(
          _FakeApi(
            routes: {
              'api/forums/games': foreignLobby,
              'api/forums/games/posts': server.postsRoutes,
            },
          ),
          me: 'user-1',
        );
        expect(mod.state.mods.single.moderator, isTrue);
        expect(
          mod.state.canModerate,
          isTrue,
          reason: 'user-1 в списке модеров',
        );

        final stranger = await openLobby(
          _FakeApi(routes: server.asRoutes),
          me: 'me',
        );
        expect(stranger.state.canModerate, isFalse);

        // Неизвестен зритель — нет и кнопок: показать лишнее опаснее, чем спрятать.
        final anonymous = await openLobby(
          _FakeApi(routes: server.asRoutes),
          me: '',
        );
        expect(anonymous.state.canModerate, isFalse);
      },
    );

    test('вступление откатывается, если сервер отказал', () async {
      final server = _Server();
      final api = _FakeApi(
        routes: server.asRoutes,
        fail: {'POST api/forums/games/join'},
      );
      final notifier = await openLobby(api);
      expect(notifier.state.forum!.joined, isFalse);

      final error = await notifier.toggleJoin();
      expect(error, 'Сообщество закрыто для вас');
      expect(notifier.state.forum!.joined, isFalse, reason: 'оптимизм отменён');

      server._joined = true;
      final ok = _FakeApi(routes: {...server.asRoutes, ...server.joinRoutes});
      final joined = await openLobby(ok);
      expect(joined.state.forum!.joined, isTrue);

      // Уход — это DELETE, а не тот же POST: проверяем оба направления.
      expect(await joined.toggleJoin(), isNull);
      expect(joined.state.forum!.joined, isFalse);
      expect(await joined.toggleJoin(), isNull);
      expect(joined.state.forum!.joined, isTrue);
      expect(
        ok.writes.map((w) => w.$1),
        contains('api/forums/games/join'),
        reason: 'вступление ходит на POST',
      );
      expect(ok.calls, contains('DELETE api/forums/games/join'));
    });

    test(
      'новый топик перечитывает ленту: пост без автора нельзя вставить в неё напрямую',
      () async {
        final server = _Server();
        final api = _FakeApi(
          routes: {
            ...server.asRoutes,
            'POST api/forums/games/posts': () => {'id': 'post-2'},
          },
        );
        final notifier = await openLobby(api);
        server.topics.add(
          _topicRow(id: 'post-2', authorId: '', authorName: ''),
        );

        expect(
          await notifier.addTopic(title: 'Что играли?', body: 'Рассказывайте'),
          isNull,
        );
        expect(notifier.state.topics.length, 2);
        expect(api.writes.first.$2, {
          'title': 'Что играли?',
          'content': 'Рассказывайте',
          'media_urls': <String>[],
        });
      },
    );

    test('сортировка меняет только ленту, шапку не трогает', () async {
      final server = _Server();
      final api = _FakeApi(routes: server.asRoutes);
      final notifier = await openLobby(api);
      final before = api.calls.length;

      await notifier.setSort('discussed');
      expect(notifier.state.sort, 'discussed');
      expect(api.queries.last['sort'], 'discussed');
      expect(api.calls.length, before + 1);
    });

    test('настройки отправляют только изменённые поля', () async {
      final server = _Server();
      final api = _FakeApi(
        routes: {
          ...server.asRoutes,
          'PATCH api/forums/games': () => {'name': 'Игры 2'},
        },
      );
      final notifier = await openLobby(api);

      await notifier.saveSettings(name: '  Игры 2  ');
      expect(api.patches, [
        {'name': 'Игры 2'},
      ]);
      // Ответ PATCH неполный, поэтому шапка перечитывается целиком.
      expect(api.calls.where((c) => c == 'api/forums/games').length, 2);
    });

    test('бан топика убирает его из списка без перезагрузки', () async {
      final server = _Server();
      final api = _FakeApi(
        routes: {
          ...server.asRoutes,
          'POST api/forums/games/posts/post-1/remove': () => {'ok': true},
        },
      );
      final notifier = await openLobby(api);
      final before = api.calls.length;

      expect(await notifier.removeTopic('post-1', reason: 'спам'), isNull);
      expect(notifier.state.topics, isEmpty);
      expect(api.calls.length, before + 1);
    });

    test(
      'снятие топика передаёт заголовок: автору придёт «что именно сняли»',
      () async {
        final server = _Server();
        final api = _FakeApi(
          routes: {
            ...server.asRoutes,
            'POST api/forums/games/posts/post-1/remove': () => {'ok': true},
          },
        );
        final notifier = await openLobby(api);

        await notifier.removeTopic(
          'post-1',
          reason: 'оффтоп',
          title: 'Что играли на выходных?',
        );
        expect(api.writes.first.$2, {
          'reason': 'оффтоп',
          'topic_title': 'Что играли на выходных?',
        });
      },
    );

    test(
      'список ограничений грузится отдельно и не путает пустоту с отказом',
      () async {
        final server = _Server();
        final api = _FakeApi(
          routes: {
            ...server.asRoutes,
            'api/forums/games/bans': () => {
              'bans': [
                {
                  'id': 'user-7',
                  'full_name': 'Витя',
                  'cosmetics': {'name_style': 'royal_gold'},
                  'reason': 'спам',
                  'banned_at': '2026-09-22T08:00:00.000Z',
                },
              ],
            },
          },
        );
        final notifier = await openLobby(api);
        // Лишних запросов нет: при входе в сообщество список ограничений не
        // грузится, он нужен только самому листу.
        expect(api.calls, ['api/forums/games', 'api/forums/games/posts']);

        final bans = await notifier.bans();
        expect(bans.error, isNull);
        expect(bans.bans.single.person.name, 'Витя');
        expect(bans.bans.single.person.equipped.nameStyle, 'royal_gold');
        expect(bans.bans.single.reason, 'спам');
        expect(
          bans.bans.single.bannedAt,
          DateTime.parse('2026-09-22T08:00:00.000Z'),
        );
        expect(api.calls.last, 'api/forums/games/bans');

        // Пустой список и «бэк не ответил» — разные вещи: без этой развилки
        // модератор прочитал бы «никто не ограничен» там, где ответа нет.
        final broken = await openLobby(_FakeApi(routes: server.asRoutes));
        final failed = await broken.bans();
        expect(failed.bans, isEmpty);
        expect(failed.error, 'Не удалось загрузить ограничения');
      },
    );

    test(
      'назначение модератора перечитывает шапку: список должен обновиться',
      () async {
        final server = _Server();
        var modsAdded = false;
        final api = _FakeApi(
          routes: {
            'api/forums/games': () {
              final payload = server.lobbyRoutes();
              if (!modsAdded) return payload;
              return {
                ...payload,
                'mods': [
                  ...(payload['mods'] as List),
                  {'id': 'user-7', 'full_name': 'Витя', 'forum_role': 'mod'},
                ],
              };
            },
            'api/forums/games/posts': server.postsRoutes,
            'POST api/forums/games/moderators/user-7': () {
              modsAdded = true;
              return {'success': true};
            },
          },
        );
        final notifier = await openLobby(api);
        expect(notifier.state.mods.length, 1);

        expect(await notifier.addModerator('user-7'), isNull);
        expect(notifier.state.mods.length, 2);
      },
    );

    test('создатель отличается от модератора: назначает только он', () async {
      final server = _Server();
      final creator = await openLobby(
        _FakeApi(routes: server.asRoutes),
        me: 'user-1',
      );
      expect(creator.state.isCreator, isTrue);

      final modOnly = await openLobby(
        _FakeApi(
          routes: {
            'api/forums/games': () {
              final payload = server.lobbyRoutes();
              return {
                ...payload,
                'forum': {
                  ...(payload['forum'] as Map),
                  'creator_id': 'someone-else',
                },
              };
            },
            'api/forums/games/posts': server.postsRoutes,
          },
        ),
        me: 'user-1',
      );
      expect(modOnly.state.canModerate, isTrue);
      expect(modOnly.state.isCreator, isFalse);
    });

    test('жалоба и бан уходят на адреса форума', () async {
      final server = _Server();
      final api = _FakeApi(
        routes: {
          ...server.asRoutes,
          'POST api/forums/games/report': () => {'id': 'r1'},
          'POST api/forums/games/ban/user-7': () => {'ok': true},
          'DELETE api/forums/games/ban/user-7': () {},
        },
      );
      final notifier = await openLobby(api);
      final author = ForumPerson.fromAuthor(_topicRow());

      expect(await notifier.report('спам'), isNull);
      expect(await notifier.ban(author, reason: 'спам'), isNull);
      expect(await notifier.unban('user-7'), isNull);
      expect(api.writes.map((w) => w.$1), [
        'api/forums/games/report',
        'api/forums/games/ban/user-7',
      ]);
      expect(api.calls, contains('DELETE api/forums/games/ban/user-7'));
    });
  });

  group('ForumTopic → WallPost', () {
    test(
      'топик открывается тем же экраном, что пост стены, и не теряет заголовок',
      () {
        final post = ForumTopic.fromJson(_topicRow()).toWallPost();
        expect(post.title, 'Что играли на выходных?');
        expect(post.content, 'Рассказывайте');
        expect(post.authorId, 'user-7');
        expect(post.authorCosmetics.nameStyle, 'royal_gold');
        expect(post.isLikedByViewer, isTrue);
        expect(post.viewsCount, 0);
      },
    );

    test(
      'у поста стены заголовка нет — и пустая строка не резервирует место в шапке',
      () {
        final post = WallPost.fromJson({
          'id': 'post-3',
          'author_id': 'user-7',
          'author_name': 'Витя',
          'title': '   ',
          'content': 'Просто пост',
          'likes_count': 0,
          'comments_count': 0,
          'views_count': 2,
          'created_at': '2026-09-21T08:00:00.000Z',
        });
        expect(post.title, isNull);
      },
    );
  });

  group('openQuestForum', () {
    test(
      'обсуждение квеста резолвится по id и заводится первым обращением',
      () async {
        final api = _FakeApi(
          routes: {
            'api/forums/quest/quest-9': () => {
              'forum_id': 'forum-9',
              'slug': 'q-quest-9',
            },
          },
        );
        final ref = await openQuestForum(api, 'quest-9');
        expect(ref.id, 'forum-9');
        expect(ref.slug, 'q-quest-9');
        expect(api.calls, ['api/forums/quest/quest-9']);
      },
    );
  });

  group('Лайк топика', () {
    Future<ForumLobbyNotifier> lobby(_FakeApi api) async {
      SharedPreferences.setMockInitialValues({'user_id': 'me'});
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      return _settled(
        () => container.read(forumLobbyProvider('games').notifier),
        (n) => n.state.isLoading,
      );
    }

    test(
      'сервер ответил «не лайк» — счётчик уходит вниз, а не вверх',
      () async {
        // Строка приходит уже залайканной: тап разлайкает, и ответ бэка обязан
        // перечислить от исходного числа, а не от нашей догадки.
        final server = _Server();
        final notifier = await lobby(
          _FakeApi(
            routes: {
              ...server.asRoutes,
              'POST api/author-walls/posts/post-1/like': () => {'liked': false},
            },
          ),
        );

        final error = await notifier.toggleTopicLike(
          notifier.state.topics.first,
        );

        expect(error, isNull);
        expect(notifier.state.topics.first.isLikedByViewer, isFalse);
        expect(notifier.state.topics.first.likesCount, 2);
      },
    );

    test(
      'сервер подтвердил лайк — плюс один к тому, что показал бэк',
      () async {
        final server = _Server();
        server.topics.first['is_liked_by_viewer'] = false;
        final notifier = await lobby(
          _FakeApi(
            routes: {
              ...server.asRoutes,
              'POST api/author-walls/posts/post-1/like': () => {'liked': true},
            },
          ),
        );

        await notifier.toggleTopicLike(notifier.state.topics.first);

        expect(notifier.state.topics.first.isLikedByViewer, isTrue);
        expect(notifier.state.topics.first.likesCount, 4);
      },
    );

    test('отказ сервера возвращает строку к исходному числу', () async {
      final server = _Server();
      final notifier = await lobby(
        _FakeApi(
          routes: server.asRoutes,
          fail: {'POST api/author-walls/posts/post-1/like'},
        ),
      );

      final error = await notifier.toggleTopicLike(
        notifier.state.topics.first,
      );

      expect(error, isNotNull);
      expect(notifier.state.topics.first.likesCount, 3);
      expect(notifier.state.topics.first.isLikedByViewer, isTrue);
    });
  });

  group('ForumHotTopicsNotifier', () {
    const hotEndpoint = 'api/forums/topics/hot?limit=6';

    Future<ForumHotTopicsNotifier> feed(_FakeApi api) async {
      SharedPreferences.setMockInitialValues({'user_id': 'me'});
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      return _settled(
        () => container.read(forumHotTopicsProvider.notifier),
        (n) => !n.state.loaded,
      );
    }

    Map<String, dynamic> hot({required String id, required String slug}) => {
      ..._topicRow(id: id),
      'forum_slug': slug,
      'forum_name': 'Игры',
    };

    test('строка несёт ещё и сообщество: без него карточке некуда вести', () {
      final item = ForumHotTopic.fromJson(hot(id: 'post-1', slug: 'games'));
      expect(item.topic.id, 'post-1');
      expect(item.forumSlug, 'games');
      expect(item.forumName, 'Игры');
    });

    test('порядок задаёт сервер, клиент его не переставляет', () async {
      final notifier = await feed(
        _FakeApi(
          routes: {
            hotEndpoint: () => {
              'topics': [
                hot(id: 'post-a', slug: 'games'),
                hot(id: 'post-b', slug: 'cats'),
              ],
            },
          },
        ),
      );

      expect(
        notifier.state.topics.map((t) => t.topic.id),
        ['post-a', 'post-b'],
      );
    });

    test('лайк в подмешанной ленте сверяется с ответом сервера', () async {
      final notifier = await feed(
        _FakeApi(
          routes: {
            hotEndpoint: () => {
              'topics': [
                {...hot(id: 'post-a', slug: 'games'), 'is_liked_by_viewer': false},
              ],
            },
            'POST api/author-walls/posts/post-a/like': () => {'liked': true},
          },
        ),
      );

      final error = await notifier.toggleLike(notifier.state.topics.first);

      expect(error, isNull);
      expect(notifier.state.topics.first.topic.likesCount, 4);
      expect(notifier.state.topics.first.topic.isLikedByViewer, isTrue);
    });

    test('упавший запрос оставляет ленту без блока, а не с ошибкой', () async {
      final notifier = await feed(_FakeApi(fail: {hotEndpoint}));

      expect(notifier.state.loaded, isTrue);
      expect(notifier.state.topics, isEmpty);
    });
  });

  group('Лобби: две колонки на широком окне', () {
    // Размер окна задаётся до первого кадра: `LayoutBuilder` решает раскладку
    // по ограничениям, и позже перекачанный тест дал бы вердикт по старой
    // ширине.
    Future<void> open(WidgetTester tester, double width) async {
      SharedPreferences.setMockInitialValues({'user_id': 'me'});
      // Картинка и анимированное оформление в этом тесте не нужны: и то, и
      // другое заводит таймеры, которые остаются висеть после disposal-а.
      final server = _Server();
      final routes = <String, dynamic Function()>{
        ...server.asRoutes,
        'api/forums/games': () => {...server.lobbyRoutes(), 'mods': const []},
        'api/forums/games/posts': () => {
          'topics': [
            {
              ..._topicRow(),
              'media_urls': const <String>[],
              'author_cosmetics': const <String, dynamic>{},
            },
          ],
        },
      };
      tester.view.physicalSize = Size(width * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(_FakeApi(routes: routes)),
          ],
          child: const MaterialApp(home: ForumLobbyScreen(slug: 'games')),
        ),
      );
      // Ни таймеров, ни анимации с задержкой: два запроса и SharedPreferences
      // отрабатывают на микрозадачах.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('правила и шапка уходят вправо, лента остаётся на месте', (
      tester,
    ) async {
      await open(tester, 1400);

      final rules = find.text('Правила');
      expect(rules, findsOneWidget);
      // Колонка отмерена от правого края: 344 px.
      expect(tester.getTopLeft(rules).dx, greaterThan(1400 - 344));
      expect(tester.getTopLeft(find.text('Обо всём игровом')).dx,
          greaterThan(1400 - 344));
      expect(find.text('Что играли на выходных?'), findsOneWidget);
      expect(
        tester.getTopLeft(rules).dx,
        greaterThan(
          tester.getTopRight(find.text('Что играли на выходных?')).dx,
        ),
        reason: 'иначе правила наехали бы на ленту',
      );
    });

    testWidgets('на телефоне колонки нет, а шапка по-прежнему над лентой', (
      tester,
    ) async {
      await open(tester, 420);

      expect(find.text('Правила'), findsNothing);
      expect(find.text('Обо всём игровом'), findsOneWidget);
      expect(
        tester.getRect(find.text('Обо всём игровом')).top,
        lessThan(tester.getRect(find.text('Что играли на выходных?')).top),
      );
    });
  });
}
