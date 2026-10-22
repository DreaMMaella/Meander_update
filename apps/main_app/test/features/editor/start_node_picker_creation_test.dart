// Выбор стартовой ноды в свежем квесте не должен быть тупиком.
//
// Экран `NodeSelectionScreen` открывают из двух состояний: «перейти /
// привязать», где есть нода отсчёта, и «выбрать стартовую», где её нет.
// Долгое время кнопка создания была привязана к первой ситуации
// (`currentNodeId != null`), поэтому новичок, который нажал «Выбрать» на
// карточке «Стартовая нода не выбрана» пустого квеста, попадал в список без
// единого элемента и без кнопки — и должен был догадаться, что ноды создаются
// в редакторе.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено тремя мутациями): убрать
// `|| widget.allowCreate` из `_canCreate` — падают оба теста пустого квеста с
// `allowCreate: true`; снять признак `_searchQuery.isEmpty` у кнопки — падает
// тест про поиск без результата; выставить `allowCreate = true` дефолтом
// конструктора — падает тест, что пикер, которому аргумент не передавали,
// создания не предлагает.
//
// Не покрыто: сам тап по кнопке — он пишет ноду на диск через `saveNodes`, а
// здесь переопределены только провайдеры чтения.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/features/editor/providers/node_provider.dart';
import 'package:canvas_app/features/editor/providers/tag_provider.dart';
import 'package:canvas_app/features/editor/screens/node_selection_screen.dart';

Future<void> openPicker(
  WidgetTester tester, {
  required List<SavedNode> nodes,
  String? currentNodeId,
  bool? allowCreate,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // `allowCreate == null` — аргумент не передаём вовсе: иначе дефолт
  // конструктора никто не проверяет, а именно он решает, не начнут ли
  // пикеры «перейти к ноде» предлагать создание.
  final screen = allowCreate == null
      ? NodeSelectionScreen(questId: 'q1', currentNodeId: currentNodeId)
      : NodeSelectionScreen(
          questId: 'q1',
          currentNodeId: currentNodeId,
          allowCreate: allowCreate,
        );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allQuestNodesProvider.overrideWith((ref, questId) async => nodes),
        questTagsProvider.overrideWith((ref, questId) async => []),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('пустой квест: выбор стартовой ноды предлагает создать её', (
    tester,
  ) async {
    await openPicker(tester, nodes: [], allowCreate: true);

    expect(find.text('В этом квесте пока нет нод'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Создать ноду'), findsOneWidget);
  });

  testWidgets('создание разрешено и висячей кнопкой, как в редакторе', (
    tester,
  ) async {
    await openPicker(tester, nodes: [], allowCreate: true);

    expect(
      find.widgetWithText(FloatingActionButton, 'Создать новую'),
      findsOneWidget,
    );
  });

  testWidgets('пикер «перейти к ноде» с пустым списком тоже даёт выход', (
    tester,
  ) async {
    await openPicker(tester, nodes: [], currentNodeId: 'n1');

    // Текущая нода есть — показывать её же нельзя, поэтому список пуст.
    // Формулировка про «другие» на месте, и создание не запрещаем: это
    // прежний сценарий «создать ноду, куда ведёт кнопка».
    expect(find.text('В этом квесте пока нет других нод'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Создать ноду'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Создать новую'),
      findsOneWidget,
    );
  });

  testWidgets('пикер без текущей ноды и без allowCreate остаётся закрытым', (
    tester,
  ) async {
    await openPicker(tester, nodes: []);

    expect(find.widgetWithText(FilledButton, 'Создать ноду'), findsNothing);
    expect(
      find.widgetWithText(FloatingActionButton, 'Создать новую'),
      findsNothing,
    );
  });

  testWidgets(
    'поиск без результата не превращается в приглашение создать ноду',
    (tester) async {
      await openPicker(
        tester,
        nodes: [
          SavedNode(
            id: 'n2',
            chapterId: 'c1',
            title: 'Прибытие',
            content: const {'items': []},
          ),
        ],
        allowCreate: true,
      );

      await tester.enterText(find.byType(TextField), 'нет-такой');
      await tester.pumpAndSettle();

      expect(find.text('Попробуйте изменить запрос'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Создать ноду'), findsNothing);
    },
  );
}
