import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Шапка блока: заголовок и чип со значением делят одну ширину.
/// Раньше между чипом и крестиком стоял Spacer — три гибких dziecka
/// делили ряд на трети, и длинное условие обрезалось на двух словах,
/// даже когда заголовок короткий и места полно.
Future<void> _pumpHeader(
  WidgetTester tester, {
  required String expression,
  double width = 360,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark)),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ScriptBlockShell(
              category: BlockCategory.control,
              title: 'Если / Иначе',
              icon: Icons.call_split_rounded,
              onDelete: () {},
              headerSuffix: ShellValueChip(
                value: expression,
                placeholder: 'условие…',
                onTap: () {},
              ),
              child: const ScriptFieldTile(label: 'Переменная', value: 'x'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('длинное значение в шапке доходит до правого края, а не до трети', (
    tester,
  ) async {
    await _pumpHeader(
      tester,
      expression: 'flag_door_open && (key_count >= 3 || used_key == "rusty")',
    );

    final chip = tester.getRect(find.byType(ShellValueChip));
    // Правый край ряда шапки — сама карточка: крестика удаления в шапке больше
    // нет (удаление живёт в меню блока), так что чип обязан доходить до края.
    final cardRight = tester.getRect(find.byType(ScriptBlockShell)).right;
    final title = tester.getRect(find.text('Если / Иначе'));

    // Мёртвый зазор между чипом и краем карточки = обрезанное значение.
    expect(
      cardRight - chip.right,
      lessThan(12),
      reason: 'ряд шапки оставляет пустую треть вместо значения',
    );
    // Чип обязан занимать больше трети гибкой зоны — с Spacer'ом в ряду он
    // был заперт ровно в одной трети, независимо от длины заголовка.
    final span = cardRight - title.left;
    expect(
      chip.width,
      greaterThan(span / 3 + 20),
      reason: 'чип сжат в треть ряда',
    );
  });

  testWidgets('короткое значение не растягивается на весь ряд', (tester) async {
    await _pumpHeader(tester, expression: 'a > 1');

    final chip = tester.getRect(find.byType(ShellValueChip));
    expect(
      chip.width,
      lessThan(120),
      reason: 'чип обязан обнимать значение, а не тянуться на всю шапку',
    );
  });

  testWidgets('пустое значение показывает плейсхолдер', (tester) async {
    await _pumpHeader(tester, expression: '   ');
    expect(find.text('условие…'), findsOneWidget);
  });

  testWidgets('шапка не переполняется на узком телефоне', (tester) async {
    await _pumpHeader(
      tester,
      expression: 'aVeryLongFlagName && anotherVeryLongFlagName == 42',
      width: 300,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('чип принимает тап, а не пробрасывает его блоку', (tester) async {
    var chipTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ScriptBlockShell(
                category: BlockCategory.control,
                title: 'Если / Иначе',
                onDelete: () {},
                headerSuffix: ShellValueChip(
                  value: 'x > 1',
                  placeholder: 'условие…',
                  onTap: () => chipTaps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ShellValueChip));
    await tester.pump();
    expect(chipTaps, 1);
  });
}
