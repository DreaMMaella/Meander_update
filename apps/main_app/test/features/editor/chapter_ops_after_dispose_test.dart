// «Мои главы» — экран, который новичок закрывает на ходу (кнопка «Закрыть
// вкладку» в AppBar, закрытие документа во вкладках редактора), а операция над
// главой в этот момент ещё живёт: `_deleteTag` сначала пишет авто-бэкап
// (архивирует всю папку квеста), потом `deleteTag` переписывает nodes.json и
// config.json.
//
// До правки итог долетал до диска, а дальше разбивался о мёртвый экран.
// `ref.invalidate(...)` на снятом State бросает — в debug это StateError
// «This widget has been unmounted, so the State no longer has a context», и
// поскольку `_deleteTag` ничего не ловит, ошибка уходит в error-зону теста.
// В `_duplicateTagAction`, `_editTag` и `_createNewTag` обновление стояло под
// `if (mounted)` — без исключения, но и без толка: канвас и список остаются с
// уже удалённой (или уже скопированной) главой, пока пользователь не откроет
// вкладку заново. Плюс снэкбар «Глава удалена» печатался не глядя: `deleteTag`
// не бросает, а возвращает false, и этот ответ раньше терялся.
//
// Правка — та же, что в срезе H и в `session_service.dart`: контейнер берётся
// до первого await, дальше `context` не нужен вовсе.
//
// Здесь держим: реальный путь удаления через UI (карточка → шит «Удалить» →
// диалог «Удалить главу?»), реальный диск и внешнего слушателя
// `questTagsProvider`, который и обязан узнать о главе без экрана. Остальные
// семь методов тем же приемом проверяются сканом исходника — каждый прячется
// за своим диалогом/пикером, и тащить их в виджет-тест значимо дороже, чем
// держать форму, из-за которой они и падали.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): откатить `tags_screen.dart` к прежнему
// виду — падает виджет-тест (внешний слушатель остаётся с «Вторая глава»:
// толка от `container.invalidate` больше нет) и падает скан (в `_deleteTag`
// нет containerOf, в файле живёт `ref.invalidate`). Снятые с экрана обновления
// проверяются через live-слушателя специально: `questTagsProvider` —
// autoDispose, и без него invalidate нечего обновлять, тест был бы пустым.

import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/features/editor/providers/tag_provider.dart';
import 'package:canvas_app/features/editor/screens/tags_screen.dart';
import 'package:canvas_app/features/editor/widgets/editor_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';

const String _questId = '44444444-4444-4444-8444-444444444444';
const String _keepChapter = 'chapter-keep';
const String _dropChapter = 'chapter-drop';
const String _keepName = 'Первая глава';
const String _dropName = 'Вторая глава';

/// Ноды «Вторая глава» намеренно большие: удаление переписывает nodes.json
/// целиком, а авто-бэкап архивирует папку — окно между тапом и итогом должно
/// быть шире, чем один кадр тест-раннера.
List<Map<String, dynamic>> _fatNodes() {
  final pad = 'х' * 40000;
  return List.generate(12, (i) {
    return {
      'id': 'node-drop-$i',
      'chapterId': _dropChapter,
      'title': 'Узел $i',
      'x': 100.0 + i * 40,
      'y': 200.0,
      'content': {
        'items': [
          {'type': 'text', 'text': pad},
        ],
      },
    };
  });
}

Future<void> _writeQuestFiles() async {
  await FileStorage.writeJsonFile(QuestPaths.config(_questId), {
    'id': _questId,
    'title': 'Ночной квест',
    'startNodeId': 'node-keep',
    'tags': [
      {'id': _keepChapter, 'name': _keepName, 'questId': _questId},
      {'id': _dropChapter, 'name': _dropName, 'questId': _questId},
    ],
    'connections': [
      {'id': 'conn-1', 'fromId': 'node-keep', 'toId': 'node-drop-0'},
    ],
  });

  await FileStorage.writeJsonFile(QuestPaths.nodesLegacy(_questId), {
    'nodes': [
      {
        'id': 'node-keep',
        'chapterId': _keepChapter,
        'title': 'Оплата',
        'x': 80.0,
        'y': 80.0,
        'content': {
          'items': [
            {'type': 'text', 'text': 'Начало'},
          ],
        },
      },
      ..._fatNodes(),
    ],
    'groups': [],
    'comments': [],
  });
}

late Directory appDir;

/// Имена глав прямо с диска, мимо кэша и провайдеров: по ним видно, что
/// удаление действительно ещё в полёте в момент, когда экран снят.
List<String> _chaptersOnDisk() {
  final file = File('${appDir.path}/${QuestPaths.config(_questId)}');
  if (!file.existsSync()) return const [];
  final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (config['tags'] as List<dynamic>? ?? [])
      .map((t) => (t as Map<String, dynamic>)['name'].toString())
      .toList();
}

