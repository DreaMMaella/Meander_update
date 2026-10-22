import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/features/game/providers/game_screen_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gameScreenProvider keys engine sessions by quest + document', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const keyA = (questId: 'q1', docKey: 'simulation:root');
    const keyB = (questId: 'q1', docKey: 'save:slot-1');

    final a = container.read(gameScreenProvider(keyA).notifier);
    final b = container.read(gameScreenProvider(keyB).notifier);
    final aAgain = container.read(gameScreenProvider(keyA).notifier);

    // Разные игровые вкладки одного квеста → разные движки/нотификаторы.
    expect(a, isNot(same(b)));
    // Повторное чтение того же ключа → тот же нотификатор.
    expect(a, same(aAgain));
  });
}
