// Создание квеста — локальная операция, и она должна такой остаться (#5).
//
// Жалоба тестера: «без интернета нельзя создавать квесты». Пути создания её
// не подтверждают: `CreateQuestScreen` пишет папку и config.json через
// FileStorage/QuestStore и ни разу не обращается к серверу. Тест держит это
// как инвариант, а не как наблюдение: API-провайдер в скоупе подменён
// броском, поэтому заедь на путь запрос или проверка сессии — создание не
// завершится и тест упадёт.
//
// Что действительно ломается без сети — это точка входа: залогиненный
// пользователь стартует с вкладки «Маркет», которая офлайн падает в
// MarketErrorBlock с одной кнопкой «Попробовать снова». Держит это
// market_offline_entry_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/quests/screens/create_quest_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/quest_descriptor.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Провайдер, который существует только чтобы упасть: любое `ref.read` с
/// экрана создания означает, что путь стал сетевым.
final _noApi = apiServiceProvider.overrideWith(
  (ref) => throw const SocketException('сети нет'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;

  setUpAll(() async {
    appDir = await Directory.systemTemp.createTemp('mnd_offline_create_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return appDir.path;
          }
          return null;
        });
  });

  setUp(() {
    // Пустые prefs = гость: ни user_id, ни токена.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    final quests = Directory('${appDir.path}/quests');
    if (quests.existsSync()) await quests.delete(recursive: true);
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  testWidgets('гость без сети создаёт квест', (tester) async {
    Quest? created;
    // Узкий высокий экран: на дефолтных 800×600 ListView не собирает поля.
    await tester.binding.setSurfaceSize(const Size(420, 1200));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [_noApi],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('open'),
                onPressed: () async {
                  created = await Navigator.push<Quest>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateQuestScreen(),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.enterText(find.byType(TextFormField).first, 'Ночной поезд');
    await tester.pump();

    // Создание пишет файлы через dart:io, а его будущие в fake-async-зоне
    // виджета-теста не завершаются никогда. runAsync возвращает настоящий
    // event loop — иначе тест «висит на пустом месте», а не падает.
    await tester.runAsync(() async {
      await tester.tap(find.text('Создать проект'));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Ошибка'), findsNothing);
    expect(created, isNotNull, reason: 'экран не вернул созданный квест');
    expect(created!.title, 'Ночной поезд');

    final configFile = File('${appDir.path}/${QuestPaths.config(created!.id)}');
    expect(configFile.existsSync(), isTrue, reason: 'config.json не записан');
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    expect(config['title'], 'Ночной поезд');
    // Гость — без автора: создание не требует сессии и не пишет чужой id.
    expect(config.containsKey('authorId'), isFalse);
  });

  test('заглушка API действительно бросает — иначе первый тест пустой', () {
    // Негативный контроль: если override ничего не делает, инвариант не
    // держится ни на чём.
    final scope = ProviderContainer(overrides: [_noApi]);
    expect(
      () => scope.read(apiServiceProvider),
      throwsA(isA<SocketException>()),
    );
  });

  test('на пути создания нет обращения к серверу', () {
    // Создание не должно однажды «починиться» сетевым запросом.
    final source = File(
      'lib/features/quests/screens/create_quest_screen.dart',
    ).readAsStringSync();
    for (final banned in const [
      'apiServiceProvider',
      'package:dio',
      'package:http',
      'HttpClient',
      'connectivity',
      'isLoggedIn',
      'authToken',
    ]) {
      expect(
        source,
        isNot(contains(banned)),
        reason: 'создание квеста тянет сеть или сессию через $banned',
      );
    }
  });
}
