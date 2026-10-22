// Пресет кнопок по умолчанию на весь квест (#159).
//
// Автор сохраняет пресеты в настройках квеста и раньше был вынужден назначать
// стиль каждой кнопке руками. Теперь достаточно назвать пресет — остальное
// разбирается здесь, из config.json.

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/quest_descriptor.dart';

Map<String, dynamic> _preset(String name, {int textColor = 0xFF26C6DA}) => {
  'presetId': 'custom',
  'presetName': name,
  'textColor': textColor,
  'fillColor': 0xFF1A2336,
};

void main() {
  group('Quest.defaultButtonStyle', () {
    test('имя пресета разрешается в сам стиль', () {
      final quest = Quest.fromJson({
        'id': 'q1',
        'title': 'Квест',
        'defaultButtonPresetName': 'Неон',
        'buttonStylePresets': [_preset('Неон', textColor: 0xFFFF0000)],
      });

      expect(quest.defaultButtonPresetName, 'Неон');
      expect(quest.defaultButtonStyle?.presetName, 'Неон');
      expect(quest.defaultButtonStyle?.textColorValue, 0xFFFF0000);
    });

    test('без имени стиля нет — играет встроенное стекло', () {
      final quest = Quest.fromJson({
        'id': 'q1',
        'defaultButtonPresetName': '   ',
        'buttonStylePresets': [_preset('Неон')],
      });

      expect(quest.defaultButtonPresetName, isNull);
      expect(quest.defaultButtonStyle, isNull);
    });

    test('удалённый или переименованный пресет не ломает квест', () {
      final quest = Quest.fromJson({
        'id': 'q1',
        'defaultButtonPresetName': 'Неон',
        'buttonStylePresets': [_preset('Другое имя')],
      });

      expect(quest.defaultButtonPresetName, 'Неон');
      expect(quest.defaultButtonStyle, isNull);
      expect(quest.isCorrupted, isFalse);
    });

    test('битая запись в списке пресетов не роняет разбор config', () {
      final quest = Quest.fromJson({
        'id': 'q1',
        'defaultButtonPresetName': 'Неон',
        'buttonStylePresets': [
          {'presetName': 'Сломанный', 'textColor': 'не число'},
          _preset('Неон', textColor: 0xFF00FF00),
        ],
      });

      expect(quest.defaultButtonStyle?.textColorValue, 0xFF00FF00);
    });

    test('имя переживает round-trip через toJson', () {
      final quest = Quest.fromJson({
        'id': 'q1',
        'defaultButtonPresetName': 'Неон',
        'buttonStylePresets': [_preset('Неон')],
      });

      expect(Quest.fromJson(quest.toJson()).defaultButtonPresetName, 'Неон');
    });
  });
}
