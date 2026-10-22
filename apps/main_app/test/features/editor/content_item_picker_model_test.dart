import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/editor/screens/visual_script_editor/content_item_picker_model.dart';
import 'package:mnd_core/models/content_item.dart';

ContentItem item(
  String id,
  String type, {
  String? text,
  String? path,
  String? expr,
  String? layerName,
  bool isHidden = false,
  List<ContentItem> children = const [],
}) => ContentItem(
  id: id,
  type: type,
  text: text,
  resourcePath: path,
  resourceExpr: expr,
  layerName: layerName,
  isHidden: isHidden,
  children: children.isEmpty ? null : children,
);

PickerNode node(String id, String title, List<ContentItem> items) =>
    PickerNode(id: id, title: title, items: items);

const names = {'cat.png': 'Одинокое дерево'};

void main() {
  group('сборка вариантов', () {
    test('картинка подписывается именем из библиотеки', () {
      final choices = buildContentItemChoices(
        nodes: [
          node('n1', 'Новая нода', [
            item('i1', 'image', path: 'res/images/cat.png'),
          ]),
        ],
        resourceNames: names,
      );

      expect(choices.single.label, 'Одинокое дерево');
      expect(choices.single.location, 'Новая нода');
      expect(choices.single.thumbnailSource, 'res/images/cat.png');
    });

    test('без имени в библиотеке — имя файла, без пути и расширения', () {
      final choices = buildContentItemChoices(
        nodes: [
          node('n1', 'Нода', [
            item('i1', 'image', path: 'res/images/1790024448511_ef.png'),
          ]),
        ],
      );

      expect(choices.single.label, '1790024448511_ef');
    });

    test('формула источника видна и отличается от статичной картинки', () {
      final choices = buildContentItemChoices(
        nodes: [
          node('n1', 'Нода', [item('i1', 'image', expr: 'res/{level}.png')]),
        ],
      );

      expect(choices.single.hasFormula, isTrue);
      // Миниатюру формулой не показать — подписываем тем, что автор написал.
      expect(choices.single.label, 'res/{level}.png');
    });

    test('вложенные айтемы идут с хлебными крошками', () {
      final choices = buildContentItemChoices(
        nodes: [
          node('n1', 'Нода', [
            item(
              'row',
              'row',
              children: [item('i1', 'image', path: 'res/images/cat.png')],
            ),
            item(
              'stack',
              'stack',
              children: [
                item(
                  'i2',
                  'image',
                  path: 'res/images/cat.png',
                  layerName: 'Фон',
                ),
              ],
            ),
          ]),
        ],
        resourceNames: names,
      );

      final byId = {for (final c in choices) c.item.id: c};
      expect(byId['i1']!.location, 'Нода › Ряд');
      expect(byId['i2']!.location, 'Нода › Стек');
      // Имя слоя — это подпись самого слоя, поэтому оно в label, а не в крошках.
      expect(byId['i2']!.label, 'Фон');
      // Сам контейнер — тоже законная цель, он в списке.
      expect(byId.keys, containsAll(<String>['row', 'stack', 'i1', 'i2']));
    });

    test('несколько рядов различимы', () {
      final choices = buildContentItemChoices(
        nodes: [
          node('n1', 'Нода', [
            item('r1', 'row', children: [item('a', 'image')]),
            item('r2', 'row', children: [item('b', 'image')]),
          ]),
        ],
      );

      final byId = {for (final c in choices) c.item.id: c};
      expect(byId['a']!.trail, ['Ряд 1']);
      expect(byId['b']!.trail, ['Ряд 2']);
    });

    test('фильтр по типу не прячет вложенность', () {
      final choices = buildContentItemChoices(
        nodes: [
          node('n1', 'Нода', [
            item(
              'row',
              'row',
              children: [item('i1', 'image', path: 'res/images/cat.png')],
            ),
          ]),
        ],
        allowedTypes: const ['image'],
      );

      expect(choices.map((c) => c.item.id), ['i1']);
    });
  });

  group('поиск', () {
    final choices = buildContentItemChoices(
      nodes: [
        node('n1', 'Лес', [
          item('i1', 'image', path: 'res/images/cat.png'),
          item('i2', 'text', text: 'Двери заперты'),
        ]),
        node('n2', 'Подвал', [
          item('i3', 'image', path: 'res/images/dog.png', layerName: 'Тень'),
        ]),
      ],
      resourceNames: names,
    );

    test('по имени ресурса', () {
      expect(
        searchContentItemChoices(choices, 'одинокое').map((c) => c.item.id),
        ['i1'],
      );
    });

    test('несколько слов в любом порядке', () {
      expect(
        searchContentItemChoices(
          choices,
          'дерево одинокое',
        ).map((c) => c.item.id),
        ['i1'],
      );
    });

    test('по ноде и по слою', () {
      expect(
        searchContentItemChoices(choices, 'подвал').map((c) => c.item.id),
        ['i3'],
      );
      expect(searchContentItemChoices(choices, 'тень').map((c) => c.item.id), [
        'i3',
      ]);
    });

    test('по тексту айтема', () {
      expect(
        searchContentItemChoices(choices, 'заперты').map((c) => c.item.id),
        ['i2'],
      );
    });

    test('пустой запрос — всё, мусор — ничего', () {
      expect(searchContentItemChoices(choices, '  ').length, 3);
      expect(searchContentItemChoices(choices, 'кит'), isEmpty);
    });
  });

  group('счётчики для фильтров', () {
    final choices = buildContentItemChoices(
      nodes: [
        node('n1', 'Лес', [item('i1', 'image'), item('i2', 'text')]),
        node('n2', 'Подвал', [item('i3', 'image')]),
      ],
    );

    test('ноды с числом подходящих айтемов', () {
      final groups = groupByNode(choices);
      expect(groups.map((g) => (g.id, g.count)), {('n1', 2), ('n2', 1)});
      expect(groups.first.title, 'Лес');
    });

    test('типы с числом айтемов', () {
      expect(countByType(choices), {'image': 2, 'text': 1});
    });
  });

  group('имена ресурсов из metadata', () {
    test('карта и легаси-строка, папки не ресурсы', () {
      final parsed = parseResourceNames({
        'cat.png': {'name': 'Одинокое дерево'},
        'dog.png': 'Пёс',
        'ghost.png': {'name': '  '},
        '__folders__': ['/'],
      });

      expect(parsed, {'cat.png': 'Одинокое дерево', 'dog.png': 'Пёс'});
    });
  });
}
