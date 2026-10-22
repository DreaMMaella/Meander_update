// Блок `set_image` договаривается с клиентом через служебную переменную
// движка. Здесь — правила чтения этой переменной: своё значение у своего
// айтема, ничего чужого, пустое значение не считается переопределением.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

void main() {
  Map<String, dynamic> stateWith(Map<String, dynamic> overrides) => {
    kItemSourceVar: overrides,
  };

  test('источник своего айтема возвращается', () {
    final variables = stateWith({'img': 'res/images/cat.png'});
    expect(itemSourceOverride(variables, 'img'), 'res/images/cat.png');
  });

  test('обрезается обрамляющий пробел', () {
    final variables = stateWith({'img': '  res/images/cat.png  '});
    expect(itemSourceOverride(variables, 'img'), 'res/images/cat.png');
  });

  test('пустое и null-значение — не переопределение', () {
    for (final value in ['', '   ', null]) {
      expect(
        itemSourceOverride(stateWith({'img': value}), 'img'),
        isNull,
        reason: 'значение: $value',
      );
    }
  });

  test('переменная отсутствует или имеет другой тип', () {
    expect(itemSourceOverride({}, 'img'), isNull);
    expect(itemSourceOverride({kItemSourceVar: 'res/a.png'}, 'img'), isNull);
    expect(
      itemSourceOverride({
        kItemSourceVar: ['res/a.png'],
      }, 'img'),
      isNull,
    );
  });

  test('значение доходит из сейва после JSON-раунд-трипа', () {
    final decoded =
        jsonDecode(jsonEncode(stateWith({'img': 'res/images/cat.png'})))
            as Map<String, dynamic>;
    expect(itemSourceOverride(decoded, 'img'), 'res/images/cat.png');
  });
}
