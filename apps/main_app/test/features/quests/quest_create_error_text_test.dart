// Если папка квестов недоступна, создание проекта — первое, что это покажет:
// новичок вводит название, жмёт «Создать проект» и получает снэкбар
// «Ошибка: FileSystemException: Cannot create directory, path =
// /data/user/0/…/blocked/quests (OS Error: Not a directory, errno = 20)».
// Человек без интернета и без знания Dart читает это как сломанный Meander и
// уходит, а причина — в середине строки, под именем класса и путём.
//
// Держим инвариант: отказ хранилища называется причиной, которую человек может
// проверить (место, разрешения), а не путём и `errno`; прочие причины доходят
// одной строкой без префикса класса.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): вернуть в `_createQuest`
// `Text('Ошибка: $e')` — падают оба теста: в виджет-тесте снэкбар начинает
// печатать `FileSystemException: Creation failed, path = … (OS Error: Not a
// directory, errno = 20)`, в разборе причины — тот же префикс класса.

import 'dart:io';

import 'package:canvas_app/features/quests/screens/create_quest_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUpAll(() async {
    sandbox = await Directory.systemTemp.createTemp('mnd_create_failure_test');
    // «Папка приложения», внутри которой нельзя создать ничего: обычный файл
    // на месте каталога даёт детерминированный отказ dart:io на любой
    // платформе — без root, /proc и chmod.
    File('${sandbox.path}/blocked').writeAsStringSync('');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getTemporaryDirectory') {
            return '${sandbox.path}/blocked';
          }
          return null;
        });
  });

  tearDownAll(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('сбой записи папки — причина, а не дамп класса', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CreateQuestScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextFormField).first, 'Ночной поезд');
    await tester.pump();

    // Реальный event loop: запись в недоступную папку — настоящий I/O.
    await tester.runAsync(() async {
      await tester.tap(find.text('Создать проект'));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final snack = find.byType(SnackBar);
    expect(snack, findsOneWidget, reason: 'отказ не показался человеку вовсе');
    final content = tester.widget<SnackBar>(snack).content;
    final shown = (content as Text).data!;

    expect(shown, startsWith('Ошибка: '));
    expect(shown, contains('не может записать проект'));
    expect(
      shown,
      isNot(contains('FileSystemException')),
      reason: 'экран печатает toString ошибки целиком',
    );
    expect(shown, isNot(contains('errno')));
    expect(shown, isNot(contains('\n')));

    await tester.pumpWidget(const SizedBox());
  });

  group('разбор причины', () {
    test('отказ каталога — фраза про место и разрешения', () {
      expect(
        questCreationErrorText(
          const FileSystemException(
            'Creation failed',
            '/data/user/0/com.IILLUMINAT.meadner/app_document/quests',
            OSError('Not a directory', 20),
          ),
        ),
        allOf(
          contains('не может записать проект'),
          isNot(contains('errno')),
          isNot(contains('\n')),
        ),
      );
    });

    test('прочая причина доходит одной строкой без префикса класса', () {
      expect(
        questCreationErrorText(Exception('Название проекта уже занято')),
        'Название проекта уже занято',
      );
    });
  });
}
