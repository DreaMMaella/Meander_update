// Палитра блоков («Выберите действие») — последнее место, где автор выбирает
// блок «Данные», не зная, что тот трогает только ключи хранилища скриптов.
// Здесь живёт контракт этих подсказок.

import 'package:canvas_app/features/editor/screens/visual_script_editor/action_picker_screen.dart';
import 'package:canvas_app/shared/script_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('под категорией «Данные» видно, чем она оперирует',
      (tester) async {
    await tester.pumpWidget(_wrap(const BlockCategoryHint(catKey: 'data')));

    expect(find.textContaining("лавка['ключ']"), findsOneWidget);
    expect(
      find.textContaining('Ряды сетки он не трогает'),
      findsOneWidget,
      reason: 'без этой строки «Данные» выглядит редактором сетки',
    );
  });

  testWidgets('у категории без подсказки ничего не рисуется', (tester) async {
    await tester.pumpWidget(_wrap(const BlockCategoryHint(catKey: 'audio')));

    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
  });

  test('ключи подсказок на плитках — настоящие типы блоков', () {
    // Ключи сверяем с реестром: переименуют тип в BlockTypes — подсказка
    // молча перестанет находить блок, и тест это поймает.
    expect(kBlockTileHints, contains(BlockTypes.tableOperation));
    expect(kBlockTileHints, contains(BlockTypes.forEach));
    expect(kBlockTileHints, contains(BlockTypes.assignVariable));
    for (final key in kBlockTileHints.keys) {
      expect(key, matches(RegExp(r'^[a-z_]+$')), reason: 'имя типа из ядра');
    }
  });

  test('подсказка «Данные» объясняет оба удаления и пустой путь', () {
    final hint = kBlockTileHints[BlockTypes.tableOperation]!;

    expect(hint, contains('Удалить значение'));
    expect(hint, contains('Путь'));
    expect(hint, contains('хранилищ'));
  });

  test('в categories и на плитках текст не расходится', () {
    // Автор читает и то и другое за один тап: «сетка» не должна появиться там,
    // где блок к сетке не прикасается.
    expect(kBlockCategoryHints['data'], contains('не трогает'));
    expect(kBlockTileHints[BlockTypes.tableOperation], contains('не меняются'));
    expect(kBlockCategoryHints['flow'], contains('рядам сетки'));
  });
}
