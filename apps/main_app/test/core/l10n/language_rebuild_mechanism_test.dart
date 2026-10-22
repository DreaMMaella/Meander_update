import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Голый механизм, без `L10n`: строка зависит от глобального «языка», ровно
/// как в `tr()`. Два вопроса, на которые отвечает этот файл, определяют всю
/// архитектуру переключения языка:
///
/// 1. Перерисовывается ли не-const дитя, когда пересобирается предок, — да,
///    и доезжает этот каскад до содержимого надстроенного маршрута. Поэтому
///    достаточно одного подписчика в `App` (`_AppState` смотрит на
///    `appLanguageProvider`), а экранам не нужен отдельный mixin.
/// 2. Застывает ли const-дитя — да: Flutter сравнивает детей по идентичности
///    и пропускает перерисовку. Отсюда гард «виджет с tr() не создают
///    const-экземпляром» в `l10n_guard_test.dart`.
///
/// Счётчик перерисовок листа и текст на экране — два независимых свидетельства
/// одного и того же факта, поэтому тест переживает изменение верстки.
String _language = 'ru';

String _tr(String ru) => _language == 'ru' ? ru : ru.toUpperCase();

bool _useConst = true;
int _leafBuilds = 0;

class Leaf extends StatelessWidget {
  const Leaf({super.key});

  @override
  Widget build(BuildContext context) {
    _leafBuilds++;
    return Text(_tr('сохранить'));
  }
}

class Screen extends StatefulWidget {
  const Screen({super.key});

  @override
  State<Screen> createState() => ScreenState();
}

class ScreenState extends State<Screen> {
  /// Публичный вход для теста: так ведёт себя `LanguageRebuild` — экран сам
  /// перерисовывает себя по извещению о смене языка.
  void repaintForLanguage() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Column(children: [_useConst ? const Leaf() : Leaf()]));
  }
}

/// Как лист попадает в дерево: `const Leaf()` или `Leaf()`.
void _place({required bool asConst}) {
  _useConst = asConst;
}

Future<void> _pumpHome(WidgetTester tester, GlobalKey<ScreenState> key) async {
  await tester.pumpWidget(MaterialApp(home: Screen(key: key)));
  await tester.pump();
}

Future<void> _pumpRoute(
  WidgetTester tester,
  GlobalKey<NavigatorState> navKey,
  GlobalKey<ScreenState> key,
) async {
  await _pumpRoot(tester, navKey);
  navKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => Screen(key: key)),
  );
  await tester.pumpAndSettle();
}

/// Новый экземпляр MaterialApp поверх того же навигатора: пересобирается
/// корень, маршрут остаётся тем же.
Future<void> _pumpRoot(
  WidgetTester tester,
  GlobalKey<NavigatorState> navKey,
) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('корень')),
    ),
  );
}

String _onScreen(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byType(Leaf), matching: find.byType(Text)),
    )
    .data!;

void main() {
  setUp(() {
    _language = 'ru';
    _leafBuilds = 0;
  });

  tearDown(() {
    _language = 'ru';
  });

  testWidgets('не-const лист перерисовывается вместе с экраном',
      (tester) async {
    final key = GlobalKey<ScreenState>();
    _place(asConst: false);
    await _pumpHome(tester, key);
    expect(_onScreen(tester), 'сохранить');

    _leafBuilds = 0;
    _language = 'en';
    // Так делает смена языка: `App` пересобирается, экран тоже, лист — следом.
    key.currentState!.repaintForLanguage();
    await tester.pump();

    expect(_leafBuilds, 1);
    expect(_onScreen(tester), 'СОХРАНИТЬ');
  });

  testWidgets('const лист остаётся с залитым языком', (tester) async {
    final key = GlobalKey<ScreenState>();
    _place(asConst: true);
    await _pumpHome(tester, key);
    expect(_onScreen(tester), 'сохранить');

    _leafBuilds = 0;
    _language = 'en';
    key.currentState!.repaintForLanguage();
    await tester.pump();

    // Экран пересобрался, а лист — нет: тот же канонизированный экземпляр.
    expect(_leafBuilds, 0);
    expect(_onScreen(tester), 'сохранить');
  });

  testWidgets('каскад доезжает в надстроенный маршрут', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final key = GlobalKey<ScreenState>();
    _place(asConst: false);
    await _pumpRoute(tester, navKey, key);
    expect(_onScreen(tester), 'сохранить');

    _leafBuilds = 0;
    _language = 'en';
    // Пересобираем только корень: до маршрута никто setState не звал.
    await _pumpRoot(tester, navKey);
    await tester.pumpAndSettle();

    expect(_leafBuilds, greaterThan(0));
    expect(_onScreen(tester), 'СОХРАНИТЬ');
  });

  testWidgets('const в маршруте не перерисовывается при пересборке корня',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final key = GlobalKey<ScreenState>();
    _place(asConst: true);
    await _pumpRoute(tester, navKey, key);
    expect(_onScreen(tester), 'сохранить');

    _leafBuilds = 0;
    _language = 'en';
    await _pumpRoot(tester, navKey);
    await tester.pumpAndSettle();

    expect(_leafBuilds, 0);
    expect(_onScreen(tester), 'сохранить');
  });
}
