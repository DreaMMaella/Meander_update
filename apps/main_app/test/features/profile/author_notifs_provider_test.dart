import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/providers/author_notifs_provider.dart';

/// Провайдер живёт в не-autoDispose списке сессии (#289): одна неудача на
/// холодном старте отравляла его до конца работы приложения, а шапка профиля
/// читала это состояние внутри `build()`. Проверяем, что состояние остаётся
/// данными и что неудача повторной попыткой лечится.
class _FakeApi extends ApiService {
  _FakeApi({this.failTimes = 0, this.failPost = false});

  int failTimes;
  final bool failPost;
  int getCalls = 0;
  int postCalls = 0;
  List<String>? lastSentExceptions;

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    if (endpoint != 'profiles/author-notifs-settings') return const {};
    getCalls++;
    if (failTimes > 0) {
      failTimes--;
      throw Exception('Unauthorized: {"error":"Token is not valid"}');
    }
    return const {'mode': 'all', 'exceptions': ['u-muted']};
  }

  @override
  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    if (endpoint != 'profiles/author-notifs-settings') return const {'ok': true};
    postCalls++;
    lastSentExceptions = (body?['exceptions'] as List?)?.cast<String>();
    if (failPost) throw Exception('Unauthorized');
    return const {'ok': true};
  }
}

ProviderContainer _container(_FakeApi api) {
  return ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
  ]);
}

void main() {
  test('гостя не отправляем на эндпоинт, состояние остаётся дефолтом', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeApi(failTimes: 99);
    final container = _container(api);
    addTearDown(container.dispose);

    await container.read(authorNotifsSettingsProvider.notifier).retryIfFailed();

    expect(api.getCalls, 0);
    final state = container.read(authorNotifsSettingsProvider);
    expect(state.hasError, isFalse);
    expect(state.valueOrNull!.isMuted('u-any'), isFalse);
  });

  test('сбой не оставляет ошибку без шанса: повторная попытка догружает', () async {
    SharedPreferences.setMockInitialValues({'jwt_token': 't', 'user_id': 'me'});
    // Первая попытка (при создании провайдера) падает, вторая — успешна.
    final api = _FakeApi(failTimes: 1);
    final container = _container(api);
    addTearDown(container.dispose);

    final notifier = container.read(authorNotifsSettingsProvider.notifier);
    await pumpEventQueue();
    expect(container.read(authorNotifsSettingsProvider).hasError, isTrue);

    await notifier.retryIfFailed();
    await pumpEventQueue();

    final state = container.read(authorNotifsSettingsProvider);
    expect(state.hasError, isFalse);
    expect(state.valueOrNull!.isMuted('u-muted'), isTrue);
    expect(api.getCalls, 2);
  });

  test('переключение без соединения откатывается и честно отвечает false', () async {
    SharedPreferences.setMockInitialValues({'jwt_token': 't', 'user_id': 'me'});
    final api = _FakeApi(failPost: true);
    final container = _container(api);
    addTearDown(container.dispose);

    final notifier = container.read(authorNotifsSettingsProvider.notifier);
    // Ждём первую (успешную) загрузку, чтобы toggle стартовал с серверного
    // состояния, а не с дефолта.
    await pumpEventQueue();

    final saved = await notifier.toggleAuthor('u-author');
    await pumpEventQueue();

    expect(saved, isFalse);
    expect(api.postCalls, 1);
    expect(api.lastSentExceptions, contains('u-author'));
    // Откат: список вернулся к серверному, без «u-author».
    final state = container.read(authorNotifsSettingsProvider);
    expect(state.valueOrNull!.isMuted('u-author'), isFalse);
    expect(state.hasError, isFalse);
  });
}
