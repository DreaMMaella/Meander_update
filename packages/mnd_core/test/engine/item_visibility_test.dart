// Блок `set_visible` договаривается с клиентом через служебную переменную
// движка: `{itemId: "hidden" | "gone" | "visible"}`. Здесь правила чтения:
// спрятан только тот айтем, про который явно сказали, всё остальное — на
// усмотрение модели. Отдельно проверяется старый формат (bool): сейвы до
// разделения «скрыть/убрать» умели только схлопывать ряд.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

void main() {
  Map<String, dynamic> stateWith(Map<String, dynamic> overrides) => {
    kItemHiddenVar: overrides,
  };

  EngineVisibility visibilityOf(Object? value) =>
      engineVisibilityOf(stateWith({'photo': value}), 'photo');

  test('скрыть оставляет место, убрать выводит из раскладки', () {
    expect(visibilityOf('hidden'), EngineVisibility.hidden);
    expect(visibilityOf('gone'), EngineVisibility.gone);
    expect(visibilityOf('visible'), EngineVisibility.visible);
  });

  test('про айтем не сказали — ключа нет: как в модели квеста', () {
    expect(visibilityOf(null), EngineVisibility.visible);
    expect(
      engineVisibilityOf(stateWith({'hud': 'gone'}), 'photo'),
      EngineVisibility.visible,
    );
  });

  test('true из старого сейва — «убрать»: раньше ряд именно схлопывался', () {
    expect(visibilityOf(true), EngineVisibility.gone);
    expect(visibilityOf(false), EngineVisibility.visible);
  });

  test('мусор вместо видимости — не прячет', () {
    for (final junk in [
      'true',
      'спрятано',
      42,
      {'a': 1},
    ]) {
      expect(visibilityOf(junk), EngineVisibility.visible, reason: '$junk');
    }
  });

  test('переменная отсутствует или имеет другой тип', () {
    expect(engineVisibilityOf({}, 'photo'), EngineVisibility.visible);
    expect(
      engineVisibilityOf({kItemHiddenVar: 'photo'}, 'photo'),
      EngineVisibility.visible,
    );
    expect(
      engineVisibilityOf({
        kItemHiddenVar: ['photo'],
      }, 'photo'),
      EngineVisibility.visible,
    );
  });

  test('значение доходит из сейва после JSON-раунд-трипа', () {
    final decoded =
        jsonDecode(jsonEncode(stateWith({'photo': 'hidden', 'hud': 'visible'})))
            as Map<String, dynamic>;
    expect(engineVisibilityOf(decoded, 'photo'), EngineVisibility.hidden);
    expect(engineVisibilityOf(decoded, 'hud'), EngineVisibility.visible);
  });
}
