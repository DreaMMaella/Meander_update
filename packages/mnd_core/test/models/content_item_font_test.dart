// Шрифт на уровне айтема (ContentItem.fontFamily): JSON round-trip и
// обратная совместимость (null → поле не пишется, старые квесты не меняются).

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/content_item.dart';

void main() {
  group('ContentItem.fontFamily', () {
    test('путь ресурса проходит round-trip', () {
      final item = ContentItem(
        id: 't1',
        type: 'text',
        text: 'Привет',
        fontFamily: 'res/fonts/display.ttf',
      );

      final restored = ContentItem.fromJson(item.toJson());

      expect(restored.fontFamily, 'res/fonts/display.ttf');
      expect(restored.text, 'Привет');
    });

    test('null — поле не пишется (обратная совместимость)', () {
      final item = ContentItem(id: 't2', type: 'text', text: 'Хелло');

      final json = item.toJson();

      expect(json.containsKey('fontFamily'), isFalse);
      expect(ContentItem.fromJson(json).fontFamily, isNull);
    });

    test('copyWith задаёт и очищает шрифт', () {
      final base = ContentItem(id: 't3', type: 'text', text: 'x');

      final withFont = base.copyWith(fontFamily: 'res/fonts/x.ttf');
      expect(withFont.fontFamily, 'res/fonts/x.ttf');

      final cleared = withFont.copyWith(clearFontFamily: true);
      expect(cleared.fontFamily, isNull);
    });

    test('дети сохраняют свой шрифт', () {
      final parent = ContentItem(
        id: 'p1',
        type: 'column',
        fontFamily: 'res/fonts/head.ttf',
        children: [
          ContentItem(
            id: 'c1',
            type: 'text',
            text: 'внутри',
            fontFamily: 'res/fonts/body.ttf',
          ),
        ],
      );

      final restored = ContentItem.fromJson(parent.toJson());

      expect(restored.fontFamily, 'res/fonts/head.ttf');
      expect(restored.children!.single.fontFamily, 'res/fonts/body.ttf');
    });
  });

  group('ContentItem.textSize', () {
    test('размер доходит до ребёнка стека через json', () {
      final stack = ContentItem(
        id: 's1',
        type: 'stack',
        children: [
          ContentItem(id: 'c1', type: 'text', text: 'Привет', textSize: 28),
        ],
      );

      final restored = ContentItem.fromJson(stack.toJson());

      expect(restored.children!.single.textSize, 28);
    });

    test('null — поле не пишется, copyWith умеет очистить', () {
      final item = ContentItem(id: 't1', type: 'text', text: 'x');
      expect(item.toJson().containsKey('textSize'), isFalse);

      final sized = item.copyWith(textSize: 12);
      expect(sized.textSize, 12);
      expect(sized.copyWith(clearTextSize: true).textSize, isNull);
    });
  });
}
