// Полный флоу кнопки «Вставить переменную» в markdown-редакторе: пикер,
// вкладки «Переменные»/«Таблицы», вставка {имя} и ссылки на ячейку
// {имя["колонка"][N]} в текст.

import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/features/resources/screens/markdown_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory appDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    appDir = await Directory.systemTemp.createTemp('mnd_picker_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return appDir.path;
      }
      return null;
    });
  });

  tearDownAll(() async {
    if (appDir.existsSync()) {
      await appDir.delete(recursive: true);
    }
  });

  Map<String, dynamic> configWith({
    List<dynamic>? variables,
    List<dynamic>? tables,
  }) => {
    'variables': variables ?? ['золото'],
    'tables': tables ?? [
      {
        'name': 'Тест',
        'columns': ['A', 'B'],
        'rows': [
          {'A': '1', 'B': 'x'},
          {'A': '2', 'B': 'y'},
        ],
        'data': {},
        'folderPath': '/',
      },
    ],
  };

  /// Конфиги пишутся до тел тестов: `await` реального dart:io внутри
  /// testWidgets попадает в fake-async зону и не завершается — тест висит до
  /// 10-минутного таймаута раннера.
  Future<void> writeConfig(
    String questId,
    Map<String, dynamic> config,
  ) async {
    final file = File('${appDir.path}/quests/$questId/config.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(config));
  }

  setUp(() async {
    for (final id in ['q1', 'q2', 'q3']) {
      await writeConfig(id, configWith());
    }
  });

  /// Пикер читает квест с диска — настоящий IO доходит только внутри
  /// runAsync; анимацию роута гасит обычный settle.
  Future<void> settleWithIo(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    // Гасим уход старого контента (AnimatedSwitcher/TabBarView): пока он
    // идёт, список перекрывает IgnorePointer'ом и тапы не доходят.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  String editorText(WidgetTester tester) => tester
      .widget<EditableText>(find.byType(EditableText).first)
      .controller
      .text;

  Future<void> openEditor(WidgetTester tester, String questId) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: MarkdownEditorScreen(initialText: '', questId: questId),
      ),
    ));
    await settleWithIo(tester);
  }

  testWidgets('кнопка «Вставить переменную»: вкладка «Таблицы» показывает таблицы',
      (tester) async {
    await openEditor(tester, 'q1');

    await tester.tap(find.byTooltip('Вставить переменную'));
    await settleWithIo(tester);

    await tester.tap(find.widgetWithText(Tab, 'Переменные'));
    await settleWithIo(tester);
    expect(find.text('золото'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Таблицы'));
    await settleWithIo(tester);
    expect(find.text('Тест'), findsOneWidget);
    // Дальше — тот же переход в выбор ячейки, что и в тесте с
    // «Данные из таблицы»: тап по строке списка после смены вкладки в
    // тестовой среде уходит в ещё досвигающийся overlay, поэтому он
    // проверен там.

    // Сбрасываем дебаунс автосохранения, чтобы он не остался на tearDown.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('кнопка «Вставить переменную»: переменная → {имя} в текст',
      (tester) async {
    await openEditor(tester, 'q2');

    await tester.tap(find.byTooltip('Вставить переменную'));
    await settleWithIo(tester);

    await tester.tap(find.text('золото'));
    await settleWithIo(tester);

    expect(editorText(tester), '{золото}');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('кнопка «Данные из таблицы» тоже возвращает ссылку на ячейку',
      (tester) async {
    await openEditor(tester, 'q3');

    await tester.tap(find.byTooltip('Данные из таблицы'));
    await settleWithIo(tester);

    await tester.tap(find.text('Тест'));
    await settleWithIo(tester);
    expect(find.text('Выбор ячейки'), findsOneWidget);

    await tester.tap(find.text('y'));
    await settleWithIo(tester);

    expect(editorText(tester), '{Тест["B"][2]}');

    await tester.pump(const Duration(seconds: 2));
  });
}
