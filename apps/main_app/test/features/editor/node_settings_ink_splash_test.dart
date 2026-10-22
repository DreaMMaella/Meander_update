// «ListTile background color or ink splashes may be invisible» — 718
// срабатываний в `~/Documents/crash_log.txt` за 04–09 октября, самая частая
// повторяющаяся UI-проверка в этом логе. Подпись в дампе одна и та же:
// `BoxDecoration(color: (0.1725, 0.2118, 0.2353), borderRadius: 12.0)` — это
// `scheme.surfaceContainerHighest` и радиус блоков «Фоновое видео» и «Скрыть
// таймер» на экране настроек ноды, внутри которых стояли `SwitchListTile`.
// ListTile красит фон и ripple на ближайшем Material-предке, поэтому краска
// промежуточного Container ложилась поверх: переключатели продолжали работать,
// но нажатие не показывало ни подсветки, ни splash — визуально «ничего не
// произошло».
//
// Здесь держим два инварианта: экран настроек ноды собирается без этого
// assertion (оба блока построены — для нижнего прокручиваем ListView), и
// переключатель после правки остаётся живым.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): вернуть в `node_settings_screen.dart`
// прежние `Container(padding: …, decoration: BoxDecoration(color: …))` вместо
// `Material(color: …, borderRadius: …)` — падает первый тест (`takeException`
// видит фразу про ink splash), и падает весь `node_background_video_fit_test.dart`:
// обработчик, который раньше заглушал эту фразу при открытии экрана, из того
// файла убран — ловить стало нечего. Третий тест характеристический: он
// собирает старую форму локально и требует, чтобы framework ругался именно
// этой фразой, иначе проверка первого теста была бы пустой.

import 'package:canvas_app/features/editor/screens/node_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Открыть экран настроек ноды с выбранным фоновым видео.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const NodeSettingsScreen(
                  questId: 'quest-1',
                  nodeId: 'n1',
                  initialBackgroundId: null,
                  initialBackgroundVideoId: 'intro.mp4',
                  initialBackgroundVideoName: 'Intro',
                  initialVideoVolume: 1,
                  initialVideoLoop: true,
                  initialVideoMuted: false,
                  initialVideoFit: 'cover',
                  initialBackgroundBlur: null,
                  initialAudioId: null,
                  initialAudioVolume: 1,
                  initialItemSpacing: null,
                  initialImageRoundedCorners: null,
                  initialTransitionMode: 'fade',
                  initialTimerEnabled: true,
                  initialTimerHidden: false,
                  initialTimerDurationText: '',
                  initialDefaultActionNodeId: null,
                  initialDefaultActionNodeName: 'Нода не найдена',
                ),
              ),
            ),
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
}

/// …и докрутить ListView до нижнего блока с таймером, чтобы построились обе
/// секции с тайлами: assertion живёт в момент сборки тайла под краской.
Future<void> _openBothTileSections(WidgetTester tester) async {
  await _openSettings(tester);
  await tester.scrollUntilVisible(
    find.text('Скрыть таймер'),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

bool _valueOf(WidgetTester tester, String title) {
  final tile = tester.widget<SwitchListTile>(
    find.ancestor(of: find.text(title), matching: find.byType(SwitchListTile)),
  );
  return tile.value;
}

void main() {
  testWidgets('настройки ноды собираются без «ink splashes may be invisible»', (
    WidgetTester tester,
  ) async {
    await _openBothTileSections(tester);

    expect(
      tester.takeException(),
      isNull,
      reason:
          'цветной Container над SwitchListTile глушит фон и ripple — '
          'см. заголовок файла',
    );
  });

  testWidgets('переключатели в обоих блоках остаются рабочими', (
    WidgetTester tester,
  ) async {
    await _openSettings(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Без звука'));
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'Без звука'), isTrue);

    // ListView выбрасывает за край то, что не вьюпорт, поэтому до нижнего
    // блока нужно доскроллить отдельно.
    await tester.scrollUntilVisible(
      find.text('Скрыть таймер'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скрыть таймер'));
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'Скрыть таймер'), isTrue);

    expect(tester.takeException(), isNull);
  });

  /// Старая форма — Container с краской под тайлом. Тест обязывает framework
  /// ругаться именно этой фразой: без него первый тест мог бы «зеленеть»
  /// и потому, что assertion вообще не срабатывает в тестовой среде.
  testWidgets('краска промежуточного box съедает ink — это и ловим', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2C363C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              title: const Text('Тайл под краской'),
              value: false,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final error = tester.takeException();
    expect(error, isNotNull, reason: 'иначе проверка экрана ничего не стоит');
    expect('$error', contains('ListTile background color'));
  });
}
