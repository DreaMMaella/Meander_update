// Подгонка фонового видео (`backgroundVideoFit`) есть в модели, её читает
// плеер (`_videoFitOf` в game_screen.dart) и сериализует Rust-ядро, но
// экран настроек ноды это поле никогда не возвращал — значение достигало
// квеста только через ручную правку JSON. Тест держит границу «экран →
// результат», из которой node_content_screen пишет поле в ноду.

import 'package:canvas_app/features/editor/screens/node_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpSettings(
  WidgetTester tester, {
  required String initialFit,
  required void Function(NodeSettingsResult? result) onPop,
}) async {
  // Раньше здесь ещё стоял обработчик, глушивший «ListTile background color or
  // ink splashes may be invisible»: блоки настроек видео висели над цветным
  // Container, который съедал их фон и ripple. Экран починен (Material вместо
  // краски), заглушка убрана — пусть assertion опять падает на тест, если
  // краска вернётся.

  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              Navigator.push<NodeSettingsResult>(
                context,
                MaterialPageRoute(
                  builder: (_) => NodeSettingsScreen(
                    questId: 'quest-1',
                    nodeId: 'n1',
                    initialBackgroundId: null,
                    initialBackgroundVideoId: 'intro.mp4',
                    initialBackgroundVideoName: 'Intro',
                    initialVideoVolume: 1,
                    initialVideoLoop: true,
                    initialVideoMuted: true,
                    initialVideoFit: initialFit,
                    initialBackgroundBlur: null,
                    initialAudioId: null,
                    initialAudioVolume: 1,
                    initialItemSpacing: null,
                    initialImageRoundedCorners: null,
                    initialTransitionMode: 'fade',
                    initialTimerEnabled: false,
                    initialTimerHidden: false,
                    initialTimerDurationText: '',
                    initialDefaultActionNodeId: null,
                    initialDefaultActionNodeName: 'Нода не найдена',
                  ),
                ),
              ).then(onPop);
            },
            child: const Text('открыть'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('вписывание фонового видео выбирается и уезжает в результат', (
    WidgetTester tester,
  ) async {
    NodeSettingsResult? popped;
    await pumpSettings(tester, initialFit: 'cover', onPop: (r) => popped = r);

    // Секция настроек видео показывается только при выбранном ролике.
    expect(find.text('Cover — заполнить, край срежется'), findsOneWidget);

    await tester.tap(find.text('Cover — заполнить, край срежется'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contain — целиком, с полями').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(popped, isNotNull, reason: 'экран обязан вернуть результат');
    expect(popped!.videoFit, 'contain');
    // Остальные поля не должны пострадать от добавления нового.
    expect(popped!.backgroundVideoAssetId, 'intro.mp4');
    expect(popped!.videoMuted, isTrue);
  });

  testWidgets('чужое значение читается из ноды и не теряется без правки', (
    WidgetTester tester,
  ) async {
    NodeSettingsResult? popped;
    await pumpSettings(tester, initialFit: 'fill', onPop: (r) => popped = r);

    expect(find.text('Fill — растянуть по экрану'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(popped!.videoFit, 'fill');
  });
}
