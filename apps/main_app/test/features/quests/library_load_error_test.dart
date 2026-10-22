// Вкладка «Мои» — первый экран, куда развилка онбординга (#247) сажает новичка
// с намерением «создавать». Если список квестов не собрался, экран печатал
// `'$err'` как есть: «FileSystemException: Cannot open directory, path =
// /data/user/0/… (OS Error: Permission denied, errno = 13)» — и ни кнопки, ни
// объяснения. Сеть при этом ни при чём: квесты лежат в папке приложения, а
// значит этот текст видел и человек без интернета, который прочитал его как
// сломанный Meander.
//
// Здесь держим два инварианта: причина свёрнута в человеческую фразу, а рядом
// есть рабочая «Повторить»; карточка повреждённого квеста тоже не печатает
// префикс класса.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): откатить вызовы — ветку `error:` в
// `_buildQuestsSliver` к `Text('Ошибка загрузки: $err')` и подпись карточки к
// `quest.loadError` — падают все три виджет-теста: «обрыв чтения папки» и
// «отказ по правилу» (нет заголовка «Библиотека не открылась», на экране
// «errno»), «карточка повреждённого квеста» (префикс `Exception:`).

import 'dart:io';

import 'package:canvas_app/features/quests/providers/quest_provider.dart';
import 'package:canvas_app/features/quests/screens/my_quests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpLibrary(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(child);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('причина: библиотека не открылась', () {
    test('дамп dart:io сворачивается в фразу про папку квестов', () {
      final text = libraryLoadErrorText(
        const FileSystemException(
          'Cannot open directory',
          '/data/user/0/com.IILLUMINAT.meadner/app_document/quests',
          OSError('Permission denied', 13),
        ),
      );

      expect(text, contains('папку с квестами'));
      expect(text, isNot(contains('errno')));
      expect(text, isNot(contains('FileSystemException')));
      expect(text, isNot(contains('\n')));
    });

    test('отсутствующий плагин путей — тоже про хранилище, а не трек', () {
      expect(
        libraryLoadErrorText(
          MissingPluginException(
            'No implementation found for method '
            'getApplicationDocumentsDirectory',
          ),
        ),
        contains('папку с квестами'),
      );
    });

    test('прочая ошибка сохраняет суть без префикса класса', () {
      // Формулировка провайдера про HMAC уже человеческая — от неё нужен
      // только снятый префикс `Exception: `.
      expect(
        libraryLoadErrorText(
          Exception('Квест поврежден или модифицирован сторонним лицом'),
        ),
        'Квест поврежден или модифицирован сторонним лицом',
      );
    });
  });

  testWidgets('обрыв чтения папки — проза и кнопка, а не трассировка', (
    WidgetTester tester,
  ) async {
    var runs = 0;
    await pumpLibrary(
      tester,
      ProviderScope(
        overrides: [
          questsProvider.overrideWith((ref) async {
            runs++;
            throw const FileSystemException(
              'Cannot open directory',
              '/data/user/0/com.IILLUMINAT.meadner/app_document/quests',
              OSError('Permission denied', 13),
            );
          }),
        ],
        child: MaterialApp(home: const MyQuestsScreen(isRoot: true)),
      ),
    );

    expect(find.text('Библиотека не открылась'), findsOneWidget);
    expect(find.textContaining('errno'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Ошибка загрузки'), findsNothing);
    expect(runs, 1);

    final retry = find.byKey(const Key('library-retry'));
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    // У _refreshAll есть пауза 200 мс перед автосинком.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(runs, 2, reason: '«Повторить» не перезапустила загрузку списка');
    expect(find.text('Библиотека не открылась'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('отказ по правилу не выдаётся за недоступную папку', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(
      tester,
      ProviderScope(
        overrides: [
          questsProvider.overrideWith(
            (ref) async =>
                throw Exception('403 Только автор может это сделать'),
          ),
        ],
        child: MaterialApp(home: const MyQuestsScreen(isRoot: true)),
      ),
    );

    expect(find.text('Библиотека не открылась'), findsOneWidget);
    expect(find.textContaining('папку с квестами'), findsNothing);
    expect(
      find.textContaining('Только автор может это сделать'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('карточка повреждённого квеста — без префикса Exception:', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(
      tester,
      ProviderScope(
        overrides: [
          questsProvider.overrideWith(
            (ref) async => [
              Quest(
                id: 'q-broken',
                title: 'Ломаный квест',
                isCorrupted: true,
                loadError:
                    'Exception: Квест поврежден или модифицирован '
                    'сторонним лицом (HMAC Error)',
              ),
            ],
          ),
        ],
        child: MaterialApp(home: const MyQuestsScreen(isRoot: true)),
      ),
    );

    expect(find.text('Ломаный квест'), findsWidgets);
    expect(find.textContaining('HMAC Error'), findsOneWidget);
    expect(
      find.textContaining('Exception:'),
      findsNothing,
      reason: 'карточка печатала loadError как есть',
    );

    await tester.pumpWidget(const SizedBox());
  });
}
