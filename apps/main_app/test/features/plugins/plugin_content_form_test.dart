import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/features/editor/widgets/plugin_content_form.dart';
import 'package:canvas_app/features/plugins/models/plugin_content_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('модель типа контента', () {
    test('разбирает JSON Rust-хоста в поля формы', () {
      final type = PluginContentType.fromHostJson({
        'pluginId': 'mnd.examples.lock',
        'type': 'mnd.examples.lock:combinationLock',
        'name': 'Кодовый замок',
        'description': 'Игрок набирает код',
        'icon': 'lock',
        'fields': [
          {
            'key': 'code',
            'label': 'Код',
            'type': 'text',
            'hint': 'Например 1337',
          },
          {
            'key': 'tries',
            'label': 'Попыток',
            'type': 'number',
            'default': 3,
            'min': 1,
            'max': 5,
          },
          {
            'key': 'mode',
            'label': 'Режим',
            'type': 'select',
            'options': ['простой', 'сложный'],
          },
        ],
      });

      expect(type.id, 'mnd.examples.lock:combinationLock');
      expect(type.pluginId, 'mnd.examples.lock');
      expect(type.iconData, isNotNull, reason: 'имя иконки из списка плеера');
      expect(type.defaults, {'tries': 3});
      expect(type.fields.map((field) => field.kind).toList(), [
        PluginFieldKind.text,
        PluginFieldKind.number,
        PluginFieldKind.select,
      ]);
      expect(type.fields[0].hint, 'Например 1337');
      expect(type.fields[1].rangeHint, 'от 1 до 5');
      expect(type.fields[2].isChoice, isTrue);
    });

    test('неизвестный тип поля не роняет форму, пустой select — не список', () {
      final field = PluginContentField.fromHostJson({
        'key': 'weird',
        'label': 'Странное',
        'type': 'duration',
        'options': <String>[],
      });
      expect(field.kind, PluginFieldKind.text);
      expect(field.isChoice, isFalse);
      expect(field.rangeHint, isNull);
    });

    test('акцент плагина стабилен и различает плагины', () {
      PluginContentType type(String pluginId) => PluginContentType.fromHostJson({
        'pluginId': pluginId,
        'type': '$pluginId:lock',
        'name': 'Замок',
      });
      expect(
        type('mnd.examples.lock').accentColor,
        type('mnd.examples.lock').accentColor,
      );
      // `Color.a` — доля покрытия (1.0 = непрозрачный).
      expect(type('mnd.examples.lock').accentColor.a, 1.0,
          reason: 'полупрозрачный акцент не видно на карточке');
      expect(
        type('mnd.examples.shop').accentColor,
        isNot(type('mnd.examples.lock').accentColor),
        reason: 'разные плагины должны различаться',
      );
    });

    test('цвет формы: #RGB, #RRGGBB и мусор', () {
      expect(tryParsePluginColor('#f0a'), const Color(0xffff00aa));
      expect(tryParsePluginColor('80ff0000'), const Color(0x80ff0000));
      expect(tryParsePluginColor('не цвет'), isNull);
      expect(tryParsePluginColor(null), isNull);
    });
  });

  group('форма айтема плагина', () {
    testWidgets('значения по умолчанию уходят в pluginData без правок', (
      tester,
    ) async {
      final form = await _openForm(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ОК'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ОК'));
      await tester.pumpAndSettle();

      expect(await form.result, {
        'code': '',
        'tries': 3,
        'mode': 'простой',
        'loud': true,
      });
    });

    testWidgets('число жмётся к границам манифеста, select и bool помнятся', (
      tester,
    ) async {
      final form = await _openForm(tester);
      await tester.pumpAndSettle();

      await tester.enterText(_field('Код'), '1337');
      await tester.enterText(_field('Попыток'), '12');
      await tester.ensureVisible(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      // Тап по тексту пункта: центр самой строки меню перекрывается
      // списком-вьюпортом, и tap() ругается на промах.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(DropdownMenuItem<String>, 'сложный'),
          matching: find.text('сложный'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('ОК'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ОК'));
      await tester.pumpAndSettle();

      expect(await form.result, {
        'code': '1337',
        'tries': 5,
        'mode': 'сложный',
        'loud': false,
      });
    });

    testWidgets('отмена формы не создаёт айтем', (tester) async {
      final form = await _openForm(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Отмена'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(await form.result, isNull);
    });

    testWidgets('эталонный замок: живой манифест даёт форму со всеми kinds', (
      tester,
    ) async {
      final form = await _openForm(tester, type: _exampleLockType());
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsOneWidget, reason: 'showProgress');
      expect(find.byType(DropdownButton<String>), findsOneWidget, reason: 'mode');
      expect(find.byIcon(Icons.folder_open), findsOneWidget, reason: 'picture');

      await tester.ensureVisible(find.text('ОК'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ОК'));
      await tester.pumpAndSettle();

      // Ключи и значения — контракт с `main.lua` плагина: он читает ровно это
      // из `pluginData`, а дефолты взяты из манифеста.
      expect(await form.result, {
        'code': '1337',
        'title': 'Замок',
        'hint': '',
        'targetNode': '',
        'attempts': 3,
        'mode': 'простой',
        'showProgress': true,
        'picture': '',
      });
    });
  });
}

/// Тип контента из настоящего `plugins/examples/combination-lock/plugin.json`:
/// правка kinds или ключей в манифесте ломает этот тест, а не тихо
/// выродившуюся в текстовое поле форму.
PluginContentType _exampleLockType() {
  const relative = 'plugins/examples/combination-lock/plugin.json';
  var dir = Directory.current.absolute;
  for (var depth = 0; depth < 5; depth++) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) {
      return _lockType(jsonDecode(candidate.readAsStringSync()));
    }
    dir = dir.parent;
  }
  fail('не нашёл $relative от ${Directory.current.path}');
}

PluginContentType _lockType(Map<String, dynamic> manifest) {
  final declared =
      (manifest['contentTypes'] as List).first as Map<String, dynamic>;
  final pluginId = manifest['id'] as String;
  return PluginContentType.fromHostJson({
    'pluginId': pluginId,
    'type': '$pluginId:${declared['id']}',
    'name': declared['name'],
    'description': declared['description'],
    'icon': declared['icon'],
    'fields': declared['fields'],
  });
}

PluginContentType _type() => PluginContentType(
  id: 'mnd.examples.lock:combinationLock',
  name: 'Кодовый замок',
  pluginId: 'mnd.examples.lock',
  description: 'Игрок набирает код на экранной клавиатуре',
  fields: const [
    PluginContentField(name: 'code', label: 'Код', kind: PluginFieldKind.text),
    PluginContentField(
      name: 'tries',
      label: 'Попыток',
      kind: PluginFieldKind.number,
      defaultValue: 3,
      min: 1,
      max: 5,
    ),
    PluginContentField(
      name: 'mode',
      label: 'Режим',
      kind: PluginFieldKind.select,
      defaultValue: 'простой',
      options: ['простой', 'сложный'],
    ),
    PluginContentField(
      name: 'loud',
      label: 'Громко',
      kind: PluginFieldKind.bool,
      defaultValue: true,
    ),
  ],
);

/// Ручка на открытую форму: [result] завершится, когда нажмут ОК или Отмена.
class _Form {
  _Form(this.result);
  final Future<Map<String, dynamic>?> result;
}

/// Открывает форму и возвращает ручку на её результат.
Future<_Form> _openForm(WidgetTester tester, {PluginContentType? type}) async {
  late Future<Map<String, dynamic>?> result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showPluginContentForm(
                context,
                type: type ?? _type(),
                questId: 'q.test',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  return _Form(result);
}

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));
