// Регрессия: краш `_lifecycleState != _ElementLifecycle.defunct` при
// размонтировании игрового экрана.
//
// Причина была в dispose(): он использовал ref.read, а dispose вызывается из
// unmount, когда элемент уже defunct (`context.mounted == false`) — ref.read
// бросал StateError, и это прерывало ConsumerStatefulElement.unmount ДО
// закрытия подписок riverpod. autoDispose-провайдер сессии не диспоузился,
// нотификатор и FFI-движок текли, а поздние эмиссии (reload после редактора,
// дебаунс live-reload, reveal-цепочка) падали в мёртвый элемент.
//
// Тест проверяет: unmount не бросает, провайдер сессии действительно
// диспоузится, и эмиссия после закрытия игры не роняет фреймворк.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/providers/game_screen_provider.dart';
import 'package:mnd_player/screens/game_screen.dart';

Future<bool> _neverStart() async => false;

final _testKey = (questId: 'test-quest', docKey: 'standalone');

void main() {
  testWidgets(
    'unmount игрового экрана не бросает и диспоузит провайдер сессии',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GameScreen(
              questId: 'test-quest',
              // Префлайт = false: сессия не стартует, движок/FFI не нужны.
              preflight: _neverStart,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final notifierBefore = container.read(
        gameScreenProvider(_testKey).notifier,
      );

      // Полностью размонтируем экран (закрытие игры / вкладки workspace).
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      // Несколько кадров: unmount, закрытие подписок, отложенный dispose
      // autoDispose-провайдера (конец фрейма).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));

      // Старый код падал здесь: ref.read в dispose бросал и unmount
      // прерывался.
      expect(tester.takeException(), isNull);

      // Провайдер сессии задиспоузился: повторный read создаёт НОВЫЙ
      // экземпляр. При утечке подписок (старый код) вернулся бы тот же
      // экземпляр, а нотификатор с движком продолжил бы жить.
      final notifierAfter = container.read(
        gameScreenProvider(_testKey).notifier,
      );
      expect(identical(notifierBefore, notifierAfter), isFalse);

      // Эмиссия «из воздуха» (как незавершённый reload после закрытия игры)
      // не должна ронять ничего: подписки экрана закрыты.
      container
          .read(gameStateProvider.notifier)
          .applyDelta(variables: {'a': '1'}, tablesJson: const {});
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
