// Очередь раскрытия ноды шагает, когда текущий айтем отдаёт `onComplete`.
// Молчаливые айтемы (спресер, скрипт, мёртвый hud_panel, статически скрытый)
// отдают этот шаг сами — и раньше отдавали его КАЖДЫЙ раз, когда список
// пересобирался, а пересобирается он после каждого нового ряда. Шагов
// становилось больше, чем айтемов, цикл прокручивался вперёд и обгонял
// препятствия: `wait_input` и `delay` теряли смысл, а текст ноды рисовался
// целиком сразу (видео тестера, 15.10).
//
// Негативный контроль: без одноразовой обёртки тест падает на втором шаге —
// молчаливый айтем отдаёт шаг повторно.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';

void main() {
  // Порядок тот же, что в ноде из видео: картинка-спресер-тексты-ожидание.
  // Движок здесь не нужен — эти ветки фабрики до него не доходят.
  final items = <ContentItem>[
    ContentItem(id: 'spacer', type: 'spacer', padding: 8),
    ContentItem(id: 'script', type: 'script', resourcePath: 'scripts/a.json'),
    ContentItem(id: 'hidden', type: 'text', text: 'спрятан', isHidden: true),
    ContentItem(id: 'hud', type: 'hud_panel'),
    ContentItem(id: 'spacer2', type: 'spacer', padding: 4),
  ];

  late int completions;

  /// Раскрывает ещё один айтем: ровно так же, как это делает экран игры, —
  /// пересобирает список с выросшим `itemCount`.
  Future<void> revealUpTo(WidgetTester tester, int count) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: count,
              itemBuilder: (context, index) => ContentDisplayFactory.build(
                item: items[index],
                questId: 'q1',
                onInteract: (_) {},
                onInputSubmitted: (_, __) {},
                onComplete: () => completions++,
                onTransition: (_) {},
                onNavigateToNode: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() => completions = 0);

  testWidgets('молчаливый айтем отдаёт шаг очереди один раз за раскрытие', (
    tester,
  ) async {
    for (var count = 1; count <= items.length; count++) {
      await revealUpTo(tester, count);
      // Один шаг на каждый раскрытый айтем — ни повторного, ни потерянного.
      expect(completions, count, reason: 'раскрыто айтемов: $count');
    }
  });

  testWidgets('пересборка списка без нового айтема очередь не двигает', (
    tester,
  ) async {
    await revealUpTo(tester, 2);
    final afterTwo = completions;
    await revealUpTo(tester, 2);
    await revealUpTo(tester, 2);
    expect(completions, afterTwo, reason: 'пустая пересборка не должна шагать');
  });

  testWidgets('стек отдаёт шаг сам, без дубля от обёртки', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ContentDisplayFactory.build(
              item: ContentItem(id: 'stack', type: 'stack', children: const []),
              questId: 'q1',
              onInteract: (_) {},
              onInputSubmitted: (_, __) {},
              onComplete: () => completions++,
              onTransition: (_) {},
              onNavigateToNode: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // `GameStackWidget` сообщает о себе из `initState` — второй шаг от
    // `InstantItem` был бы потерей одного ряда очереди.
    expect(completions, 1);
  });
}
