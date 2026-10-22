// Офлайн-вход в создание квеста (#5, вторая половина).
//
// Жалоба тестера «без интернета нельзя создавать квесты» живёт не в пути
// создания (он локальный — это держит quest_create_offline_test.dart), а в
// точке входа: залогиненный пользователь стартует с «Маркета», который без
// сети падает в MarketErrorBlock. Старый блок знал только код
// SERVER_MAINTENANCE, а таймаут и DNS-обрыв печатал сырым исключением — и
// предлагал одну кнопку «Попробовать снова». То есть офлайн человек упирался
// в глухую стену и читал её как «приложение без интернета не работает».
//
// Здесь держим два инварианта: сетевой сбой распознаётся по-человечески и
// рядом с «Попробовать снова» появляется реальный выход в локальную часть.

import 'dart:io';

import 'package:canvas_app/core/utils/error_text.dart';
import 'package:canvas_app/features/market/widgets/market_widgets.dart';
import 'package:canvas_app/features/quests/screens/my_quests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isConnectionFailure', () {
    test('распознаёт все формы обрыва, чем бы они ни пришли', () {
      // api_service сводит SocketException/ClientException к коду
      // SERVER_MAINTENANCE, но таймаут запроса и DNS проходят как есть.
      for (final error in <Object>[
        Exception('SERVER_MAINTENANCE'),
        const SocketException('Connection failed'),
        Exception(
          'TimeoutException after 0:00:15.000000: Future not completed',
        ),
        const SocketException('Failed host lookup: api.example.org'),
        Exception('ClientException: Connection refused, uri=…'),
        Exception('SocketException: Network is unreachable (OS Error: …)'),
      ]) {
        expect(isConnectionFailure(error), isTrue, reason: '$error');
      }
    });

    test('не выдаёт отказ по правилу и прочий бред за сеть', () {
      // Иначе «Доступ запрещён» или падение парсера показывались бы человеку
      // как «пропал интернет», а кнопка «Мои квесты» была бы обманкой.
      for (final error in <Object>[
        Exception('403 Только автор может это сделать'),
        Exception('Некорректный идентификатор'),
        FormatException('Unexpected character'),
        StateError('no element'),
      ]) {
        expect(isConnectionFailure(error), isFalse, reason: '$error');
      }
    });
  });

  group('MarketErrorBlock офлайн', () {
    late Directory appDir;

    setUpAll(() async {
      appDir = await Directory.systemTemp.createTemp('mnd_offline_market_test');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return appDir.path;
            }
            return null;
          });
    });

    setUp(() => SharedPreferences.setMockInitialValues({}));

    tearDownAll(() async {
      if (appDir.existsSync()) await appDir.delete(recursive: true);
    });

    Future<void> pumpBlock(
      WidgetTester tester,
      Object error, {
      required VoidCallback onRetry,
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MarketErrorBlock(error: error, onRetry: onRetry),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('таймаут без сети — человеческий текст, а не Exception: …', (
      tester,
    ) async {
      var retries = 0;
      await pumpBlock(
        tester,
        Exception(
          'TimeoutException after 0:00:15.000000: Future not completed',
        ),
        onRetry: () => retries++,
      );

      expect(find.textContaining('Нет подключения к серверу'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('работают офлайн'), findsOneWidget);

      await tester.tap(find.text('Попробовать снова'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('офлайн даёт выход в библиотеку, а не только «заново»', (
      tester,
    ) async {
      await pumpBlock(
        tester,
        const SocketException('Failed host lookup: api.example.org'),
        onRetry: () {},
      );

      final library = find.byKey(const Key('market-offline-library'));
      expect(
        library,
        findsOneWidget,
        reason: 'офлайн-выхода в локальную часть нет',
      );

      await tester.tap(library);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MyQuestsScreen), findsOneWidget);
    });

    testWidgets('обычная ошибка сети не выдаёт — без кнопки «Мои квесты»', (
      tester,
    ) async {
      await pumpBlock(
        tester,
        Exception('403 Только автор может это сделать'),
        onRetry: () {},
      );

      expect(find.textContaining('Нет подключения к серверу'), findsNothing);
      expect(
        find.byKey(const Key('market-offline-library')),
        findsNothing,
        reason: 'кнопка «Мои квесты» под обещанием офлайна была бы обманкой',
      );
    });
  });
}
