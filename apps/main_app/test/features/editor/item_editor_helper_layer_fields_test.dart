// Редакторы «по типу» собирают ContentItem с нуля, поэтому их результат
// склеивается с исходным слоем через ItemEditorHelper.keepLayerFields.
// Проверяется то, ради чего он существует: правка кнопки внутри стека не
// должна схлопывать её бокс в точку и терять поля канваса.

import 'package:canvas_app/features/editor/logic/item_editor_helper.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';

/// Слой-кнопка так, как его оставляет канвас стека: якоря 0, смещения в px.
ContentItem _layer() => ContentItem(
  id: 'b1',
  type: 'button',
  text: 'Вкл звук',
  anchorLeft: 0,
  anchorTop: 0,
  anchorRight: 0,
  anchorBottom: 0,
  offsetLeft: 20,
  offsetTop: 40,
  offsetRight: 180,
  offsetBottom: 90,
  opacity: 0.5,
  rotation: 30,
  isHidden: true,
  locked: true,
  groupName: 'Панель',
  layerName: 'Кнопка звука',
  behaviours: const [
    ContentTrigger(event: 'onPress', script: 'scripts/sound.json'),
  ],
  templateRef: 'master-1',
  templateVersion: 3,
);

/// То, что возвращает экран кнопки: свои поля и дефолты остального.
ContentItem _fromEditor() => ContentItem(
  id: 'fresh',
  type: 'button',
  text: 'Выключить звук',
  buttonStyle: const ButtonStyleConfig(presetId: 'customPreset:кнопка_1'),
);

void main() {
  test('правка кнопки в стеке сохраняет геометрию и поля канваса', () {
    final merged = ItemEditorHelper.keepLayerFields(_layer(), _fromEditor());

    // Владелец редактора — текст и стиль.
    expect(merged.text, 'Выключить звук');
    expect(merged.buttonStyle?.presetId, 'customPreset:кнопка_1');
    // Владелец канваса — бокс: без него слой схлопывается в точку.
    expect(merged.anchorLeft, 0);
    expect(merged.anchorRight, 0);
    expect(merged.offsetLeft, 20);
    expect(merged.offsetTop, 40);
    expect(merged.offsetRight, 180);
    expect(merged.offsetBottom, 90);
    expect(
      merged.stackChildRect(290, 300),
      const Rect.fromLTRB(20, 40, 180, 90),
    );
    expect(merged.opacity, 0.5);
    expect(merged.rotation, 30);
    expect(merged.isHidden, isTrue);
    expect(merged.locked, isTrue);
    expect(merged.groupName, 'Панель');
    expect(merged.layerName, 'Кнопка звука');
    expect(merged.behaviours!.single.script, 'scripts/sound.json');
    expect(merged.templateRef, 'master-1');
    expect(merged.templateVersion, 3);
    // Идентичность слоя — из исходника, а не из свежего uuid.
    expect(merged.id, 'b1');
  });

  test('новое значение из редактора не перетирается исходным', () {
    // Проверка в другую сторону: merge не должен превращаться в «вернули
    // исходный айтем целиком».
    final merged = ItemEditorHelper.keepLayerFields(
      _layer(),
      _fromEditor().copyWith(targetNodeId: 'n2'),
    );
    expect(merged.targetNodeId, 'n2');
    // flex и id канвасу не принадлежат, но их исторически переносят из
    // исходного айтема — проверка, что merge не превращается в «взять
    // исходник целиком».
    expect(merged.flex, _layer().flex);
  });

  test('формула слоя переживает правку редактором по типу', () {
    // Числа у таких редакторов нет, а формула живёт в `numericExprs`: без
    // переноса любое «отредактировать кнопку» снимало бы привязку.
    final merged = ItemEditorHelper.keepLayerFields(
      _layer().copyWith(
        numericExprs: const {'borderRadius': 'hp / 4'},
        resourceExpr: 'res/{pic}.png',
      ),
      _fromEditor(),
    );

    expect(merged.numericExpr('borderRadius'), 'hp / 4');
    expect(merged.resourceExpr, 'res/{pic}.png');
  });

  test('редактор, который ведёт формулу, сам её и задаёт', () {
    // У исходника формулы нет — значит всё, что вернул редактор видео, его.
    final merged = ItemEditorHelper.keepLayerFields(
      _layer(),
      _fromEditor().copyWith(numericExprs: const {'textSize': '12 + gap'}),
    );

    expect(merged.numericExpr('textSize'), '12 + gap');
  });

  test('без формул merge не изобретает карту', () {
    final merged = ItemEditorHelper.keepLayerFields(_layer(), _fromEditor());

    expect(merged.numericExprs, isNull);
    expect(merged.toJson().containsKey('numericExprs'), isFalse);
  });
}
