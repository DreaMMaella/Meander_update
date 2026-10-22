import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/content_item.dart';

void main() {
  group('ButtonStyleConfig кастомизация основных кнопок', () {
    test('новые параметры проходят JSON round-trip', () {
      const config = ButtonStyleConfig(
        presetId: 'custom',
        presetName: 'Мой стиль',
        textSize: 22,
        textWeight: 700,
        letterSpacing: 0.5,
        fontFamily: 'serif',
        borderRadius: 6,
        borderWidth: 3.5,
        fillOpacity: 0.6,
        useGradient: true,
        gradientStartColorValue: 0xFFFF5722,
        gradientEndColorValue: 0xFF2196F3,
        gradientDirection: 'leftRight',
        shadowColorValue: 0xFF000000,
        shadowOpacity: 0.4,
        shadowBlur: 24,
        shadowOffsetX: 3,
        shadowOffsetY: 5,
        paddingH: 40,
        paddingV: 18,
      );

      final restored = ButtonStyleConfig.fromJson(config.toJson());

      expect(restored.presetId, 'custom');
      expect(restored.presetName, 'Мой стиль');
      expect(restored.textSize, 22);
      expect(restored.textWeight, 700);
      expect(restored.letterSpacing, 0.5);
      expect(restored.fontFamily, 'serif');
      expect(restored.borderRadius, 6);
      expect(restored.borderWidth, 3.5);
      expect(restored.fillOpacity, 0.6);
      expect(restored.useGradient, isTrue);
      expect(restored.gradientStartColorValue, 0xFFFF5722);
      expect(restored.gradientEndColorValue, 0xFF2196F3);
      expect(restored.gradientDirection, 'leftRight');
      expect(restored.shadowColorValue, 0xFF000000);
      expect(restored.shadowOpacity, 0.4);
      expect(restored.shadowBlur, 24);
      expect(restored.shadowOffsetX, 3);
      expect(restored.shadowOffsetY, 5);
      expect(restored.paddingH, 40);
      expect(restored.paddingV, 18);
    });

    test(
      'старый JSON без новых полей даёт прежние значения (обратная совместимость)',
      () {
        final oldJson = <String, dynamic>{
          'presetId': 'classic',
          'horizontalModules': 6,
          'verticalModules': 3,
          'centerModules': 9,
          'moduleSize': 11.0,
          'autoCenterByText': true,
          'fillColor': 0xFF2B2B2B,
          'borderColor': 0xFF9E9E9E,
          'textColor': 0xFFF5F5F5,
        };

        final restored = ButtonStyleConfig.fromJson(oldJson);

        expect(restored.textSize, isNull);
        expect(restored.textWeight, isNull);
        expect(restored.letterSpacing, isNull);
        expect(restored.fontFamily, isNull);
        expect(restored.borderRadius, isNull);
        expect(restored.borderWidth, isNull);
        expect(restored.fillOpacity, isNull);
        expect(restored.useGradient, isFalse);
        expect(restored.gradientStartColorValue, isNull);
        expect(restored.gradientEndColorValue, isNull);
        expect(restored.shadowColorValue, isNull);
        expect(restored.paddingH, isNull);
        expect(restored.paddingV, isNull);
        // базовые поля сохраняются
        expect(restored.moduleSize, 11.0);
        expect(restored.fillColorValue, 0xFF2B2B2B);
      },
    );

    test('toJson не пишет пустые (null) новые поля', () {
      const config = ButtonStyleConfig();
      final json = config.toJson();
      expect(json.containsKey('textSize'), isFalse);
      expect(json.containsKey('useGradient'), isFalse);
      expect(json.containsKey('shadowColor'), isFalse);
      expect(json.containsKey('paddingH'), isFalse);
    });

    test('эффективные значения по умолчанию', () {
      const config = ButtonStyleConfig();
      expect(config.effectiveTextSize, 16);
      expect(config.effectiveFillOpacity, 0.92);
      expect(config.effectiveShadowOpacity, 0.2);
      expect(config.effectiveShadowBlur, 16);
      expect(config.shadowColor, config.borderColor);
      expect(config.gradientStartColor, config.fillColor);
    });

    test('copyWith сбрасывает группы через clear-флаги', () {
      const config = ButtonStyleConfig(
        textSize: 22,
        borderRadius: 6,
        shadowBlur: 24,
        paddingH: 40,
      );

      final cleared = config.copyWith(
        clearTextOverrides: true,
        clearShapeOverrides: true,
        clearShadowOverrides: true,
        clearPaddingOverrides: true,
      );

      expect(cleared.textSize, isNull);
      expect(cleared.borderRadius, isNull);
      expect(cleared.shadowBlur, isNull);
      expect(cleared.paddingH, isNull);
    });
  });
}
