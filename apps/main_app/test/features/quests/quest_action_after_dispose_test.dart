// Создание и удаление квеста — операции не мгновенные: `CreateQuestScreen`
// пишет папки и `config.json` через FileStorage/QuestStore, `_deleteQuest`
// стирает всю папку `quests/<id>`. Всё это время экран можно закрыть:
// «Новый квест» снимается кнопкой «Закрыть» в AppBar, библиотека живёт в табах.
//
// Для новичка это кончалось тупиком. Долетевший до конца результат трогал
// `ref` уже мёртвого экрана, и на этом летит StateError («This widget has been
// unmounted, so the State no longer has a context»). В `_createQuest` бросок
// ловился нижним catch — то есть обновление списка просто не происходило:
// квест лег на диск, а «Мои» остались без карточки. В `_deleteQuest` хуже:
// catch звал `_showSnack`, а тот — `Theme.of(context)` и
// `ScaffoldMessenger.of(context)` на мёртвом context; исключение из catch
// наружу уже нечем ловить.
//
// Правка — брать контейнер до первого await (тот же приём в
// `session_service.dart`: «контейнер берётся до первого await — дальше
// context не нужен вовсе»), тогда обновление списка доживает до конца даже
// без экрана.
//
// Здесь держим: механизм (первый тест), реальный экран создания (второй) и
// форму `_deleteQuest` (третий — скан исходника: весь UI-путь удаления,
// карточка + попап-меню + диалог с чекбоксом, в виджет-тест честно не
// влезает, так что он остаётся незакрытым).
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): откатить оба экрана к прежнему виду —
// падают второй тест (`loads` остаётся 1: библиотека не узнала о квесте) и
// третий (в `_deleteQuest` нет containerOf, есть ref.invalidate). Первый тест
// от правки в экранах не зависит: он и есть то, от чего guard’ы защищают, —
// без него второй тест держался бы на ничем.

import 'dart:async';
import 'dart:io';

import 'package:canvas_app/features/quests/providers/quest_provider.dart';
import 'package:canvas_app/features/quests/screens/create_quest_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _probeBuilds = 0;

/// Считает пересборки: по нему видно, жив ли контейнер после смерти экрана.
final _probeProvider = Provider<int>((ref) => ++_probeBuilds);

final _counterProvider = StateProvider.autoDispose<int>((ref) => 0);

/// Экран, который по заказу тестера трогает `ref` после того, как его сняли с
/// дерева. Ровно то, что делали `_createQuest` и `_deleteQuest` до правки.
class _LeakyScreen extends ConsumerStatefulWidget {
  const _LeakyScreen();

  @override
  ConsumerState<_LeakyScreen> createState() => _LeakyScreenState();
}

class _LeakyScreenState extends ConsumerState<_LeakyScreen> {
  final Completer<void> _gate = Completer<void>();
  ProviderContainer? _grabbed;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  /// Как в экране: контейнер берётся, пока `context` жив.
  void grabContainer() =>
      _grabbed = ProviderScope.containerOf(context, listen: false);

  void release() => _gate.complete();

  /// Ничего не ловим: в экране тоже не ловили.
  Future<void> touchRefAfterUnmount() async {
    await _gate.future;
    ref.invalidate(_counterProvider);
  }

  int readProbe() => _grabbed!.read(_probeProvider);

  void invalidateProbe() => _grabbed!.invalidate(_probeProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;
  var appDirGate = Completer<String>();

  setUpAll(() async {
    appDir = await Directory.systemTemp.createTemp('mnd_dispose_slice_test');
  });

  setUp(() {
    // Первый вызов FileStorage.getAppDirectory запоминается на весь изолят,
    // поэтому на нём и паркуем создание квеста: handler отдаёт путь, только
    // когда тест сам его разблокирует. Иначе запись долетает раньше, чем
    // экран снят с дерева, и проверка стала бы пустой.
    appDirGate = Completer<String>();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return await appDirGate.future;
          }
          return null;
        });
    // Гость: ни user_id, ни токена — создание обязано работать офлайн.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (!appDirGate.isCompleted) appDirGate.complete(appDir.path);
    final quests = Directory('${appDir.path}/quests');
    if (quests.existsSync()) await quests.delete(recursive: true);
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  /// Есть ли уже записанный config хоть у одного квеста.
  bool configWritten() {
    final quests = Directory('${appDir.path}/quests');
    if (!quests.existsSync()) return false;
    return quests.listSync().whereType<Directory>().any(
      (d) => File('${d.path}/config.json').existsSync(),
    );
  }

