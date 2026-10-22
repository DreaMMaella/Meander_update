// Страж класса багов «правильно сохранил, но поле пропало».
//
// saveNodes склеивает старую запись ноды со свежей и ВЫЧИЩАЕТ ключи модели,
// которых нет в свежей сериализации (иначе снятая настройка воскресает).
// Значит любая проекция ноды, собранная перечислением полей, обязана знать
// все поля модели: незаписанное поле = удалённые из квеста данные. Так
// редактор контента терял цвет ноды и связь с мастер-шаблоном, а канвас —
// видео-фон (см. canvas_add_node_stale_overwrite_test.dart).
//
// Тест сверяет исходник проекции со списком SavedNode.modelKeys: добавил
// поле в модель и не перенёс его в редактор контента — проверка падает.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/saved_node.dart';

const String _screenPath =
    'lib/features/editor/screens/node_content_screen.dart';

/// Участок `_saveNode` от конструктора ноды до записи на диск.
String _saveProjection(String source) {
  final start = source.indexOf('final updatedNode = SavedNode(');
  expect(start, greaterThan(-1), reason: 'не найден конструктор ноды');
  final end = source.indexOf(
    'await updateNode(widget.questId, updatedNode);',
    start,
  );
  expect(end, greaterThan(start), reason: 'не найден вызов updateNode');
  return source.substring(start, end);
}

void main() {
  test('редактор контента сохраняет на диск все поля модели ноды', () {
    final source = File(_screenPath).readAsStringSync();
    final projection = _saveProjection(source);

    for (final key in SavedNode.modelKeys) {
      expect(
        projection,
        contains('$key:'),
        reason:
            'поле $key есть в SavedNode.modelKeys, но редактор контента его '
            'не пишет — saveNodes вычистит его из nodes.json',
      );
    }
  });
}
