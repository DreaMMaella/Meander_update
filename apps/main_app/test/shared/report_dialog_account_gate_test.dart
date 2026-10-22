import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/shared/widgets/report_dialog.dart';

/// Живая сеть в тесте не нужна: важно, что гость не отправляет POST /reports,
/// а видит объяснение. Подмёнка считает вызовы и всегда падает как сервер без
/// сессии.
class _RecordingApi extends ApiService {
  int reportCalls = 0;

  @override
  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    if (endpoint == 'reports') reportCalls++;
    throw Exception('Unauthorized: {"error":"jwt must be provided"}');
  }
}

Future<_RecordingApi> _openReportDialog(
  WidgetTester tester,
  Map<String, Object> prefs,
) async {
  // Диалог с шестью радиокнопками и полем не влезает в тестовые 800x600 —
  // flutter_test падает на переполнении, а не на проверке.
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final api = _RecordingApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiServiceProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: const ReportDialog(
            reportedType: 'quest',
            reportedId: 'quest-1',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return api;
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Спам'));
  await tester.pump();
  await tester.tap(find.text('Отправить'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('гость не отправляет жалобу в никуда, а получает объяснение', (
    tester,
  ) async {
    final api = await _openReportDialog(tester, const {});
    await _submit(tester);

    expect(api.reportCalls, 0);
    expect(find.text('Нужен аккаунт'), findsOneWidget);
    expect(find.textContaining('Жалобы разбирает модерация'), findsOneWidget);
    expect(find.textContaining('Unauthorized'), findsNothing);
  });

  testWidgets('с аккаунтом жалоба уходит на сервер', (tester) async {
    final api = await _openReportDialog(
      tester,
      const {'jwt_token': 'token-123'},
    );
    await _submit(tester);

    expect(api.reportCalls, 1);
    expect(find.text('Нужен аккаунт'), findsNothing);
  });
}