/// Реальный диск живёт вне fake-часов, поэтому каждый шаг — окно `runAsync`
/// плюс кадр, чтобы слушатели успели перерисоваться.
Future<void> _settle(
  WidgetTester tester,
  bool Function() until, {
  int steps = 120,
  required String what,
}) async {
  for (var i = 0; i < steps; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (until()) return;
  }
  throw StateError('$what: так и не наступило за $steps реальных шагов');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    appDir = await Directory.systemTemp.createTemp('mnd_chapter_dispose');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return appDir.path;
          }
          return null;
        });
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _writeQuestFiles();
  });

  tearDown(() async {
    final quest = Directory('${appDir.path}/quests/$_questId');
    if (quest.existsSync()) await quest.delete(recursive: true);
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  // Скан стоит ПЕРВЫМ и намеренно не трогает диск. Виджет-тест заканчивается,
  // когда записи ещё в полёте, и цепочка FileStorage._writeLocks по этому пути
  // остаётся отравленной до конца изолята: следующий writeJsonFile того же
  // файла уже не резюмируется (честный таймаут, не баг приложения — в нём
  // fake-часов нет). Артефакт harness’а, лечится порядком.
  test('обновления глав в tags_screen идут через container, не через ref', () {
    // Форма, из-за которой всё и падало: после await трогать `ref` нельзя,
    // а `if (mounted)` вокруг invalidate превращает долетевшую операцию в
    // тихое «ничего не обновилось».
    final source = File(
      'lib/features/editor/screens/tags_screen.dart',
    ).readAsStringSync();

    expect(
      'ref.invalidate'.allMatches(source).length,
      0,
      reason: 'ref после dispose бросает — обновлений через него быть не должно',
    );
    expect(
      'ref.unlisten'.allMatches(source).length,
      0,
      reason: 'то же самое: ref живёт только до первого await',
    );
    final grabs = 'ProviderScope.containerOf(context'.allMatches(source).length;
    expect(
      grabs,
      8,
      reason:
          'контейнер должны брать все восемь долгих путей над главами '
          '(переименование и удаление папки, создание, правка, перенос, '
          'дублирование, вставка из шаблона, удаление главы)',
    );

    // Внутри удаления порядка мало — invalidate обязан стоять ДО garde:
    // «если экран жив» оставляет канвас с мёртвой главой.
    final start = source.indexOf('Future<void> _deleteTag(');
    expect(start, isNot(-1), reason: '_deleteTag не найден');
    final body = source.substring(start, source.indexOf('\n  }\n', start));
    expect(body, contains('ProviderScope.containerOf(context'));
    expect(body, contains('container.invalidate(questTagsProvider'));
    expect(
      body.indexOf('container.invalidate(questTagsProvider'),
      lessThan(body.indexOf('if (!mounted) return;')),
      reason: 'толчок провайдеру встал под mounted-гард — без экрана он не сработает',
    );
    // Честный ответ: deleteTag возвращает false, и это «не удалось», а не успех.
    expect(body, contains('final removed = await deleteTag'));
    expect(body, contains('Не удалось удалить главу'));
  });

  testWidgets('закрыть список глав посреди удаления — глава уходит и список узнаёт', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(460, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Экран снимаем с дерева не `pumpWidget` (внутри runAsync он вешает
    // процесс), а флагом. Скоуп остаётся тот же, а внешний Consumer держит
    // autoDispose-провайдер живым — иначе invalidate было бы нечего обновлять.
    final showScreen = ValueNotifier<bool>(true);
    addTearDown(showScreen.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final tags = ref.watch(questTagsProvider(_questId));
                    final names =
                        tags.valueOrNull?.map((t) => t.name).join(',') ??
                        'нет данных';
                    return Text(
                      'list:$names',
                      textDirection: TextDirection.ltr,
                    );
                  },
                ),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: showScreen,
                    builder: (context, show, _) => show
                        ? TagsScreen(questId: _questId)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await _settle(
      tester,
      () => find.text(_dropName).evaluate().isNotEmpty,
      what: 'список глав не отрисовался с диска',
    );
    expect(find.text(_keepName), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'открытие «Моих глав» не должно шуметь',
    );

    // Реальный жест: карточка → «⋮» → «Удалить» → подтверждение.
    final card = find.ancestor(
      of: find.text(_dropName),
      matching: find.byType(EditorListCard),
    );
    expect(card, findsOneWidget);
    await tester.tap(
      find.descendant(of: card, matching: find.byIcon(Icons.more_vert_rounded)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(
      find.ancestor(of: find.text('Удалить'), matching: find.byType(ListTile)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Удалить главу?'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Удалить')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await tester.pump();

    // Громкая предпосылка: в момент, когда экрана ещё нет, удаление ещё НЕ
    // долетело. Иначе тест проверял бы обычный путь, а не жизнь без экрана.
    expect(
      _chaptersOnDisk(),
      containsAll(<String>[_keepName, _dropName]),
      reason:
          'удаление завершилось до dispose — окно операции слишком узкое, '
          'тест ничего не проверяет',
    );

    showScreen.value = false;
    await tester.pump();
    expect(
      find.byType(TagsScreen),
      findsNothing,
      reason: 'экран не снят с дерева — проверки ниже бессмысленны',
    );

    // Операция доживает без экрана: сначала диск, потом внешний слушатель.
    await _settle(
      tester,
      () => _chaptersOnDisk().length == 1,
      what: 'удаление главы не долетело до диска',
    );
    expect(_chaptersOnDisk(), [_keepName]);

    await _settle(
      tester,
      () => find.text('list:$_keepName').evaluate().isNotEmpty,
      what: 'список не узнал об удалённой главе',
    );

    expect(
      tester.takeException(),
      isNull,
      reason:
          'долетевшее удаление не должно трогать ref/context после dispose — '
          'ошибка из несжатого await уходит в error-зону',
    );
  });
}

