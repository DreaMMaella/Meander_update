// Шаблон из стека теряет шрифты (#243).
//
// Стек — это ContentItem(type: 'stack') с детьми-слоями; шрифт живёт в трёх
// местах: наследуемый `fontFamily` контейнера, `fontFamily` слоя-текста,
// `buttonStyle.fontFamily` кнопки и инлайн-тег `[font=…]` в markdown. Сами
// значения сериализуются честно, но шаблон уносит с собой только payload:
// файл шрифта в него не попадает, и в чужом квесте `FontService.loadQuestFont`
// не находит `res/fonts/<имя>.ttf` → текст рендерится дефолтным шрифтом.

import 'package:canvas_app/features/editor/utils/template_applier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

Map<String, dynamic> stackPayload() => <String, dynamic>{
  'id': 'stack-1',
  'type': 'stack',
  'fontFamily': 'res/fonts/title.ttf',
  'children': <dynamic>[
    <String, dynamic>{
      'id': 'txt-1',
      'type': 'text',
      'text': 'Привет',
      'fontFamily': 'res/fonts/hand.ttf',
    },
    <String, dynamic>{
      'id': 'md-1',
      'type': 'text',
      'contentMarkdown': '[font=res/fonts/inline.ttf]Шёпот[/font]',
    },
    <String, dynamic>{
      'id': 'btn-1',
      'type': 'button',
      'buttonText': 'Идти',
      'buttonStyle': <String, dynamic>{'fontFamily': 'res/fonts/label.ttf'},
    },
  ],
};

TemplateItem stackTemplate() => TemplateItem(
  id: 'tpl-stack',
  name: 'Стек со шрифтами',
  kind: TemplateKind.content,
  payload: stackPayload(),
);

void main() {
  test('в payload шрифт выживает: стек → ContentItem', () {
    final item = TemplateApplier.buildContentItem(stackTemplate());
    expect(item, isNotNull);
    expect(item!.fontFamily, 'res/fonts/title.ttf');
    final children = item.children!;
    expect(children[0].fontFamily, 'res/fonts/hand.ttf');
    expect(children[2].buttonStyle?.fontFamily, 'res/fonts/label.ttf');
  });

  test('шрифты стек-шаблона собираются в ассеты', () {
    final paths = TemplateApplier.collectResourcePaths(stackTemplate());
    expect(paths, contains('res/fonts/title.ttf'));
    expect(paths, contains('res/fonts/hand.ttf'));
    expect(paths, contains('res/fonts/label.ttf'));
    expect(paths, contains('res/fonts/inline.ttf'));
  });
}
