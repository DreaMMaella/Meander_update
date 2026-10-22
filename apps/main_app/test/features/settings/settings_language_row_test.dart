import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/l10n/l10n_provider.dart';
import 'package:canvas_app/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Язык интерфейса выбирается в «Настройках» и обязан примениться на месте:
// человек не должен искать кнопку «перезапустить». Механизм тот же, что и у
// корня приложения (`_AppState` смотрит на `appLanguageProvider`), поэтому
// тест держит настоящий экран и настоящий провайдер — меняет язык жестом,
// а не вызовом `L10n.setCurrent` в обход UI.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ: убери `ref.watch(appLanguageProvider)` из build
// `SettingsScreen` (строка 685) — падает «переключение языка переводит экран
// без перезапуска»: подпись строки и заголовки останутся русскими.
Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(const {});
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: SettingsScreen())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // `L10n` — глобальный синглтон: без возврата к исходному языку этот файл
  // отравил бы соседние тесты английскими строками.
  tearDown(() => L10n.setCurrent(L10n.byCode(kSourceLanguageCode)));

  testWidgets('язык выбирается в разделе «Внешний вид»', (tester) async {
    await _pumpSettings(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Язык интерфейса'), findsOneWidget);
    // Текущий язык показан самоназванием: по-русски — «Русский».
    expect(find.text('Русский'), findsOneWidget);
  });

  testWidgets('переключение языка переводит экран без перезапуска', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Язык интерфейса'));
    await tester.pumpAndSettle();
    // Шит выбора: оба языка видно, текущий помечен.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Текущий язык'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    // Тот же элемент, тот же экземпляр экрана — без Navigator.pop, без
    // пересоздания MaterialApp.
    expect(find.text('Interface language'), findsOneWidget);
    expect(find.text('Язык интерфейса'), findsNothing);
    expect(find.text('Appearance theme'), findsOneWidget);
    // Подпись строки показывает уже выбранный язык.
    expect(find.text('English'), findsWidgets);
    // И человек получает подтверждение.
    expect(find.text('Interface language: English'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppLanguageNotifier.prefsKey), 'en');
  });

  testWidgets('обратный выбор возвращает русский', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Язык интерфейса'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Interface language'), findsOneWidget);

    await tester.tap(find.text('Interface language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();

    expect(find.text('Язык интерфейса'), findsOneWidget);
    expect(find.text('Interface language'), findsNothing);
    expect(L10n.current.code, kSourceLanguageCode);
  });
}
