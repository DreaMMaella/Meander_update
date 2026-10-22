// Откуда профиль берёт часы. Когда-то для своего профиля использовался только
// локальный счётчик (SharedPreferences этого устройства), и на втором
// компьютере человек выглядел так, будто ни разу не играл, хотя на сервере
// часы лежали. Правило «сервер важнее» живёт в одном месте — здесь оно и
// зафиксировано.

import 'package:canvas_app/core/services/playtime_service.dart';
import 'package:canvas_app/core/utils/playtime_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlaytimeService implements PlaytimeService {
  _FakePlaytimeService({required this.appSeconds, required this.questSeconds});

  final int appSeconds;
  final int questSeconds;

  @override
  Future<int> getTotalAppPlaytime() async => appSeconds;

  @override
  Future<int> getTotalQuestsPlaytime() async => questSeconds;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('PlaytimeFormatter.serverFirst', () {
    test('серверное значение важнее локального', () {
      expect(PlaytimeFormatter.serverFirst(7200, 60), 7200);
    });

    test('пока сервер молчит, показываем часы этого устройства', () {
      expect(PlaytimeFormatter.serverFirst(0, 5400), 5400);
    });

    test('оба нуля — ровно то же, что рисует форматтер', () {
      expect(
        PlaytimeFormatter.format(PlaytimeFormatter.serverFirst(0, 0)),
        '0 мин.',
      );
    });
  });

  group('локальные провайдеры часов', () {
    test('читают через PlaytimeService этого устройства', () async {
      final container = ProviderContainer(
        overrides: [
          playtimeServiceProvider.overrideWithValue(
            _FakePlaytimeService(appSeconds: 3600, questSeconds: 1800),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(localAppPlaytimeProvider.future), 3600);
      expect(await container.read(localQuestPlaytimeProvider.future), 1800);
    });
  });
}
