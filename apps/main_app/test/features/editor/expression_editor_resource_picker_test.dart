// Пикер картинки в редакторе формул вставляет токен, а не путь из библиотеки.
// Две грамматики полей: формула (`'cat.png'` — литерал) и шаблон строки
// (`cat.png` — движок подставляет `{переменные}` и берёт остальное дословно).

import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/engine/quest_resource_index.dart';

void main() {
  group('пикер ресурса: токен', () {
    test('картинка — голое имя, резолвер сам подставит res/images', () {
      final token = resourceReference(
        fileName: 'cat.png',
        path: 'res/images/0c958f72.jpg',
      );
      expect(token, 'cat.png');
      expect(directResourceCandidates(token), ['res/images/cat.png']);
    });

    test('в формуле — строковый литерал', () {
      expect(resourceLiteral('cat.png', isTemplate: false), "'cat.png'");
      expect(resourceLiteral("ca't.png", isTemplate: false), r"'ca\'t.png'");
    });

    test('в шаблоне источника — без кавычек: их движок не снимает', () {
      // `'cat.png'` в resourceExpr или set_image — это буквальные кавычки в
      // пути, и картинка перестала бы находиться.
      expect(resourceLiteral('cat.png', isTemplate: true), 'cat.png');
    });
  });
}
