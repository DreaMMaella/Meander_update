import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/utils/cosmetic_ids.dart';

void main() {
  group('cosmeticSlotId', () {
    test('читает слот из карты и из строки jsonb', () {
      expect(cosmeticSlotId({'avatar_frame': 'prism_ring'}, 'avatar_frame'),
          'prism_ring');
      expect(
          cosmeticSlotId('{"avatar_frame":"prism_ring"}', 'avatar_frame'),
          'prism_ring');
    });

    test('пустота, чужой слот и битая строка дают null', () {
      expect(cosmeticSlotId(null, 'avatar_frame'), isNull);
      expect(cosmeticSlotId({'avatar_frame': ''}, 'avatar_frame'), isNull);
      expect(cosmeticSlotId({'name_style': 'x'}, 'avatar_frame'), isNull);
      expect(cosmeticSlotId('{not json', 'avatar_frame'), isNull);
      expect(cosmeticSlotId(42, 'avatar_frame'), isNull);
    });
  });
}
