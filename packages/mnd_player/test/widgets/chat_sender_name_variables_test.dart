// Рантайм: имя отправителя в чате — такое же поле с переменными, как и текст
// сообщения. До фикса `{npc}` подставлялся только в тело, а имя рисовалось
// буквально и у входящих, и у исходящих пузырей.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/widgets/content_display_factory.dart'
    show ChatItemWidget;

/// `{…}` раскрывает Rust-ядро, поэтому этим тестам нужен собранный `.so`
/// (как в `image_resource_expr_test.dart`).
final String? _soPath = () {
  final env = Platform.environment['MND_FFI_SO'];
  if (env != null && File(env).existsSync()) return env;
  for (final candidate in [
    '../../target/release/libmnd_ffi.so',
    '../../crates/mnd-ffi/target/release/libmnd_ffi.so',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}();

void main() {
  setUpAll(() async {
    if (_soPath != null) {
      await initRustCore(externalLibrary: ExternalLibrary.open(_soPath!));
    }
  });

  ContentItem chat({
    required String? senderName,
    bool incoming = true,
  }) => ContentItem(
    id: 'chat-1',
    type: 'chat',
    text: 'Привет',
    senderName: senderName,
    isIncoming: incoming,
  );

  Future<ProviderContainer> render(
    WidgetTester tester,
    ContentItem item,
  ) async {
    final container = ProviderContainer()
      ..listen(gameStateProvider, (_, __) {});
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: ChatItemWidget(item: item, questId: 'q1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('имя без переменных остаётся как написано', (tester) async {
    await render(tester, chat(senderName: 'Голос'));

    expect(find.text('Голос'), findsOneWidget);
  });

  testWidgets('пустое имя остаётся заглушкой', (tester) async {
    await render(tester, chat(senderName: '   '));

    expect(find.text('Отправитель'), findsOneWidget);
  });

  group('имя отправителя с переменными', () {
    testWidgets('входящее сообщение', (tester) async {
      final container = await render(tester, chat(senderName: '{npc}'));
      container.read(gameStateProvider.notifier).setVariable('npc', 'Аня');
      await tester.pumpAndSettle();

      expect(find.text('Аня'), findsOneWidget);
      expect(find.text('{npc}'), findsNothing);
    });

    testWidgets('исходящее сообщение', (tester) async {
      final container = await render(
        tester,
        chat(senderName: '{npc}', incoming: false),
      );
      container.read(gameStateProvider.notifier).setVariable('npc', 'Аня');
      await tester.pumpAndSettle();

      expect(find.text('Аня'), findsOneWidget);
    });

    testWidgets('имя меняется вместе с переменной', (tester) async {
      final container = await render(tester, chat(senderName: '{npc}'));
      container.read(gameStateProvider.notifier).setVariable('npc', 'Витя');
      await tester.pumpAndSettle();

      expect(find.text('Витя'), findsOneWidget);
    });

    testWidgets('имя может склеивать переменную с текстом', (tester) async {
      final container = await render(
        tester,
        chat(senderName: '{npc} (аноним)'),
      );
      container.read(gameStateProvider.notifier).setVariable('npc', 'Аня');
      await tester.pumpAndSettle();

      expect(find.text('Аня (аноним)'), findsOneWidget);
    });
  }, skip: _soPath == null);
}
