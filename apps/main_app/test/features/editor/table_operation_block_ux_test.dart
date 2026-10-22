// Редактор: блок «Данные» — семь операций, у каждой своё назначение и свои
// поля.
//
// Претензия тестера: «операция „Удалить“ по-прежнему имеет три строки вместо
// четырёх, как удалять значения из таблицы?». Ответ движка — отдельная
// операция «Удалить значение» (ей нужно поле «Значение»), а «Удалить» работает
// по ключу/индексу и значения не принимает. Проверяем и проводку (имя в JSON
// файла), и то, что интерфейс реально показывает нужные поля, и что подсказки
// не пустые.

import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/widgets/table_operation_block_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('проводка операции', () {
    test('семь операций переживают запись и чтение', () {
      for (final op in TableOperation.values) {
        final block = TableOperationBlock(
          operation: op,
          tableName: 'лавка',
          path: 'items',
          value: '"меч"',
          targetVariable: 'остаток',
        );
        final json = block.toJson();
        expect(json['operation'], isNotNull, reason: op.name);
        final back = TableOperationBlock.fromJson(json);
        expect(back.operation, op, reason: '${json['operation']}');
        expect(back.tableName, 'лавка');
        expect(back.path, 'items');
        expect(back.targetVariable, 'остаток');
      }
    });

    test('«Удалить значение» пишется как remove_value', () {
      // Имя в файле — контракт с ядром (executor.rs ловит именно "remove_value").
      final json = TableOperationBlock(
        operation: TableOperation.removeValue,
      ).toJson();
      expect(json['operation'], 'remove_value');
      expect(
        TableOperationBlock.fromJson({...json, 'operation': 'remove_value'})
            .operation,
        TableOperation.removeValue,
      );
    });

    test('старые имена не теряются', () {
      expect(tableOperationFromWire('get'), TableOperation.get);
      expect(tableOperationFromWire('remove_value'), TableOperation.removeValue);
      // Запасные варианты, которые встречались в чужих файлах.
      expect(tableOperationFromWire('delete'), TableOperation.remove);
      expect(tableOperationFromWire('unset'), TableOperation.remove);
      expect(tableOperationFromWire(''), isNull);
      expect(tableOperationFromWire(null), isNull);
    });

    test('неизвестная операция не превращается молча в «Получить»', () {
      // Иначе load→save переписал бы блок чужой сборки и потерял его данные.
      final raw = <String, dynamic>{
        'type': 'table_operation',
        'id': 'b1',
        'operation': 'pop_front',
        'tableName': 'лавка',
        'path': 'items',
        'value': '0',
        'targetVariable': 'x',
      };
      final block = VisualScriptBlock.fromJson(raw);
      expect(block, isA<UnknownBlock>());
      expect((block as UnknownBlock).toJson()['operation'], 'pop_front');
    });
  });

  group('подсказки', () {
    test('у каждой операции есть название и внятное описание', () {
      for (final op in TableOperation.values) {
        expect(op.label, isNotEmpty);
        expect(op.description.length, greaterThan(30), reason: op.name);
      }
      // Разница двух «удалений» — ровно то, что спрашивал тестер.
      expect(
        TableOperation.remove.description,
        contains('Удалить значение'),
      );
    });

    test('у каждого показываемого поля есть мини-подсказка', () {
      for (final op in TableOperation.values) {
        expect(op.hintFor('path'), isNotEmpty, reason: '${op.name}.path');
        if (op.needsValue) {
          expect(op.hintFor('value'), isNotEmpty, reason: '${op.name}.value');
        }
        if (op.needsTarget) {
          expect(op.hintFor('target'), isNotEmpty, reason: '${op.name}.target');
        }
      }
    });

    test('поля «Значение» и «В переменную» показаны только там, где нужны', () {
      expect(TableOperation.remove.needsValue, isFalse);
      expect(TableOperation.clear.needsValue, isFalse);
      expect(TableOperation.removeValue.needsValue, isTrue);
      expect(TableOperation.get.needsTarget, isTrue);
      expect(TableOperation.contains.needsTarget, isTrue);
      expect(TableOperation.set.needsTarget, isFalse);
      expect(TableOperation.clear.pathIsOptional, isTrue);
      expect(TableOperation.get.pathIsOptional, isFalse);
    });
  });

  Future<TableOperationBlock> pumpBlock(
    WidgetTester tester,
    TableOperation op,
  ) async {
    final block = TableOperationBlock(
      operation: op,
      tableName: 'лавка',
      path: 'items',
      value: '"меч"',
      targetVariable: 'остаток',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TableOperationBlockWidget(block: block, questId: 'q1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return block;
  }

  testWidgets('у «Удалить» три поля и подсказка, где четвёртое', (
    tester,
  ) async {
    await pumpBlock(tester, TableOperation.remove);

    expect(find.byType(ScriptFieldTile), findsNWidgets(3));
    expect(find.text('Значение'), findsNothing);
    expect(
      find.text('ключ (bread) или элемент с нуля: items[1] — второй'),
      findsOneWidget,
    );
    expect(
      find.textContaining('По значению — см. «Удалить значение»'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('у «Удалить значение» есть поле «Значение»', (tester) async {
    await pumpBlock(tester, TableOperation.removeValue);

    expect(find.byType(ScriptFieldTile), findsNWidgets(4));
    expect(find.text('Значение'), findsOneWidget);
    expect(find.text('какой список: items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('у «Получить» есть приёмник, у «Записать» — нет', (
    tester,
  ) async {
    await pumpBlock(tester, TableOperation.get);
    expect(find.text('В переменную'), findsOneWidget);
    expect(find.text('кладётся в переменную, если ключа нет'), findsOneWidget);

    await pumpBlock(tester, TableOperation.set);
    expect(find.text('В переменную'), findsNothing);
    expect(find.byType(ScriptFieldTile), findsNWidgets(4));
  });

  testWidgets('шит операций влезает в экран и объясняет оба удаления', (
    tester,
  ) async {
    await pumpBlock(tester, TableOperation.remove);

    // Поле «Операция»: заголовок блока тоже показывает «Удалить».
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();

    expect(find.text('Удалить значение'), findsOneWidget);
    expect(find.textContaining('первое совпадение со значением'), findsOneWidget);

    // Семь операций по три строки раньше не влезали в шит телефона: список
    // обязан крутиться до последней операции.
    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('Содержит?'), 200, scrollable: list);
    await tester.pumpAndSettle();
    expect(find.text('Содержит?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
