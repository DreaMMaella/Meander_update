import 'package:canvas_app/core/services/quest_content_change_bus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Синглтон глобальный, поэтому каждый тест использует уникальные questId.

  test('markChanged увеличивает версию и уведомляет подписчиков квеста', () {
    final bus = QuestContentChangeBus.instance;
    final questId = 'q_live_1';
    var calls = 0;
    final unlisten = bus.listen(questId, () => calls++);

    expect(bus.versionOf(questId), 0);
    bus.markChanged(questId);
    expect(bus.versionOf(questId), 1);
    expect(calls, 1);

    bus.markChanged(questId);
    expect(bus.versionOf(questId), 2);
    expect(calls, 2);

    unlisten();
    bus.markChanged(questId);
    expect(calls, 2); // отписка сработала
    expect(bus.versionOf(questId), 3);
  });

  test('подписчики разных квестов изолированы', () {
    final bus = QuestContentChangeBus.instance;
    var a = 0;
    var b = 0;
    final unlistenA = bus.listen('q_live_a', () => a++);
    final unlistenB = bus.listen('q_live_b', () => b++);

    bus.markChanged('q_live_a');
    expect(a, 1);
    expect(b, 0);

    bus.markChanged('q_live_b');
    expect(a, 1);
    expect(b, 1);

    unlistenA();
    unlistenB();
  });
}
