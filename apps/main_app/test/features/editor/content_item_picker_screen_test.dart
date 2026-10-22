// Пикер элементов контента должен оставаться рабочим на квесте из сотен нод:
// поиск и фильтр по ноде режут список до того, как он доедет до сетки.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/features/editor/providers/node_provider.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/content_item_picker_model.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/content_item_selection_screen.dart';

SavedNode node(String id, String title, List<Map<String, dynamic>> items) =>
    SavedNode(id: id, chapterId: 'c1', title: title, content: {'items': items});

void main() {
  final nodes = <SavedNode>[
    node('n1', 'Лес', [
      {'id': 'i1', 'type': 'image', 'resourcePath': 'res/images/tree.png'},
      {'id': 'i2', 'type': 'text', 'text': 'Двери заперты'},
      {
        'id': 'row',
        'type': 'row',
        'children': [
          {
            'id': 'i3',
            'type': 'image',
            'resourcePath': 'res/images/1790024448511_efa5.png',
          },
        ],
      },
    ]),
    node('n2', 'Подвал', [
      {'id': 'i4', 'type': 'image', 'resourcePath': 'res/images/key.png'},
    ]),
  ];

  Future<void> openPicker(WidgetTester tester, {String? nodeId}) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allQuestNodesProvider.overrideWith((ref, questId) async => nodes),
        ],
        child: MaterialApp(
          home: ContentItemSelectionScreen(
            questId: 'q1',
            nodeId: nodeId,
            allowedTypes: const ['image'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('показывает картинки всех нод, включая вложенные в ряд', (
    tester,
  ) async {
    await openPicker(tester);

    expect(find.text('tree'), findsOneWidget);
    expect(find.text('1790024448511_efa5'), findsOneWidget);
    expect(find.text('key'), findsOneWidget);
    // Текст и ряд — не картинка, их в пикере set_image быть не должно.
    expect(find.text('Двери заперты'), findsNothing);
    expect(find.text('Показано 3'), findsOneWidget);
  });

  testWidgets('поиск по названию ноды оставляет только её картинки', (
    tester,
  ) async {
    await openPicker(tester);

    await tester.enterText(find.byType(TextField), 'подвал');
    await tester.pump();

    expect(find.text('key'), findsOneWidget);
    expect(find.text('tree'), findsNothing);
    expect(find.text('Показано 1'), findsOneWidget);
  });

  testWidgets('чип ноды фильтрует без поиска', (tester) async {
    await openPicker(tester);

    await tester.dragUntilVisible(
      find.text('Подвал · 1'),
      find.byType(SingleChildScrollView).first,
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подвал · 1'));
    await tester.pumpAndSettle();

    expect(find.text('key'), findsOneWidget);
    expect(find.text('tree'), findsNothing);
  });

  testWidgets('с текущей ноды начинается, а не со всего квеста', (
    tester,
  ) async {
    await openPicker(tester, nodeId: 'n2');

    expect(find.text('Показано 1'), findsOneWidget);
    expect(find.text('key'), findsOneWidget);
    expect(find.text('tree'), findsNothing);
    // Выйти на весь квест всё равно можно: скрипт видит картинки из других сцен.
    await tester.tap(find.text('Все ноды · 3'));
    await tester.pumpAndSettle();
    expect(find.text('Показано 3'), findsOneWidget);
  });

  testWidgets('пустой результат предлагается сбросить, а не чинить руками', (
    tester,
  ) async {
    await openPicker(tester);

    await tester.enterText(find.byType(TextField), 'космос');
    await tester.pumpAndSettle();

    expect(find.text('Ничего не подошло'), findsOneWidget);
    await tester.tap(find.text('Сбросить фильтры'));
    await tester.pumpAndSettle();

    expect(find.text('Показано 3'), findsOneWidget);
  });

  testWidgets('выбор возвращает айтем вместе с подписью', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ContentItemChoice? popped;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allQuestNodesProvider.overrideWith((ref, questId) async => nodes),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                popped = await Navigator.push<ContentItemChoice>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ContentItemSelectionScreen(
                      questId: 'q1',
                      allowedTypes: ['image'],
                    ),
                  ),
                );
              },
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1790024448511_efa5'));
    await tester.pumpAndSettle();

    // Блок `set_image` подписывает цель этим, что вернул пикер.
    expect(popped?.item.id, 'i3');
    expect(popped?.location, 'Лес › Ряд');
    expect(popped?.label, '1790024448511_efa5');
  });
}
