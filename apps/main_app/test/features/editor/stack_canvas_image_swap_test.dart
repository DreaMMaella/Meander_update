// Смена картинки у слоя стека: «Сменить» открывает пикер ресурсов квеста,
// выбор пишется одним шагом истории (undo возвращает старый файл), отмена не
// создаёт шага вообще. Контрол показывается только у слоя-картинки.

import 'dart:io';

import 'package:canvas_app/features/editor/screens/node_content/stack_canvas/stack_canvas_screen.dart';
import 'package:canvas_app/features/resources/screens/resource_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

/// Слой с формулой-источником рендерит картинку через Rust-ядро, поэтому
/// этому тесту нужен собранный `.so`.
final String? _soPath = () {
  final env = Platform.environment['MND_FFI_SO'];
  if (env != null && File(env).existsSync()) return env;
  for (final candidate in [
    '../../crates/mnd-ffi/target/release/libmnd_ffi.so',
    '../../target/release/libmnd_ffi.so',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}();

ContentItem _imageChild({String path = 'res/images/old.png', String? expr}) =>
  ContentItem(
    id: 'img',
    type: 'image',
    resourcePath: path,
    resourceExpr: expr,
    anchorLeft: 0,
    anchorTop: 0,
    anchorRight: 0,
    anchorBottom: 0,
    offsetLeft: 16,
    offsetTop: 8,
    offsetRight: 116,
    offsetBottom: 48,
  );

ContentItem _textChild() => ContentItem(
  id: 'txt',
  type: 'text',
  text: 'привет',
  anchorLeft: 0,
  anchorTop: 0,
  anchorRight: 0,
  anchorBottom: 0,
  offsetLeft: 16,
  offsetTop: 8,
  offsetRight: 116,
  offsetBottom: 48,
);

ContentItem _stack(ContentItem child) => ContentItem(
  id: 'stack-1',
  type: 'stack',
  stackHeight: 240,
  children: [child],
);

PhysicalKeyboardKey? physOf(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.controlLeft) {
    return PhysicalKeyboardKey.controlLeft;
  }
  return null;
}

void main() {
  late List<ContentItem> saved;

  setUpAll(() async {
    if (_soPath != null) {
      await initRustCore(externalLibrary: ExternalLibrary.open(_soPath!));
    }
  });

  Future<void> pumpCanvas(WidgetTester tester, ContentItem child) async {
    saved = [];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StackCanvasScreen(
            stackItem: _stack(child),
            questId: 'q-images',
            nodeId: 'n-test',
            onAutoSave: (payload) async {
              saved.add(payload['item']! as ContentItem);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    final ctrl = LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(ctrl, physicalKey: physOf(ctrl));
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(ctrl, physicalKey: physOf(ctrl));
    await tester.pump();
  }

  Future<void> openPropsSheet(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.keyA);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
  }

  /// Тап по «Сменить» и ответ пикера. `null` — пользователь вышел без выбора.
  Future<void> answerPicker(WidgetTester tester, String? path) async {
    // Шит свойств стал длиннее (пресеты якорей) — кнопку может не быть в
    // вьюпорте 800×600, поэтому подводим скролл перед тапом.
    await tester.ensureVisible(find.text('Сменить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сменить'));
    // Пикер грузит библиотеку реальным IO, а pumpAndSettle ждал бы вечного
    // спиннера — поэтому один кадр и сразу ответ маршруту.
    await tester.pump();
    expect(find.byType(ResourceSelectionScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(ResourceSelectionScreen))).pop(
      path == null
          ? null
          : SelectableResource(
              path: path,
              name: path.split('/').last,
              friendlyName: path.split('/').last,
              type: 'image',
            ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('слой-картинка даёт «Сменить» и помнит текущий файл', (
    tester,
  ) async {
    await pumpCanvas(tester, _imageChild());
    await openPropsSheet(tester);

    expect(find.text('Изображение'), findsOneWidget);
    expect(find.text('old.png'), findsOneWidget);
    expect(find.text('Сменить'), findsOneWidget);
  });

  testWidgets('выбор новой картинки — один шаг истории и он отменяется', (
    tester,
  ) async {
    await pumpCanvas(tester, _imageChild());
    await openPropsSheet(tester);
    await answerPicker(tester, 'res/images/new.png');

    expect(saved.last.children!.single.resourcePath, 'res/images/new.png');
    expect(find.text('new.png'), findsOneWidget, reason: 'шит показывает файл');

    await tester.tapAt(const Offset(400, 10));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyZ);
    expect(saved.last.children!.single.resourcePath, 'res/images/old.png');
  });

  testWidgets('отмена выбора не правит документ', (tester) async {
    await pumpCanvas(tester, _imageChild());
    await openPropsSheet(tester);
    await answerPicker(tester, null);

    expect(saved, isEmpty);
    expect(find.text('old.png'), findsOneWidget);
  });

  testWidgets('у текстового слоя строки изображения нет', (tester) async {
    await pumpCanvas(tester, _textChild());
    await openPropsSheet(tester);

    expect(find.text('Изображение'), findsNothing);
    expect(find.text('Сменить'), findsNothing);
  });

  testWidgets(
    'выбор файла снимает привязку источника к формуле',
    (tester) async {
      await pumpCanvas(tester, _imageChild(expr: '{pic}'));
      await openPropsSheet(tester);
      await answerPicker(tester, 'res/images/new.png');

      // Пока формула живёт, resolveResourcePath отдаёт её значение — и
      // картинка на канвасе не менялась бы вовсе.
      final child = saved.last.children!.single;
      expect(child.resourcePath, 'res/images/new.png');
      expect(child.resourceExpr, isNull);
      expect(
        child.resolveResourcePath(evaluatedExpr: 'res/images/old.png'),
        'res/images/new.png',
      );
    },
    skip: _soPath == null,
  );
}
