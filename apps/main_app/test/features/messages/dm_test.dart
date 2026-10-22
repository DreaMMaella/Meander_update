// Личка: клиент рисует человека ровно так, как его собрал сервер. Глаз по
// одному скриншоту этого не заметит, поэтому зафиксировано то, где расхождение
// видно только по поведению: у ленты диалогов и у списка блокировок один и тот
// же человек приходит в разных колонках, а бейдж не должен считать заглушённые
// переписки. Плюс кнопка отправки: отказ сервера обязан оставлять её живой.

import 'dart:async';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/core/services/socket_service.dart';
import 'package:canvas_app/features/messages/models/dm_models.dart';
import 'package:canvas_app/features/messages/providers/dm_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi({
    Map<String, dynamic Function()>? routes,
    Set<String> fail = const {},
    dynamic postResult,
  }) : _routes = routes ?? const {},
       _fail = fail,
       postResult = postResult ?? const {};

  final Map<String, dynamic Function()> _routes;
  final Set<String> _fail;
  final List<String> calls = [];
  final List<(String, Map<String, dynamic>?)> posts = [];

  /// Тело ответа на POST. `null` — как настоящий `ApiService` на 204.
  dynamic postResult;

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    calls.add(endpoint);
    if (_fail.contains(endpoint)) {
      throw Exception('Exception: SERVER_MAINTENANCE');
    }
    final route = _routes[endpoint];
    if (route == null) throw Exception('неизвестный эндпоинт $endpoint');
    return route();
  }

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    posts.add((endpoint, body));
    if (_fail.contains(endpoint)) {
      throw Exception('Exception: SERVER_MAINTENANCE');
    }
    return postResult;
  }

  @override
  Future<dynamic> delete(String endpoint, {Map<String, dynamic>? body}) async {
    calls.add('DELETE $endpoint');
  }
}

Map<String, dynamic> _thread({
  String id = 'thread-1',
  String peerId = 'peer-1',
  String name = 'Аня',
  String? lastBody = 'привет',
  String? lastSenderId = 'peer-1',
  bool muted = false,
  int unread = 0,
}) => {
  'thread_id': id,
  'peer_id': peerId,
  'peer_name': name,
  'peer_role': 'user',
  'last_body': lastBody,
  'last_sender_id': lastSenderId,
  'muted': muted,
  'unread': unread,
  'last_message_at': '2026-09-20T10:00:00.000Z',
};

/// Первые [eagerResponses] ответов отдаются сразу, всё остальное висит до
/// `release`/`failWith`. Так ловится продолжение загрузки после того, как
/// провайдер уже умер: экран закрыли, а ответ всё равно приходит.
class _PendingApi extends ApiService {
  _PendingApi(this.eagerResponses);

  final List<dynamic> eagerResponses;
  final Completer<dynamic> _held = Completer<dynamic>();
  int _served = 0;

  @override
  Future<dynamic> get(String endpoint, {Map<String, String>? queryParams}) {
    if (endpoint == 'api/messages/system') {
      return Future<dynamic>.value(const {});
    }
    if (_served < eagerResponses.length) {
      return Future<dynamic>.value(eagerResponses[_served++]);
    }
    return _held.future;
  }

  void release(dynamic value) => _held.complete(value);

  void failWith(Object error) => _held.completeError(error);
}