  testWidgets('после dispose ref бросает, а взятый заранее container — нет', (
    tester,
  ) async {
    // Экран снимаем с дерева не `pumpWidget` (внутри runAsync он вешает
    // процесс), а флагом: провайдер-скоуп при этом остаётся тот же.
    final showLeaky = ValueNotifier<bool>(true);
    addTearDown(showLeaky.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showLeaky,
              builder: (context, show, _) =>
                  show ? const _LeakyScreen() : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    final state = tester.state<_LeakyScreenState>(find.byType(_LeakyScreen));
    state.grabContainer();

    // Операция висит на gate; экран снимаем с дерева, потом отпускаем.
    final inFlight = state.touchRefAfterUnmount();
    showLeaky.value = false;
    await tester.pump();
    expect(state.mounted, isFalse, reason: 'иначе тест проверяет не dispose');
    state.release();

    Object? thrown;
    try {
      await inFlight;
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isNotNull, reason: 'иначе guard’ы не от чего защищать');
    // Сам бросок — debug-проверка `State.context`: «This widget has been
    // unmounted, so the State no longer has a context». Она стоит раньше
    // собственного текста riverpod про «ref after the widget was disposed»,
    // поэтому в экранах ловить надо именно её.
    expect('$thrown', contains('unmounted'));

    // Тот же шаг через контейнер, взятый пока экран жил: он экран переживает
    // и по-прежнему обновляется — на этом держится правка.
    final before = state.readProbe();
    state.invalidateProbe();
    expect(
      state.readProbe(),
      isNot(before),
      reason: 'container после dispose не обновляется',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('закрыть создание посреди записи — библиотека всё равно узнаёт', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var loads = 0;
    final openCreate = ValueNotifier<bool>(false);
    addTearDown(openCreate.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          questsProvider.overrideWith((ref) async {
            loads++;
            return const <Never>[];
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) => Text(
                    'quests=${ref.watch(questsProvider).valueOrNull?.length ?? -1}',
                    textDirection: TextDirection.ltr,
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: openCreate,
                    builder: (context, show, _) => show
                        ? const CreateQuestScreen()
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    openCreate.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.enterText(find.byType(TextFormField).first, 'Ночной поезд');
    await tester.pump();
    expect(loads, 1);

    await tester.runAsync(() async {
      await tester.tap(find.text('Создать проект'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    expect(
      configWritten(),
      isFalse,
      reason: 'запись долетела до закрытия экрана — проверка была бы пустой',
    );

    // То самое «Закрыть» в AppBar: экрана нет, а создание ещё в полёте.
    openCreate.value = false;
    await tester.pump();
    appDirGate.complete(appDir.path);

    await tester.runAsync(() async {
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'долетевшее создание не должно трогать ref/context после dispose',
    );
    expect(
      loads,
      2,
      reason:
          'библиотека не узнала о квесте: обновление списка не дожило до '
          'конца операции, когда экрана уже не было',
    );
    expect(
      configWritten(),
      isTrue,
      reason: 'сам квест обязан создаться, даже если экран уже закрыт',
    );
  });

  test('долгий путь удаления обновляет список не через ref', () {
    // Скан исходника, а не виджет-тест: `_deleteQuest` живёт за карточкой,
    // попап-меню и диалогом с чекбоксом. Проверяем форму, потому что именно
    // она и есть причина падения: `ref` после dispose бросает, бросок ловит
    // catch, а catch на мёртвом context роняет уже навечно.
    final source = File(
      'lib/features/quests/screens/my_quests_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _deleteQuest(');
    expect(start, isNot(-1), reason: '_deleteQuest не найден');
    final body = source.substring(start, source.indexOf('\n  }\n', start));

    expect(body, contains('ProviderScope.containerOf(context'));
    expect(body, contains('container.invalidate(questsProvider)'));
    expect(
      body,
      isNot(contains('ref.invalidate')),
      reason: 'после dispose этот вызов бросает — список не обновится',
    );
    expect(
      body,
      isNot(contains('ref.read')),
      reason: 'аналогично: best-effort удаление из облака живёт на ref',
    );
  });
}
