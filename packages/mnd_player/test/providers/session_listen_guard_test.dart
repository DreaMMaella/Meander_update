// Регрессия: краш `_lifecycleState != _ElementLifecycle.defunct` при эмиссии
// StateNotifier после размонтирования экрана. Игровой экран НЕ использует
// `ref.watch` для пересборки (riverpod 2.6.1 вызывает markNeedsBuild
// безусловно), а слушает через `ref.listenManual` с guard'ом `mounted`.
// Этот тест повторяет паттерн GameScreen и проверяет: пересборка работает,
// а эмиссия после unmount не роняет тест.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionCount extends StateNotifier<int> {
  _SessionCount() : super(0);
}

final _sessionCountProvider =
    StateNotifierProvider.autoDispose<_SessionCount, int>((ref) {
      return _SessionCount();
    });

/// Копия паттерна GameScreen: listenManual в initState с guard'ом mounted,
/// чтение в build без подписки.
class _TestSessionScreen extends ConsumerStatefulWidget {
  const _TestSessionScreen();

  @override
  ConsumerState<_TestSessionScreen> createState() => _TestSessionScreenState();
}

class _TestSessionScreenState extends ConsumerState<_TestSessionScreen> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(_sessionCountProvider, (prev, next) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text('count: ${ref.read(_sessionCountProvider)}'));
  }
}

void main() {
  testWidgets('пересборка по эмиссии работает', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _TestSessionScreen()),
      ),
    );
    expect(find.text('count: 0'), findsOneWidget);

    container.read(_sessionCountProvider.notifier).state = 5;
    await tester.pump();
    expect(find.text('count: 5'), findsOneWidget);

    container.read(_sessionCountProvider.notifier).state = 3;
    await tester.pump();
    expect(find.text('count: 3'), findsOneWidget);
  });

  testWidgets(
    'эмиссия после размонтирования экрана не роняет (guard mounted)',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: _TestSessionScreen()),
        ),
      );
      await tester.pump();

      // Полностью размонтируем экран.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      await tester.pump();

      // Эмиссия «из воздуха» — как незавершённый reload после закрытия игры.
      // С паттерном ref.watch это падало бы ассертом defunct-элемента.
      container.read(_sessionCountProvider.notifier).state = 7;
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
