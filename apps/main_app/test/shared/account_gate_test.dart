import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/shared/dialogs/account_gate.dart';

/// Возвращает результат гейта после тапа; попутно даёт тестам кадры, чтобы
/// диалог успел отрисоваться.
Future<bool> _tapGate(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  bool? allowed;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => allowed = await ensurePublishAccount(context),
          child: const Text('action'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('action'));
  // Кадры вместо pumpAndSettle: result остаётся null, пока диалог открыт, а
  // бесконечных индикаторов здесь нет — но settling всё равно дороже кадров.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return allowed ?? false;
}

void main() {
  testWidgets('гость: действие блокируется, а reason виден на экране', (
    tester,
  ) async {
    final allowed = await _tapGate(tester, const {});

    expect(allowed, isFalse);
    expect(find.text('Нужен аккаунт'), findsOneWidget);
    expect(find.textContaining('Войдите на вкладке'), findsOneWidget);
  });

  testWidgets('с авторизованной сессией: гейт не мешает', (tester) async {
    final allowed = await _tapGate(
      tester,
      const {'jwt_token': 'token-123'},
    );

    expect(allowed, isTrue);
    expect(find.text('Нужен аккаунт'), findsNothing);
  });

  testWidgets('истёкшая сессия: пустой jwt_token не считается входом', (
    tester,
  ) async {
    final allowed = await _tapGate(tester, const {'jwt_token': ''});

    expect(allowed, isFalse);
    expect(find.text('Нужен аккаунт'), findsOneWidget);
  });

  testWidgets('ensureAccount подставляет текст под конкретное действие', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    bool? allowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => allowed = await ensureAccount(
              context,
              why: 'Оценивать чужие треки могут авторы с аккаунтом.',
            ),
            child: const Text('action'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('action'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Пока объяснение открыто, future гейта не завершён — поэтому `?? false`:
    // проверяем, что действие НЕ разрешили и текст соответствует действию.
    expect(allowed ?? false, isFalse);
    expect(find.text('Нужен аккаунт'), findsOneWidget);
    expect(find.textContaining('Оценивать чужие треки'), findsOneWidget);
  });
}
