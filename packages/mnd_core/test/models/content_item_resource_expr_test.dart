// Картинка может брать путь из формулы-источника (ContentItem.resourceExpr):
// `{pic}`, `res/{level}.png`. Здесь — только семантика модели: что победит,
// если вызывающий уже вычислил формулу, и что происходит при пустом значении
// (не должно ломать сцену). Подстановку переменных делает движок,
// resolveTextVariables.

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/content_item.dart';

void main() {
  ContentItem image({String? path = 'res/images/a.png', String? expr}) =>
      ContentItem(
        id: 'i1',
        type: 'image',
        resourcePath: path,
        resourceExpr: expr,
      );

  group('ContentItem.resourceExpr', () {
    test('round-trip и отсутствие поля по умолчанию', () {
      final bound = image(expr: '{pic}');

      final restored = ContentItem.fromJson(bound.toJson());

      expect(restored.resourceExpr, '{pic}');
      expect(restored.resourcePath, 'res/images/a.png');
      expect(image().toJson().containsKey('resourceExpr'), isFalse);
    });

    test('copyWith задаёт и снимает формулу', () {
      final base = image();

      final bound = base.copyWith(resourceExpr: '{pic}');
      expect(bound.resourceExpr, '{pic}');

      final unbound = bound.copyWith(clearResourceExpr: true);
      expect(unbound.resourceExpr, isNull);
    });

    test('hasResourceExpr игнорирует пробелы', () {
      expect(image(expr: '{pic}').hasResourceExpr, isTrue);
      expect(image(expr: '   ').hasResourceExpr, isFalse);
      expect(image().hasResourceExpr, isFalse);
    });
  });

  group('resolveResourcePath', () {
    test('вычисленная формула важнее статического пути', () {
      final item = image(expr: '{pic}');

      expect(
        item.resolveResourcePath(evaluatedExpr: 'res/images/b.png'),
        'res/images/b.png',
      );
    });

    test('пустое или отсутствующее значение — откат на resourcePath', () {
      final item = image(expr: '{pic}');

      expect(item.resolveResourcePath(evaluatedExpr: ''), 'res/images/a.png');
      expect(
        item.resolveResourcePath(evaluatedExpr: '   '),
        'res/images/a.png',
      );
      expect(item.resolveResourcePath(), 'res/images/a.png');
    });

    test('без формулы вычисленное значение не участвует', () {
      final item = image();

      expect(
        item.resolveResourcePath(evaluatedExpr: 'res/images/b.png'),
        'res/images/a.png',
      );
    });

    test('движок вернул имя неизвестной переменной — откат', () {
      final item = image(expr: '{pic}');

      expect(item.resolveResourcePath(evaluatedExpr: 'pic'), 'res/images/a.png');
      // А вот `pic` со значением «pic» — уже настоящий источник.
      expect(
        image(expr: 'pic').resolveResourcePath(evaluatedExpr: 'pic'),
        'pic',
      );
    });

    test('формула без плейсхолдеров — просто строка-источник', () {
      final item = image(expr: 'res/images/c.png');

      expect(
        item.resolveResourcePath(evaluatedExpr: 'res/images/c.png'),
        'res/images/c.png',
      );
    });
  });
}
