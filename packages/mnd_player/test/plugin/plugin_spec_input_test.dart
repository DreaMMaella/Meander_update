// Рендерер поля ввода: плагин объявляет `input`, клиент рисует TextField, а
// набранный текст уходит в Lua-функцию. FFI здесь не нужен — проверяется
// ровно то, что видит игрок.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/widgets/plugin_spec_view.dart';

void main() {
  List<Object?> calls = [];

  Map<String, dynamic> _inputSpec({Object? args = 'item-1'}) => {
    'type': 'input',
    'placeholder': 'код',
    'args': args,
    'onChange': 'typing',
    'onSubmit': 'submit',
  };

  Future<void> pump(
    WidgetTester tester,
    Map<String, dynamic> spec, {
    Map<String, dynamic> vars = const {},
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PluginSpecView(
          spec: spec,
          vars: vars,
          onHandler: (handler, argument) => calls.add({handler: argument}),
        ),
      ),
    ),
  );

  setUp(() => calls = []);

  testWidgets('поле рисруется и живёт своими колбэками', (tester) async {
    await pump(tester, _inputSpec());
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('код'), findsOneWidget, reason: 'placeholder');

    await tester.enterText(find.byType(TextField), '4');
    expect(calls.last, {'typing': {'args': 'item-1', 'value': '4'}});

    await tester.enterText(find.byType(TextField), '42');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(calls.last, {'submit': {'args': 'item-1', 'value': '42'}});
  });

  testWidgets('`args`-объект сливается со значением поля', (tester) async {
    await pump(tester, _inputSpec(args: {'field': 'pin'}));
    await tester.enterText(find.byType(TextField), '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(calls.last, {
      'submit': {'field': 'pin', 'value': '7'},
    });
  });

  testWidgets('value — привязка к переменной квеста', (tester) async {
    await pump(
      tester,
      _inputSpec()..['value'] = '{typed}',
      vars: {'typed': '1337'},
    );
    expect(find.text('1337'), findsOneWidget);
  });

  testWidgets('пока игрок печатает, перерисовка не перетирает поле', (
    tester,
  ) async {
    await pump(tester, _inputSpec()..['value'] = '{typed}');
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '42');

    // Плагин зеркалит ввод в переменную и перерисовывает карточку: значение
    // спеки отстаёт от курсора, и догонять его нельзя.
    await pump(
      tester,
      _inputSpec()..['value'] = '{typed}',
      vars: {'typed': '4'},
    );
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '42');
  });

  testWidgets('скрытый и длинный режимы', (tester) async {
    await pump(tester, _inputSpec()..['password'] = true);
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);

    await pump(tester, _inputSpec()..['multiline'] = true);
    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 3);
  });
}
