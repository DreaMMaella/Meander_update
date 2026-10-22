import 'package:canvas_app/core/services/refactoring_service.dart';
import 'package:canvas_app/features/resources/screens/markdown_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('rename таблицы обновляет ссылку {имя["колонка"][N]} в тексте',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: MarkdownEditorScreen(
          initialText: 'A {Тест["B"]1} B {Тест} C {Тест2} D {Теста["A"]1}',
          questId: 'q1',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    RefactoringService.emitRenameEvent(
      const RefactorRenameEvent(
        questId: 'q1',
        oldName: 'Тест',
        newName: 'Новое',
      ),
    );
    await tester.pumpAndSettle();

    final text = tester
        .widget<EditableText>(find.byType(EditableText).first)
        .controller
        .text;
    expect(text, 'A {Новое["B"]1} B {Новое} C {Тест2} D {Теста["A"]1}');

    await tester.pump(const Duration(seconds: 2));
  });
}