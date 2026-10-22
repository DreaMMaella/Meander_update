import 'package:flutter_test/flutter_test.dart';

import 'package:mnd_core/models/content_item.dart';

/// Tests for ContentTrigger model and ContentItem.resolvedBehaviours.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // ContentTrigger JSON roundtrip
  // ===========================================================================

  group('ContentTrigger.fromJson', () {
    test('basic action trigger with defaults', () {
      final ct = ContentTrigger.fromJson({
        'event': 'onPress',
        'script': 'scripts/btn.lua',
      });
      expect(ct.event, 'onPress');
      expect(ct.script, 'scripts/btn.lua');
      expect(ct.kind, 'action');
    });

    test('visibility trigger', () {
      final ct = ContentTrigger.fromJson({
        'event': 'onAppear',
        'script': 'scripts/show.json',
        'kind': 'visibility',
      });
      expect(ct.event, 'onAppear');
      expect(ct.kind, 'visibility');
    });

    test('reveal trigger', () {
      final ct = ContentTrigger.fromJson({
        'event': 'onReveal',
        'script': 'scripts/anim.json',
        'kind': 'reveal',
      });
      expect(ct.event, 'onReveal');
      expect(ct.kind, 'reveal');
    });

    test('empty json defaults', () {
      final ct = ContentTrigger.fromJson({});
      expect(ct.event, '');
      expect(ct.script, '');
      expect(ct.kind, 'action');
    });
  });

  group('ContentTrigger.toJson', () {
    test('action kind is omitted (default)', () {
      final ct = ContentTrigger(
        event: 'onPress',
        script: 'scripts/btn.lua',
        kind: 'action',
      );
      final json = ct.toJson();
      expect(json['event'], 'onPress');
      expect(json['script'], 'scripts/btn.lua');
      expect(json.containsKey('kind'), isFalse);
    });

    test('visibility kind is preserved', () {
      final ct = ContentTrigger(
        event: 'onAppear',
        script: 'scripts/show.json',
        kind: 'visibility',
      );
      final json = ct.toJson();
      expect(json['kind'], 'visibility');
    });
  });

  // ===========================================================================
  // ContentItem.resolvedBehaviours
  // ===========================================================================

  group('ContentItem.resolvedBehaviours', () {
    test('empty when no triggers', () {
      final item = ContentItem(id: 't1', type: 'text');
      expect(item.resolvedBehaviours, isEmpty);
    });

    test('prefers behaviours over scriptTriggers', () {
      final item = ContentItem(
        id: 'b1',
        type: 'button',
        behaviours: [
          ContentTrigger(event: 'onPress', script: 'scripts/new.lua'),
        ],
        scriptTriggers: {'onPress': 'scripts/old.json'},
      );
      final behs = item.resolvedBehaviours;
      expect(behs.length, 1);
      expect(behs.first.script, 'scripts/new.lua');
    });

    test('falls back to scriptTriggers when no behaviours', () {
      final item = ContentItem(
        id: 'b1',
        type: 'button',
        scriptTriggers: {
          'onPress': 'scripts/btn.json',
          'onAppear': 'scripts/show.json',
        },
      );
      final behs = item.resolvedBehaviours;
      expect(behs.length, 2);
      expect(behs.every((b) => b.kind == 'action'), isTrue);
    });

    test('empty when behaviours array is empty', () {
      final item = ContentItem(id: 'b1', type: 'button', behaviours: []);
      expect(item.resolvedBehaviours, isEmpty);
    });

    test('roundtrip through fromJson → toJson preserves behaviours', () {
      final json = {
        'id': 'b1',
        'type': 'button',
        'behaviours': [
          {'event': 'onPress', 'script': 'scripts/btn.lua'},
          {
            'event': 'onAppear',
            'script': 'scripts/show.json',
            'kind': 'visibility',
          },
        ],
      };
      final item = ContentItem.fromJson(json);
      final output = item.toJson();

      expect(output['behaviours'], isNotNull);
      final behs = output['behaviours'] as List;
      expect(behs.length, 2);
      expect(behs[0]['event'], 'onPress');
      expect(behs[1]['kind'], 'visibility');
    });

    test('roundtrip: old scriptTriggers survive toJson', () {
      final json = {
        'id': 'b1',
        'type': 'button',
        'scriptTriggers': {'onPress': 'scripts/btn.json'},
      };
      final item = ContentItem.fromJson(json);
      final output = item.toJson();
      expect(output['scriptTriggers'], isNotNull);
    });
  });

  // ===========================================================================
  // ContentItem.showTimer — флаг обратного отсчёта модалки. В старых файлах
  // квеста он прятался в `scriptTriggers` (`{"showTimer": "true"}`), где
  // проверка квеста читала его как ссылку на несуществующий скрипт «true».
  // ===========================================================================

  group('ContentItem.showTimer', () {
    test('собственное поле читается и возвращается в json', () {
      final item = ContentItem.fromJson({
        'id': 'm1',
        'type': 'modal',
        'showTimer': true,
      });
      expect(item.showTimer, isTrue);
      expect(item.toJson()['showTimer'], isTrue);
    });

    test('выключенный флаг не плодит ключ', () {
      final item = ContentItem.fromJson({'id': 'm2', 'type': 'modal'});
      expect(item.showTimer, isFalse);
      expect(item.toJson().containsKey('showTimer'), isFalse);
    });

    test('legacy-запись переезжает в поле и выпадет из карты', () {
      final item = ContentItem.fromJson({
        'id': 'm3',
        'type': 'modal',
        'scriptTriggers': {'showTimer': 'true'},
      });
      expect(item.showTimer, isTrue);
      expect(item.scriptTriggers, isNull);
      expect(item.resolvedBehaviours, isEmpty);
      final output = item.toJson();
      expect(output['showTimer'], isTrue);
      expect(output.containsKey('scriptTriggers'), isFalse);
    });

    test('из mixed-карты уходит только showTimer, скрипт остаётся', () {
      final item = ContentItem.fromJson({
        'id': 'm4',
        'type': 'modal',
        'scriptTriggers': {
          'showTimer': 'true',
          'onPress': 'scripts/a.json',
        },
      });
      expect(item.showTimer, isTrue);
      expect(item.scriptTriggers, {'onPress': 'scripts/a.json'});
      expect(item.scriptForEvent('onPress'), 'scripts/a.json');
    });
  });

  // ===========================================================================
  // ContentItem.scriptForEvent — единый поиск скрипта по событию для плеера
  // (`_onItemInteract`, ConditionalContentWrapper читали только legacy map).
  // ===========================================================================

  group('ContentItem.scriptForEvent', () {
    test('находит скрипт в legacy scriptTriggers', () {
      final item = ContentItem(
        id: 't1',
        type: 'text',
        scriptTriggers: {'onPress': 'scripts/legacy.json'},
      );
      expect(item.scriptForEvent('onPress'), 'scripts/legacy.json');
      expect(item.scriptForEvent('onSubmit'), isNull);
    });

    test('находит скрипт в новом behaviours', () {
      final item = ContentItem(
        id: 't1',
        type: 'text',
        behaviours: [
          ContentTrigger(event: 'onAppear', script: 'scripts/show.json'),
        ],
      );
      expect(item.scriptForEvent('onAppear'), 'scripts/show.json');
    });

    test('пустая ссылка не считается триггером', () {
      final legacy = ContentItem(
        id: 't1',
        type: 'text',
        scriptTriggers: {'onPress': ''},
      );
      expect(legacy.scriptForEvent('onPress'), isNull);

      final blankBehaviour = ContentItem(
        id: 't2',
        type: 'text',
        behaviours: [const ContentTrigger(event: 'onPress', script: '   ')],
      );
      expect(blankBehaviour.scriptForEvent('onPress'), isNull);
    });
  });

  // ===========================================================================
  // ContentItem.resolvedTriggers — карта занятых слотов для редактора.
  // Зеркало scriptForEvent: без него TriggerSlotButtons и карточка элемента
  // читали только legacy `scriptTriggers` и показывали пустой глазик на
  // айтеме с `behaviours`, хотя плеер скрипт выполнял.
  // ===========================================================================

  group('ContentItem.resolvedTriggers', () {
    test('совпадает с scriptForEvent по каждому событию', () {
      final item = ContentItem(
        id: 't1',
        type: 'button',
        behaviours: [
          const ContentTrigger(event: 'onPress', script: 'scripts/new.lua'),
          const ContentTrigger(
            event: 'onAppear',
            script: 'scripts/show.json',
            kind: 'visibility',
          ),
          const ContentTrigger(event: 'onSubmit', script: '   '),
        ],
        scriptTriggers: {
          'onPress': 'scripts/old.json',
          'onTimer': 'scripts/tick.json',
        },
      );

      final map = item.resolvedTriggers;
      expect(map.keys.toSet(), {'onPress', 'onAppear'});
      expect(
        map['onPress'],
        'scripts/new.lua',
        reason: 'behaviours перекрывает legacy',
      );
      for (final e in map.entries) {
        expect(
          item.scriptForEvent(e.key),
          e.value,
          reason: 'редактор и плеер расходятся на ${e.key}',
        );
      }
    });

    test('живой behaviours затеняет legacy-запись — плеер её не выполнит', () {
      final item = ContentItem(
        id: 't1',
        type: 'button',
        behaviours: [
          const ContentTrigger(event: 'onPress', script: 'scripts/new.lua'),
        ],
        scriptTriggers: {'onAppear': 'scripts/old.json'},
      );
      expect(item.resolvedTriggers.containsKey('onAppear'), isFalse);
      expect(item.scriptForEvent('onAppear'), isNull);
    });

    test('legacy без behaviours читается целиком', () {
      final item = ContentItem(
        id: 't1',
        type: 'button',
        scriptTriggers: {'onPress': 'scripts/btn.json', 'onAppear': ''},
      );
      expect(item.resolvedTriggers, {'onPress': 'scripts/btn.json'});
    });
  });

  // ===========================================================================
  // ContentItem.withTrigger / withoutTrigger — редактор обязан писать туда,
  // откуда движок читает, и убирать оттуда же.
  // ===========================================================================

  group('ContentItem.withTrigger', () {
    const script = 'scripts/fn.json#fn=Проверка';

    for (final (label, base) in [
      (
        'только legacy',
        ContentItem(
          id: 'x',
          type: 'text',
          scriptTriggers: {'onPress': 'scripts/other.json'},
        ),
      ),
      ('пустой айтем', ContentItem(id: 'x', type: 'text')),
      (
        'есть behaviours',
        ContentItem(
          id: 'x',
          type: 'text',
          behaviours: [
            ContentTrigger(event: 'onSubmit', script: 'scripts/other.json'),
          ],
          scriptTriggers: {'onPress': 'scripts/old.json'},
        ),
      ),
    ]) {
      test('запись читается движком ($label)', () {
        final item = base.withTrigger('onAppear', script);
        expect(item.scriptForEvent('onAppear'), script);
        expect(item.resolvedTriggers['onAppear'], script);
      });
    }

    test('не переезжает другие события', () {
      final item = ContentItem(
        id: 'x',
        type: 'text',
        scriptTriggers: {'onPress': 'scripts/press.json'},
      ).withTrigger('onAppear', script);
      expect(item.scriptForEvent('onPress'), 'scripts/press.json');
      expect(item.scriptTriggers?['onPress'], 'scripts/press.json');
    });

    test('kind занятого события сохраняется: видимость ≠ действие', () {
      final item = ContentItem(
        id: 'x',
        type: 'text',
        behaviours: [
          const ContentTrigger(
            event: 'onAppear',
            script: 'scripts/old.json',
            kind: 'visibility',
          ),
        ],
      ).withTrigger('onAppear', script);
      expect(item.behaviours!.single.kind, 'visibility');
      expect(item.behaviours!.single.script, script);
    });

    test('при живых behaviours legacy остаётся нетронутым, но мёртвым', () {
      final item = ContentItem(
        id: 'x',
        type: 'text',
        behaviours: [
          const ContentTrigger(event: 'onPress', script: 'scripts/a.json'),
        ],
        scriptTriggers: {'onPress': 'scripts/legacy.json'},
      ).withTrigger('onPress', 'scripts/b.json');
      expect(item.scriptTriggers, {'onPress': 'scripts/legacy.json'});
      expect(item.behaviours!.single.script, 'scripts/b.json');
    });
  });

  group('ContentItem.withoutTrigger', () {
    test('гасит слот, если форматы оба', () {
      final item = ContentItem(
        id: 'x',
        type: 'text',
        behaviours: [
          const ContentTrigger(event: 'onAppear', script: 'scripts/a.json'),
          const ContentTrigger(event: 'onPress', script: 'scripts/b.json'),
        ],
        scriptTriggers: {'onAppear': 'scripts/legacy.json'},
      ).withoutTrigger('onAppear');
      expect(item.scriptForEvent('onAppear'), isNull);
      expect(item.resolvedTriggers, {'onPress': 'scripts/b.json'});
    });

    test('чистит legacy и снимает флаг при последнем событии', () {
      final item = ContentItem(
        id: 'x',
        type: 'text',
        scriptTriggers: {
          'onAppear': 'scripts/a.json',
          'onPress': 'scripts/b.json',
        },
      ).withoutTrigger('onPress');
      expect(item.scriptTriggers, {'onAppear': 'scripts/a.json'});
      expect(item.resolvedTriggers, {'onAppear': 'scripts/a.json'});

      final empty = item.withoutTrigger('onAppear');
      expect(empty.scriptTriggers, isNull);
      expect(empty.resolvedTriggers, isEmpty);
      expect(empty.scriptForEvent('onAppear'), isNull);
    });

    test('удаление незанятого слота ничего не меняет', () {
      final item = ContentItem(id: 'x', type: 'text');
      final after = item.withoutTrigger('onAppear');
      expect(after.scriptTriggers, isNull);
      expect(after.behaviours, isNull);
    });
  });
}
