import 'package:canvas_app/features/resources/screens/data/table_editor_screen.dart';
import 'package:canvas_app/models/quest_table_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  QuestTable makeTable() => QuestTable(
        name: 'Тест',
        columns: const ['A', 'B'],
        rows: [
          {'A': '1', 'B': 'x'},
          {'A': '2', 'B': 'y'},
        ],
        data: const {'key': 'value'},
      );

  testWidgets('TableEditorScreen builds, selects a cell and edits value',
      (tester) async {
    final table = makeTable();
    QuestTable? savedTable;

    await tester.pumpWidget(MaterialApp(
      home: TableEditorScreen(
        table: table,
        questId: 'smoke',
        onSave: (t) => savedTable = t,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Тест'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);

    await tester.tap(find.text('x'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('B1'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '42');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Применить'));
    await tester.pumpAndSettle();

    expect(find.text('42'), findsNWidgets(2));
    expect(table.rows[0]['B'], 'x');

    await tester.tap(find.byTooltip('Сохранить'));
    await tester.pumpAndSettle();
    expect(savedTable, isNotNull);
    expect(savedTable!.rows[0]['B'], '42');
    expect(savedTable!.rows[1]['B'], 'y');
  });
}