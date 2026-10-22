import 'package:flutter_test/flutter_test.dart';

import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/services/trigger_pipeline.dart';

/// Тесты TriggerPipeline: фасад для поведений.
/// Тестируем статические методы и resolveInteractionEvent (не требуют состояния).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // TriggerPipeline.itemHasInteraction
  // ---------------------------------------------------------------------------

  group('TriggerPipeline.itemHasInteraction', () {
    test('true when item has onPress in behaviours', () {
      final item = ContentItem(
        id: 'b1',
        type: 'button',
        behaviours: [
          const ContentTrigger(event: 'onPress', script: 'scripts/btn.lua'),
        ],
      );
      expect(TriggerPipeline.itemHasInteraction(item), isTrue);
    });

    test('true when item has onSubmit in behaviours', () {
      final item = ContentItem(
        id: 'i1',
        type: 'input',
        behaviours: [
          const ContentTrigger(event: 'onSubmit', script: 'scripts/submit.lua'),
        ],
      );
      expect(TriggerPipeline.itemHasInteraction(item), isTrue);
    });

    test('true when item has onPress in legacy scriptTriggers', () {
      final item = ContentItem(
        id: 'b1',
        type: 'button',
        scriptTriggers: const {'onPress': 'scripts/btn.json'},
      );
      expect(TriggerPipeline.itemHasInteraction(item), isTrue);
    });

    test('false when no interaction behaviours', () {
      final item = ContentItem(id: 't1', type: 'text');
      expect(TriggerPipeline.itemHasInteraction(item), isFalse);
    });

    test('false when only onAppear without onPress', () {
      final item = ContentItem(
        id: 't1',
        type: 'text',
        scriptTriggers: const {'onAppear': 'scripts/show.json'},
      );
      expect(TriggerPipeline.itemHasInteraction(item), isFalse);
    });

    test('false when empty behaviours', () {
      final item = ContentItem(
        id: 'b1',
        type: 'button',
        behaviours: const [],
      );
      expect(TriggerPipeline.itemHasInteraction(item), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // TriggerPipeline.resolveInteractionEvent
  // ---------------------------------------------------------------------------

  group('TriggerPipeline.resolveInteractionEvent', () {
    test('input → onSubmit preferred', () {
      final item = ContentItem(
        id: 'i1',
        type: 'input',
        behaviours: [
          const ContentTrigger(event: 'onSubmit', script: 's.lua'),
          const ContentTrigger(event: 'onPress', script: 's.lua'),
        ],
      );
      expect(TriggerPipeline.resolveInteractionEvent(item), 'onSubmit');
    });

    test('input → onPress fallback when no onSubmit', () {
      final item = ContentItem(
        id: 'i1',
        type: 'input',
        behaviours: [
          const ContentTrigger(event: 'onPress', script: 's.lua'),
        ],
      );
      expect(TriggerPipeline.resolveInteractionEvent(item), 'onPress');
    });

    test('button → onPress', () {
      final item = ContentItem(
        id: 'b1',
        type: 'button',
        behaviours: [
          const ContentTrigger(event: 'onPress', script: 's.lua'),
        ],
      );
      expect(TriggerPipeline.resolveInteractionEvent(item), 'onPress');
    });

    test('button without onPress but with onAppear → onAppear', () {
      final item = ContentItem(
        id: 'b1',
        type: 'button',
        behaviours: [
          const ContentTrigger(event: 'onAppear', script: 's.lua'),
        ],
      );
      expect(TriggerPipeline.resolveInteractionEvent(item), 'onAppear');
    });

    test('null when no behaviours', () {
      final item = ContentItem(id: 't1', type: 'text');
      expect(TriggerPipeline.resolveInteractionEvent(item), isNull);
    });

    test('legacy: onPress from scriptTriggers', () {
      final item = ContentItem(
        id: 'b1',
        type: 'button',
        scriptTriggers: const {'onPress': 'scripts/btn.json'},
      );
      expect(TriggerPipeline.resolveInteractionEvent(item), 'onPress');
    });

    test('legacy: input with onSubmit in scriptTriggers', () {
      final item = ContentItem(
        id: 'i1',
        type: 'input',
        scriptTriggers: const {'onSubmit': 'scripts/submit.json'},
      );
      expect(TriggerPipeline.resolveInteractionEvent(item), 'onSubmit');
    });
  });
}