void main() {
  group('DmPeer', () {
    test('лента диалогов отдаёт колонки с префиксом peer_', () {
      final peer = DmPeer.fromJson(_thread());
      expect(peer.id, 'peer-1');
      expect(peer.name, 'Аня');
      expect(peer.role, 'user');
      expect(peer.lastSeenAt, isNull);
    });

    test('список блокировок отдаёт того же человека без префикса', () {
      final peer = DmPeer.fromJson({
        'id': 'peer-9',
        'full_name': 'Витя',
        'avatar_url': 'https://cdn/a.png',
        'cosmetics': {'avatar_frame': 'prism_ring'},
        'role': 'moderator',
        'last_seen_at': '2026-09-20T10:00:00.000Z',
      });
      expect(peer.id, 'peer-9');
      expect(peer.name, 'Витя');
      expect(peer.avatarUrl, 'https://cdn/a.png');
      expect(peer.equipped.avatarFrame, 'prism_ring');
      expect(peer.isStaff, isTrue);
      // Тот же момент, но в местных часах: DateTime считает равными только
      // значения в одном поясе, а нам для «был(а) в сети» нужен местный.
      expect(
        peer.lastSeenAt!.toUtc(),
        DateTime.parse('2026-09-20T10:00:00.000Z'),
      );
    });

    test('аккаунт команды опознаётся по id, а не по имени', () {
      expect(DmPeer(id: kSystemUserId, name: 'Что-то там').isSystem, isTrue);
      expect(DmPeer(id: 'peer-1', name: 'Meander').isSystem, isFalse);
    });
  });

  group('DmThread', () {
    test('превью моей последней реплики помечено «Вы:»', () {
      final thread = DmThread.fromJson(
        _thread(lastBody: 'я зайду вечером', lastSenderId: 'me'),
      );
      expect(thread.previewFor('me'), 'Вы: я зайду вечером');
      expect(thread.previewFor('peer-1'), 'я зайду вечером');
    });

    test('пустая переписка не выглядит сломанной', () {
      final thread = DmThread.fromJson(
        _thread(lastBody: null, lastSenderId: null, peerId: kSystemUserId),
      );
      expect(thread.isSystem, isTrue);
      expect(thread.preview, contains('новости Meander'));
      expect(thread.previewFor('me'), isNotEmpty);
    });
  });

  group('DmThreadsNotifier', () {
    Future<DmThreadsNotifier> openList(_FakeApi api, {String me = 'me'}) async {
      SharedPreferences.setMockInitialValues({'user_id': me});
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      // Конструктор уже запустил загрузку — ждать надо именно её: второй
      // `load()` из теста дописал бы состояние поверх локальных правок.
      final notifier = container.read(dmThreadsProvider.notifier);
      for (var i = 0; i < 50 && notifier.state.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      return notifier;
    }

    test(
      'системный чат запрашивается до ленты, чтобы вкладка не была пустой',
      () async {
        final api = _FakeApi(
          routes: {
            'api/messages/system': () => {'thread_id': 'sys'},
            'api/messages/threads': () => {
              'threads': [
                _thread(id: 'sys', peerId: kSystemUserId, name: 'Meander'),
                _thread(),
              ],
            },
          },
        );
        final notifier = await openList(api);

        expect(api.calls.first, 'api/messages/system');
        expect(notifier.state.threads.map((t) => t.threadId), [
          'sys',
          'thread-1',
        ]);
        expect(notifier.state.threads.first.isSystem, isTrue);
      },
    );

    test('отказ системного чата не блокирует ленту', () async {
      final api = _FakeApi(
        fail: {'api/messages/system'},
        routes: {
          'api/messages/threads': () => {
            'threads': [_thread()],
          },
        },
      );
      final notifier = await openList(api);

      expect(notifier.state.error, isNull);
      expect(notifier.state.threads.length, 1);
    });

    test('бейдж не считает заглушённые переписки', () async {
      final api = _FakeApi(
        routes: {
          'api/messages/system': () => {'thread_id': 'sys'},
          'api/messages/threads': () => {
            'threads': [
              _thread(unread: 3),
              _thread(id: 'thread-2', peerId: 'peer-2', muted: true, unread: 7),
            ],
          },
        },
      );
      final notifier = await openList(api);

      expect(notifier.state.unreadTotal, 3);
      // Заглушить — значит снять и счётчик: человек явно попросил не шуметь.
      await notifier.mute('thread-1', true);
      expect(notifier.state.unreadTotal, 0);
      expect(api.posts.first.$1, 'api/messages/threads/thread-1/mute');
    });

    test('скрытый диалог уходит из ленты у того, кто нажал', () async {
      final api = _FakeApi(
        routes: {
          'api/messages/system': () => {'thread_id': 'sys'},
          'api/messages/threads': () => {
            'threads': [_thread()],
          },
        },
      );
      final notifier = await openList(api);
      await notifier.hide('thread-1');

      expect(notifier.state.threads, isEmpty);
    });
  });

  group('DmChatNotifier', () {
    Map<String, dynamic> message({
      required String id,
      required String body,
      required String senderId,
    }) => {
      'id': id,
      'thread_id': 'thread-1',
      'sender_id': senderId,
      'body': body,
      'kind': 'text',
      'created_at': '2026-09-20T10:00:00.000Z',
    };

    /// Ответы сервера для окна переписки: шапка диалога, история, лента для
    /// бейджа (её трогает и `send`, и отметка о прочтении).
    Map<String, dynamic Function()> chatRoutes() => {
      'api/messages/threads/peer/peer-1': () => _thread(),
      'api/messages/threads/thread-1': () => {
        'messages': [
          message(id: 'm-0', body: 'привет', senderId: 'peer-1'),
        ],
        'has_more': false,
      },
      'api/messages/system': () => {'thread_id': 'sys'},
      'api/messages/threads': () => {
        'threads': [_thread(unread: 2)],
      },
    };

    /// Дожидается, пока состояние перестанет быть «в полёте».
    Future<void> settle(bool Function() pending) async {
      for (var i = 0; i < 50 && pending(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    /// `send` перечитывает ленту без `await`: фоновый ответ надо догнать до
    /// tear-down'а, иначе dispose контейнера превратит его в ошибку теста.
    Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 5));

    /// Контейнер возвращаем вместе с нотифайером: половина смысла окна чата
    /// видна только в ленте переписок — по погасшему бейджу.
    ///
    /// Ленту поднимаем заранее и ждём её до конца: в приложении окно открывается
    /// поверх живой вкладки «Чаты», а параллельная первая загрузка лентой бы
    /// перетёрла локальную отметку о прочтении.
    Future<(DmChatNotifier, ProviderContainer)> openChat(
      _FakeApi api, {
      String peerId = 'peer-1',
    }) async {
      SharedPreferences.setMockInitialValues({'user_id': 'me'});
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final threads = container.read(dmThreadsProvider.notifier);
      await settle(() => threads.state.threads.isEmpty);

      final notifier = container.read(dmChatProvider(peerId).notifier);
      await settle(
        () => notifier.state.isLoading || notifier.state.messages.isEmpty,
      );
      return (notifier, container);
    }

    /// В тесте соединения нет, поэтому payload идёт через тех же слушателей,
    /// которых поднимает настоящий `dm_message`: проверяется путь целиком.
    void deliver({
      String id = 'm-9',
      String senderId = 'peer-1',
      String body = 'пока',
    }) {
      SocketService().emitDmMessageForTest({
        'thread_id': 'thread-1',
        'message': message(id: id, body: body, senderId: senderId),
      });
    }

    /// Больше дебаунса (`_readDebounce` = 400 мс): таймер точно сработал.
    Future<void> pastDebounce() =>
        Future<void>.delayed(const Duration(milliseconds: 500));

    test('история гасит непрочитанное в ленте', () async {
      final api = _FakeApi(routes: chatRoutes());
      final (notifier, container) = await openChat(api);

      expect(notifier.state.error, isNull);
      expect(notifier.state.peer?.name, 'Аня');
      expect(notifier.state.messages.map((m) => m.body), ['привет']);
      expect(
        container.read(dmThreadsProvider).unreadTotal,
        0,
        reason: 'окно показало переписку — бейдж обязан погаснуть',
      );
    });

    test('входящее в открытом окне отмечает прочитанное на сервере', () async {
      // Без этого POST штамп `last_read_at` стоит со времени последнего входа:
      // человек читает, а собеседник и бейдж на вкладке считают иначе.
      final api = _FakeApi(routes: chatRoutes());
      final (notifier, container) = await openChat(api);
      notifier.setViewed(true);

      deliver();
      expect(
        container.read(dmThreadsProvider).unreadTotal,
        0,
        reason: 'счётчик гаснем сразу, не дожидаясь сети',
      );
      expect(api.posts, isEmpty);

      await pastDebounce();
      expect(
        api.posts.map((p) => p.$1).toList(),
        ['api/messages/threads/thread-1/read'],
      );
    });

    test('волна входящих — один запрос, а не по одному на сообщение', () async {
      final api = _FakeApi(routes: chatRoutes());
      final (notifier, _) = await openChat(api);
      notifier.setViewed(true);

      deliver(id: 'm-1');
      deliver(id: 'm-2');
      deliver(id: 'm-3');
      await pastDebounce();

      expect(notifier.state.messages, hasLength(4));
      expect(
        api.posts.where((p) => p.$1.endsWith('/read')),
        hasLength(1),
      );
    });

    test('своё сообщение не шлёт отметку', () async {
      final api = _FakeApi(routes: chatRoutes());
      final (notifier, _) = await openChat(api);
      notifier.setViewed(true);

      deliver(senderId: 'me');
      await pastDebounce();

      expect(api.posts, isEmpty);
    });

    test('в закрытом окне входящее не отмечается прочитанным', () async {
      // Провайдер живёт до выхода из аккаунта, а экран — нет. Отмечать
      // пришедшее в фоне означало бы съедать счётчик, которого человек не видел.
      final api = _FakeApi(routes: chatRoutes());
      final (notifier, container) = await openChat(api);
      notifier.setViewed(true);
      notifier.setViewed(false);

      deliver();
      await pastDebounce();

      expect(api.posts, isEmpty);
      expect(container.read(dmThreadsProvider).unreadTotal, 1);
    });

    test('уход из окна дошлёт отметку, а не потеряет её', () async {
      final api = _FakeApi(routes: chatRoutes());
      final (notifier, _) = await openChat(api);
      notifier.setViewed(true);

      deliver();
      notifier.setViewed(false);
      await pastDebounce();

      expect(
        api.posts.where((p) => p.$1.endsWith('/read')),
        hasLength(1),
        reason: 'флэш при уходе + отменённый таймер: ровно один запрос',
      );
    });

    test('отказ отметки не рвёт окно и не поднимает ошибку', () async {
      final api = _FakeApi(
        routes: chatRoutes(),
        fail: {'api/messages/threads/thread-1/read'},
      );
      final (notifier, container) = await openChat(api);
      notifier.setViewed(true);

      deliver();
      await pastDebounce();

      expect(api.posts, isNotEmpty);
      expect(notifier.state.error, isNull);
      expect(notifier.state.messages, hasLength(2));
      expect(container.read(dmThreadsProvider).unreadTotal, 0);
    });

    test('отказ отправки не выключает кнопку, и повтор работает', () async {
      // ApiService.post возвращает null на пустом теле (204). До фикса из
      // этой ветки выходили с isSending=true: кнопка гасла до перезахода.
      final api = _FakeApi(routes: chatRoutes(), postResult: null);
      final (notifier, _) = await openChat(api);

      expect(await notifier.send('ок'), isFalse);
      expect(notifier.state.isSending, isFalse);
      expect(notifier.state.sendError, isNotNull);
      expect(notifier.state.messages.map((m) => m.body), ['привет']);

      // И вторая попытка реально уходит на сервер, а не съедается флагом.
      api.postResult = {
        'message': message(id: 'm-1', body: 'ок', senderId: 'me'),
      };
      expect(await notifier.send('ок'), isTrue);
      expect(notifier.state.messages.map((m) => m.body), ['привет', 'ок']);
      expect(notifier.state.sendError, isNull);
      expect(api.posts.length, 2);
      await flush();
    });

    test('из служебного чата не пишут', () async {
      final api = _FakeApi(
        routes: {
          ...chatRoutes(),
          'api/messages/threads/peer/${kSystemUserId}': () => _thread(
            peerId: kSystemUserId,
            name: 'Meander',
          ),
        },
      );
      final (notifier, _) = await openChat(api, peerId: kSystemUserId);

      expect(notifier.state.isSystem, isTrue);
      expect(await notifier.send('привет'), isFalse);
      expect(api.posts, isEmpty);
      expect(notifier.state.isSending, isFalse);
    });
  });

  group('DmPrivacy', () {
    test('неизвестный режим откатывается к «Все»', () {
      expect(DmPrivacy.fromJson({'mode': 'только_друг'}).mode, 'everyone');
      expect(DmPrivacy.fromJson({'mode': 'nobody'}).mode, 'nobody');
    });

    test('пороги приходят строкой из формы и читаются числами', () {
      final privacy = DmPrivacy.fromJson({
        'mode': 'standing',
        'min_playtime_hours': '12',
        'min_account_age_days': 3,
      });
      expect(privacy.minPlaytimeHours, 12);
      expect(privacy.minAccountAgeDays, 3);
    });
  });

  group('Ответ сервера после закрытия экрана', () {
    // Человек заходит во вкладку «Чаты» и тут же уходит. Нотифайер умер, а
    // `load()` всё ещё исполняется: запись в `state` бросает StateError, его
    // ловит собственный catch той же загрузки — и на экран ложится
    // «Не удалось загрузить переписки», хотя сервер ответил успешно.
    //
    // Причина живёт только в CrashLogService, а он пишет через debugPrint —
    // поэтому тест смотрит сюда: иначе не отличить «тихо проигнорировали» от
    // «сожгли ошибку и показали её человеку».
    List<String> captureLog() {
      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        lines.add(message ?? '');
      };
      addTearDown(() => debugPrint = previous);
      return lines;
    }

    ProviderContainer openContainer(_PendingApi api) {
      SharedPreferences.setMockInitialValues({'user_id': 'me'});
      return ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
    }

    /// Дожидается конца загрузки и возвращает то, чем она завершилась.
    Future<Object?> outcome(Future<void> inFlight) async {
      try {
        await inFlight;
      } catch (e) {
        return e;
      }
      return null;
    }

    test('успешный ответ не превращается в ошибку ленты', () async {
      final log = captureLog();
      final api = _PendingApi([const {'threads': []}]);
      final container = openContainer(api);
      final notifier = container.read(dmThreadsProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final inFlight = notifier.load();
      // Загрузка должна успеть встать на await ответа: иначе completeError
      // прилетает в future без слушателя, и это отдельная незаперченная ошибка.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      container.dispose();
      expect(notifier.mounted, isFalse);
      api.release({'threads': [_thread()]});

      await outcome(inFlight);
      expect(
        log.where((line) => line.contains('лента переписок')),
        isEmpty,
        reason: 'экран показал бы «Не удалось загрузить переписки» '
            'при удачном ответе сервера',
      );
    });

    test('ошибка ответа не пишется в мёртвый провайдер', () async {
      final api = _PendingApi([const {'threads': []}]);
      final container = openContainer(api);
      final notifier = container.read(dmThreadsProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final inFlight = notifier.load();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      container.dispose();
      api.failWith(Exception('Exception: SERVER_MAINTENANCE'));

      expect(
        await outcome(inFlight),
        isNull,
        reason: 'из catch нельзя писать в уже закрытый экран — StateError '
            'внутри catch стал бы незаперченной ошибкой загрузки',
      );
    });

    test('окно переписки молчит, когда ответили после закрытия', () async {
      final log = captureLog();
      final api = _PendingApi(const []);
      final container = openContainer(api);
      container.read(dmChatProvider('peer-1').notifier);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      container.dispose();
      api.release(const {'thread_id': 'thread-1', 'messages': []});
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(
        log.where((line) => line.contains('переписка не загрузилась')),
        isEmpty,
        reason: 'у `_load` нет шанса поймать ошибку извне: её сожрёт её же catch',
      );
    });
  });
}
