// Язык, на котором написан квест (#331).
//
// Маркет обязан первыми показывать квесты на языке игрока, для этого метадата
// должна жить в config.json и переживать разбор — иначе параметр теряется при
// первом же сохранении настроек квеста.

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/quest_descriptor.dart';

void main() {
  group('Quest.language', () {
    test('код языка переживает round-trip через toJson', () {
      final quest = Quest.fromJson({
        'id': 'q1',
        'title': 'Квест',
        'language': ' ja ',
      });

      expect(quest.language, 'ja');
      expect(quest.toJson()['language'], 'ja');
      expect(Quest.fromJson(quest.toJson()).language, 'ja');
    });

    test('региональный код сохраняется как есть', () {
      final quest = Quest.fromJson({
        'id': 'q1',
        'language': 'pt-BR',
      });

      expect(Quest.fromJson(quest.toJson()).language, 'pt-BR');
    });

    test('без языка или с пустым значением — поля в json нет', () {
      final absent = Quest.fromJson({'id': 'q1'});
      expect(absent.language, isNull);
      expect(absent.toJson().containsKey('language'), isFalse);

      final blank = Quest.fromJson({'id': 'q1', 'language': '   '});
      expect(blank.language, isNull);
      expect(blank.toJson().containsKey('language'), isFalse);
    });

    test('copyWith не теряет язык', () {
      final quest = Quest.fromJson({'id': 'q1', 'language': 'de'});

      expect(quest.copyWith(title: 'Новое название').language, 'de');
    });
  });
}
