// FontService: извлечение путей из инлайн-тегов [font=...], детерминированное
// family-имя и резолв «путь ресурса → family» / «family → как есть».

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/services/font_service.dart';

void main() {
  group('FontService.extractInlineFontPaths', () {
    test('находит пути в тегах [font=...]', () {
      const text =
          'Обычный текст [font=res/fonts/display.ttf]Заголовок'
          '[/font] и [font=res/fonts/body.otf]ещё[/font] конец';

      final paths = FontService.extractInlineFontPaths(text).toList();

      expect(paths, ['res/fonts/display.ttf', 'res/fonts/body.otf']);
    });

    test('текст без тегов — пустой список', () {
      expect(
        FontService.extractInlineFontPaths('просто текст **bold**'),
        isEmpty,
      );
    });

    test('пустой путь внутри тега игнорируется', () {
      final paths = FontService.extractInlineFontPaths(
        '[font=]пусто[/font] и [font=  ]пробелы[/font]',
      ).toList();
      expect(paths, isEmpty);
    });
  });

  group('FontService.resolveFamily', () {
    test('путь ресурса → детерминированное family-имя', () {
      expect(
        FontService.resolveFamily('q1', 'res/fonts/My Font.ttf'),
        'Font_q1_My_Font_ttf',
      );
    });

    test('family-имя без слэша — как есть', () {
      expect(FontService.resolveFamily('q1', 'serif'), 'serif');
    });

    test('null/пусто — null', () {
      expect(FontService.resolveFamily('q1', null), isNull);
      expect(FontService.resolveFamily('q1', '   '), isNull);
    });
  });

  group('FontService.familyNameFor', () {
    test('полный путь и basename дают одно family-имя', () {
      final full = FontService.familyNameFor('q1', 'res/fonts/display.ttf');
      final base = FontService.familyNameFor('q1', 'display.ttf');
      expect(full, base);
      expect(full, 'Font_q1_display_ttf');
    });
  });

  // Плеер регистрировал шрифты, обходя типизированный `ContentItem`, и терял
  // стиль у вложенных слоёв стека и у мастеров шаблонов — кнопка оставалась с
  // системным шрифтом. Обход по сырому JSON собирает их все.
  group('FontService.collectFontRefsFromJson', () {
    test('кнопка, текст, вложенный слой и инлайн-тег', () {
      final json = <String, dynamic>{
        'items': [
          {
            'id': 'b1',
            'buttonStyle': {'fontFamily': 'res/fonts/button.ttf'},
          },
          {'id': 't1', 'fontFamily': 'res/fonts/item.OTF'},
          {
            'id': 's1',
            'children': [
              {
                'id': 'l1',
                'buttonStyle': {'fontFamily': 'res/fonts/layer.ttf'},
              },
            ],
          },
          {
            'id': 'm1',
            'contentMarkdown': '[font=res/fonts/inline.ttf]текст[/font]',
          },
          {'id': 'x1', 'buttonText': 'обычная кнопка без шрифта'},
        ],
      };

      expect(FontService.collectFontRefsFromJson(json), {
        'res/fonts/button.ttf',
        'res/fonts/item.OTF',
        'res/fonts/layer.ttf',
        'res/fonts/inline.ttf',
      });
    });

    test('системное family-имя без расширения ресурсом не считается', () {
      expect(
        FontService.collectFontRefsFromJson({
          'buttonStyle': {'fontFamily': 'serif'},
        }),
        isEmpty,
      );
      expect(
        FontService.collectFontRefsFromJson({'text': '[font=serif]т[/font]'}),
        isEmpty,
      );
    });

    test('пустые данные и не-строки не ломают обход', () {
      expect(FontService.collectFontRefsFromJson(null), isEmpty);
      expect(
        FontService.collectFontRefsFromJson({
          'a': 1,
          'b': null,
          'c': <dynamic>[],
        }),
        isEmpty,
      );
    });
  });
}
