// «Мои публикации» — экран автора: что он выложил и в каком статусе. Когда
// список не сошёл (нет сети, сервер на обслуживании, сессия просрочена), экран
// печатал `'$err'` как есть и не предлагал ничего: `SocketException: Failed to
// connect host = vps…, port = 443 (Connection refused), errno = 111` и ни одной
// кнопки. Оставался только скрытый pull-to-refresh: на экране про него нет ни
// строки, и человек до него не додумывается — читает это как «Meander сломан».
//
// Здесь держим два инварианта: причина свёрнута в человеческую фразу рядом с
// рабочей «Повторить», и эта кнопка выводит из ошибки в данные, а не
// перерисовывает тот же трейс.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): вернуть в ветку `error:` прежний
// `Text('Ошибка загрузки: $err')` без кнопки — падают оба теста файла: первый
// не находит заголовок и видит `errno`, второй не находит `my-pubs-retry` и
// считает один вызов провайдера вместо двух.

import 'dart:io';

import 'package:canvas_app/features/profile/providers/profile_provider.dart';
import 'package:canvas_app/features/profile/screens/my_publications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpPubs(WidgetTester tester, List<Override> overrides) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: MyPublicationsScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_id': 'u-1'}));

  testWidgets('нет сети — причина и кнопка, а не трассировка', (
    WidgetTester tester,
  ) async {
    var runs = 0;
    await _pumpPubs(tester, [
      userPublicationsProvider.overrideWith((ref, userId) async {
        runs++;
        throw const SocketException('Connection refused');
      }),
    ]);

    expect(find.text('Публикации не загрузились'), findsOneWidget);
    expect(find.text('Нет соединения с сервером'), findsOneWidget);
    expect(
      find.textContaining('errno'),
      findsNothing,
      reason: 'на экране дамп dart:io вместо причины',
    );
    expect(find.textContaining('SocketException'), findsNothing);
    expect(runs, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('«Повторить» перевызывает и выводит из ошибки', (
    WidgetTester tester,
  ) async {
    var runs = 0;
    await _pumpPubs(tester, [
      userPublicationsProvider.overrideWith((ref, userId) async {
        runs++;
        if (runs == 1) throw const SocketException('Connection refused');
        return [];
      }),
    ]);

    expect(find.text('Публикации не загрузились'), findsOneWidget);

    final retry = find.byKey(const Key('my-pubs-retry'));
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runs, 2, reason: '«Повторить» не перезапустила загрузку списка');
    expect(
      find.text('Публикации не загрузились'),
      findsNothing,
      reason: 'кнопка не вывела из ветки ошибки',
    );
    expect(find.text('Вы ещё ничего не публиковали'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
