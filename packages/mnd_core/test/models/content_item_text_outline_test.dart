// Обводка текста (ContentItem.textOutlineColor / textOutlineWidth): round-trip
// через json и обратная совместимость — без обводки файл квеста не меняется.
// Те же ключи читает Rust-зеркало (crates/mnd-core/src/models/content_item.rs),
// иначе round-trip ноды сотрёт настройку.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/content_item.dart';

void main() {
  group('обводка текста', () {
    test('цвет и толщина доживают до файла и обратно', () {
      final item = ContentItem(
        id: 't1',
        type: 'text',
        text: 'Привет',
        textOutlineColor: const Color(0xFFFF0000),
        textOutlineWidth: 3,
      );

      final restored = ContentItem.fromJson(item.toJson());

      expect(restored.textOutlineColor, const Color(0xFFFF0000));
      expect(restored.textOutlineWidth, 3);
    });

    test('без обводки ключей в json нет', () {
      final json = ContentItem(id: 't2', type: 'text', text: 'Хелло').toJson();

      expect(json.containsKey('textOutlineColor'), isFalse);
      expect(json.containsKey('textOutlineWidth'), isFalse);
    });

    test('толщина без цвета в файл не едет: обводки всё равно нет', () {
      final json = ContentItem(
        id: 't3',
        type: 'text',
        textOutlineWidth: 4,
      ).toJson();

      expect(json.containsKey('textOutlineColor'), isFalse);
      expect(json.containsKey('textOutlineWidth'), isFalse);
    });

    test('copyWith меняет половину пары и снимает обводку целиком', () {
      final base = ContentItem(id: 't4', type: 'text').copyWith(
        textOutlineColor: const Color(0xFF00FF00),
        textOutlineWidth: 2,
      );

      expect(
        base.copyWith(textOutlineWidth: 5).textOutlineColor,
        const Color(0xFF00FF00),
        reason: 'цвет остаётся, пока автор не просит снять обводку',
      );
      final cleared = base.copyWith(clearTextOutline: true);
      expect(cleared.textOutlineColor, isNull);
      expect(cleared.textOutlineWidth, isNull);
    });
  });

  test('дефолтная толщина — та, что применяет плеер', () {
    expect(kTextOutlineWidthDefault, 2.0);
    expect(kTextOutlineWidthMin < kTextOutlineWidthDefault, isTrue);
    expect(kTextOutlineWidthMax > kTextOutlineWidthDefault, isTrue);
  });
}
