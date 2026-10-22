import 'package:canvas_app/features/asset_market/providers/asset_provider.dart';
import 'package:canvas_app/features/hub/screens/hub_screen.dart';
import 'package:canvas_app/features/music_library/providers/music_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Гость, которого онбординг привёл на «Хаб», жал на «Загрузить ресурс» и
// получал форму публикации: отказ приходил только на кнопке «Опубликовать»,
// потому что экрану нужен jwt, которого у гостя нет. Теперь проверка на тапе.
//
// Данные каталога отдаём пустыми оверрайдами: реальный HTTP под FakeAsync не
// дожидается, а бесконечный шиммер вечно вешает pumpAndSettle.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ: убери `if (prefs.getString('jwt_token') == null)` —
// падает «аккаунту открывается форма выбора типа» (диалог лезет всем).
Future<void> _pumpHub(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        filteredAssetProvider.overrideWith((_) async => const []),
        filteredMusicTracksProvider.overrideWith((_) async => const []),
      ],
      child: const MaterialApp(home: HubScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapUpload(WidgetTester tester) async {
  await tester.tap(find.text('Загрузить ресурс'));
  // Кадры вместо pumpAndSettle: у авторизованного вкладка остаётся в
  // «Загрузка…», а бесконечный индикатор никогда не «успокаивается».
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('гость получает объяснение вместо формы публикации', (
    tester,
  ) async {
    await _pumpHub(tester, const {});
    await _tapUpload(tester);

    expect(find.text('Нужен аккаунт'), findsOneWidget);
    expect(find.textContaining('Войдите на вкладке'), findsOneWidget);
    // Форма загрузки не открылась: новичок не тыкается в поля, которые
    // всё равно не примет сервер.
    expect(find.text('Добавить ресурс'), findsNothing);
  });

  testWidgets('аккаунту открывается форма выбора типа', (tester) async {
    await _pumpHub(tester, const {'jwt_token': 'token-123'});
    await _tapUpload(tester);

    expect(find.text('Нужен аккаунт'), findsNothing);
    expect(find.text('Добавить ресурс'), findsOneWidget);
  });
}
