// Экспорт квеста в HTML терял обводку текста: processItem отдавал плееру
// только id/type/text, и страница, на которую автор выкладывает квест,
// показывала голый текст там, где в приложении — контур. Проверяем, что
// обводка доезжает до `quest-data`, а печать стиля живёт в JS-скелете.
//
// Негативный контроль (проверено мутациями, каждая роняет ровно свой тест):
// без строки проекции в кейсе 'text' падают 1, 3 и 4; если писать ключ всегда
// — падает 2 (он и есть инвариант «нет обводки — нет ключа»); без clamp и без
// rgba — падает 3; без пропуска центрального offset — падает 1; без
// присваивания div.style.textShadow — падает 4.
import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/core/services/quest_book_models.dart';
import 'package:canvas_app/core/services/quest_html_builder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _questId = '33333333-3333-4333-8333-333333333333';

/// Кисненно-зелёная обводка (заведомо не белый текст страницы) и красная
/// с альфой 0.5.
const int _lime = 0xFF00FF00;
const int _halfRed = 0x80FF0000;

Future<Map<String, dynamic>> _questData(String html) async {
  final start = html.indexOf(
    '<script id="quest-data" type="application/json">',
  );
  expect(
    start,
    greaterThan(-1),
    reason: 'в экспорте нет блока с данными квеста',
  );
  const open = '<script id="quest-data" type="application/json">'.length;
  final end = html.indexOf('</script>', start + open);
  return jsonDecode(html.substring(start + open, end)) as Map<String, dynamic>;
}

Map<String, dynamic> _item(
  Map<String, dynamic> quest,
  String nodeId,
  String itemId,
) {
  final items = (quest['nodes']![nodeId]!['items'] as List).cast<Map>();
  return items.firstWhere((m) => m['id'] == itemId).cast<String, dynamic>();
}

/// Строит экспорт вокруг одного текста (или ряда с текстом внутри) и
/// возвращает спроецированный айтем вместе со всем HTML.
Future<(Map<String, dynamic>, String)> _exportItem(
  Map<String, dynamic> item, {
  bool wrapInRow = false,
}) async {
  final node = <String, dynamic>{
    'id': 'n1',
    'chapterId': 'ch1',
    'title': 'Нода 1',
    'content': {
      'items': [
        if (wrapInRow)
          {
            'id': 'row1',
            'type': 'row',
            'children': [item],
          }
        else
          item,
      ],
    },
  };
  final book = QuestBook(
    id: _questId,
    title: 'Обводка',
    author: null,
    description: null,
    startNodeId: 'n1',
    nodesById: {'n1': node},
    chapters: [
      QuestChapter(id: 'ch1', name: 'Глава 1', nodes: [node]),
    ],
    previewBytes: null,
    previewMime: null,
    customFontFileName: null,
    customFontBytes: null,
  );
  final html = await QuestHtmlBuilder.build(book);
  final quest = await _questData(html);
  return (_item(quest, 'n1', wrapInRow ? 'row1' : item['id']! as String), html);
}

void main() {
  late Directory appDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    appDir = await Directory.systemTemp.createTemp('mnd_html_outline_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return appDir.path;
          }
          return null;
        });
  });

  tearDownAll(() async {
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  test('текст с обводкой уносит её в экспорт восемью смещениями', () async {
    final (item, _) = await _exportItem({
      'id': 't1',
      'type': 'text',
      'text': 'Здравствуй, мир',
      'textOutlineColor': _lime,
    });

    final shadow = item['textShadow'] as String;
    // Восемь копий глифов, центрального offset(0,0) быть не должно — иначе
    // тень съест само начертание.
    expect(shadow.split(', '), hasLength(8));
    expect(shadow.split('#00FF00'), hasLength(9));
    expect(shadow, isNot(contains('0.0px 0.0px')));
    // Дефолтная толщина 2 px → контур наполовину снаружи, т.е. offset 1 px.
    expect(shadow, contains('-1.0px -1.0px 0 #00FF00'));
  });

  test('без обводки экспорт не плодит ключ', () async {
    final (item, _) = await _exportItem({
      'id': 't1',
      'type': 'text',
      'text': 'Обычный текст',
    });
    expect(item.containsKey('textShadow'), isFalse);
  });

  test('толщина и альфа цвета доезжают до страницы', () async {
    final (thick, _) = await _exportItem({
      'id': 't1',
      'type': 'text',
      'text': 'Жирный контур',
      'textOutlineColor': _lime,
      'textOutlineWidth': 5.0,
    });
    expect(thick['textShadow'], contains('2.5px'));

    // Значение вне диапазона модель не ловит на чтении — экспорту это тоже
    // запрещено: 50 px контур в браузере съел бы текст.
    final (clamped, _) = await _exportItem({
      'id': 't2',
      'type': 'text',
      'text': 'Слишком жирный',
      'textOutlineColor': _lime,
      'textOutlineWidth': 50.0,
    });
    expect(clamped['textShadow'], contains('6.0px'));
    expect(clamped['textShadow'], isNot(contains('25.0px')));

    final (alpha, _) = await _exportItem({
      'id': 't3',
      'type': 'text',
      'text': 'Полупрозрачный контур',
      'textOutlineColor': _halfRed,
    });
    expect(alpha['textShadow'], contains('rgba(255, 0, 0, 0.502)'));
  });

  test('обводка текста в ряду печатается тем же JS-кодом', () async {
    final (row, html) = await _exportItem({
      'id': 't1',
      'type': 'text',
      'text': 'Внутри ряда',
      'textOutlineColor': _lime,
    }, wrapInRow: true);
    final inner = (row['children'] as List).cast<Map>().firstWhere(
      (m) => m['id'] == 't1',
    );
    expect(inner['textShadow'], isA<String>());

    // Вторая половина среза: JSON сам по себе ничего не рисует, стиль на div
    // должен ставить JS-скелет, вшитый в страницу. Если убрать присваивание,
    // экспорт снова станет молча терять обводку — и тест это поймает.
    expect(html, contains('div.style.textShadow = it.textShadow'));
  });
}
