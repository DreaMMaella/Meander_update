// Пикер пути блока «Данные»: путь — это ключ хранилища скриптов, а не строка
// сетки. Когда ключей нет, пикер показывал пустой список и автор шёл в поле
// писать имя колонки сетки — блок на этом молча промахивался. Теперь пикер
// объясняет, что такое путь, а сетку отдаёт ссылками {т["колонка"][1]}.

import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/table_path_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory appDir;
  final copied = <String>[];
  String? chosen;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    appDir = await Directory.systemTemp.createTemp('mnd_path_picker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? appDir.path
          : null,
    );
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  /// Конфиг пишем до тела теста: `await` dart:io внутри testWidgets попадает
  /// в fake-async зону и не завершается.
  Future<void> writeConfig(String questId, Map<String, dynamic> table) async {
    final dir = Directory('${appDir.path}/quests/$questId');
    await dir.create(recursive: true);
    await File('${dir.path}/config.json').writeAsString(
      jsonEncode({
        'variables': ['золото'],
        'tables': [table],
      }),
    );
  }

  setUp(() async {
    chosen = null;
    copied.clear();
    await writeConfig('q_grid', {
      'name': 'фрукты',
      'columns': ['название', 'цвет'],
      'rows': [
        {'название': 'тыква', 'цвет': 'жёлтый'},
        {'название': 'киви', 'цвет': 'зелёный'},
      ],
      'data': {},
      'folderPath': '/',
    });
    await writeConfig('q_keys', {
      'name': 'фрукты',
      'columns': ['название'],
      'rows': [
        {'название': 'тыква'},
      ],
      'data': {'корзина': ['тыква', 'киви'], 'открыто': true},
      'folderPath': '/',
    });
  });

  Future<void> openPicker(
    WidgetTester tester,
    String questId,
    String table,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                chosen = await pickTablePath(
                  context,
                  questId: questId,
                  tableName: table,
                  operation: TableOperation.set,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // Реальный IO доходит только внутри runAsync.
    await tester.runAsync(() async {
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('пустое хранилище: объясняем путь и показываем сетку ссылками',
      (tester) async {
    await openPicker(tester, 'q_grid', 'фрукты');

    expect(find.textContaining('Путь — это имя'), findsOneWidget);
    expect(find.textContaining('рядов сетки'), findsOneWidget);
    // Ссылка на ячейку — в каноне с [N]: без скобок номер съедается молча.
    // Вторую колонку проверяет только текст: горизонтальный список на 360 px
    // её не вмещает, она за прокруткой.
    expect(find.text('{фрукты["название"][1]}'), findsOneWidget);
    expect(find.textContaining('Сетка — это не путь'), findsOneWidget);
    expect(find.text('{фрукты["название"]1}'), findsNothing);

    await tester.tap(find.text('{фрукты["название"][1]}'));
    await tester.pumpAndSettle();
    expect(copied, ['{фрукты["название"][1]}']);
    // Чип сетки — не выбор пути: пикер не закрывается и путь не возвращает.
    expect(find.text('Путь в «фрукты»'), findsOneWidget);
    expect(chosen, isNull);
  });

  testWidgets('ключи хранилища — это и есть пути, тап возвращает ключ',
      (tester) async {
    await openPicker(tester, 'q_keys', 'фрукты');

    expect(find.text('корзина'), findsOneWidget);
    expect(find.text('открыто'), findsOneWidget);

    await tester.tap(find.text('корзина'));
    await tester.pumpAndSettle();
    expect(chosen, 'корзина');
  });
}
