// Слой-картинка подписан именем из библиотеки квеста, а не именем файла.
// Загруженные картинки называются `1790009583255_<uuid>.png` — по такому
// хвосту автор не отличит один кадр от другого, а именно эти подписи он
// читает в панели слоёв и в свойствах слоя.

import 'package:canvas_app/features/editor/screens/node_content/stack_canvas/stack_canvas_screen.dart';
import 'package:canvas_app/features/resources/services/resource_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/models/content_item.dart';

const String _uuidFile =
    '1790009583255_0d202795-7499-4abc-8f5a-d861150a7662.png';
const String _uuidPath = 'res/images/$_uuidFile';
const String _friendly = 'Одинокое дерево';

ContentItem _imageLayer({String path = _uuidPath}) => ContentItem(
  id: 'img',
  type: 'image',
  resourcePath: path,
  anchorLeft: 0,
  anchorTop: 0,
  anchorRight: 0,
  anchorBottom: 0,
  offsetLeft: 16,
  offsetTop: 8,
  offsetRight: 116,
  offsetBottom: 48,
);

ContentItem _stack() => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [_imageLayer()],
);

void main() {
  Future<void> pumpCanvas(
    WidgetTester tester,
    Map<String, String> names,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        // Имена приходят из metadata квеста; в тесте отдаём их напрямую,
        // чтобы проверять подпись, а не чтение диска.
        overrides: [
          questResourceNamesProvider(
            'q-names',
          ).overrideWith((ref) async => names),
        ],
        child: MaterialApp(
          home: StackCanvasScreen(
            stackItem: _stack(),
            questId: 'q-names',
            nodeId: 'n-test',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  /// Шит свойств выделенного слоя: Ctrl+A — выделить всё, затем «настройки».
  Future<void> openPropsSheet(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.keyA);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('панель слоёв подписывает картинку именем из библиотеки', (
    tester,
  ) async {
    await pumpCanvas(tester, {_uuidFile: _friendly});

    await tester.tap(
      find.byTooltip(
        'Панель слоёв: z-порядок (долгое нажатие на строку), '
        'видимость, замок, выбор',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(_friendly), findsOneWidget);
    expect(find.text(_uuidFile), findsNothing);
  });

  testWidgets('в свойствах слоя — то же имя', (tester) async {
    await pumpCanvas(tester, {_uuidFile: _friendly});
    await openPropsSheet(tester);

    expect(find.text(_friendly), findsOneWidget);
    expect(find.text(_uuidFile), findsNothing);
  });

  testWidgets('без имени в библиотеке остаётся файл, а не пустота', (
    tester,
  ) async {
    await pumpCanvas(tester, {'other.png': _friendly});
    await openPropsSheet(tester);

    expect(find.text(_uuidFile), findsOneWidget);
    expect(find.text(_friendly), findsNothing);
  });
}
