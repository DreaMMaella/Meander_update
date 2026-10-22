import 'package:canvas_app/core/services/deep_link_service.dart';
import 'package:canvas_app/core/services/notification_routing.dart';
import 'package:canvas_app/features/forums/screens/forum_lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Маршрут тапа по уведомлению.
///
/// Проверка про пуш-данные: бан и снятый топик бэкенд высылает плашкой, а ни
/// один из трёх клиентских маршрутизаторов их не понимал — тап молчал.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Меню')),
        ),
      ),
    );
  }

  /// На старте стек — одна начальная маршрута, с неё не выбраться; тап по
  /// плашке обязан добавить вторую.
  bool pushed(WidgetTester tester) => navigatorKey.currentState!.canPop();

  testWidgets('бан в сообществе ведёт в лобби этого сообщества', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(pushed(tester), isFalse);

    routeNotificationTap(const {
      'type': 'forum_ban',
      'forumSlug': 'quest-discussion',
    });
    // Первый pump рисует кадр маршрута, второй — уже пост-фрейм колбэк
    // HeroController, который возвращает страницу обратно on-stage: до него
    // страница живёт под Offstage, и find.byType её не видит.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(pushed(tester), isTrue);
    final lobby = tester.widget<ForumLobbyScreen>(
      find.byType(ForumLobbyScreen),
    );
    expect(lobby.slug, 'quest-discussion');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('бан без слага никуда не ведёт', (tester) async {
    await pumpApp(tester);

    routeNotificationTap(const {'type': 'forum_topic_removed'});
    await tester.pump();

    expect(pushed(tester), isFalse);
    expect(find.byType(ForumLobbyScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('неизвестный тип не толкает ни одного маршрута', (tester) async {
    await pumpApp(tester);

    routeNotificationTap(const {'type': 'achievement'});
    await tester.pump();

    expect(pushed(tester), isFalse);

    await tester.pumpWidget(const SizedBox());
  });
}
