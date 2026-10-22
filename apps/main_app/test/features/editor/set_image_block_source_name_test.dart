// Блок «Сменить картинку» в скрипте показывает имя картинки из библиотеки,
// а не `1790009583255_<uuid>.png`: автор выбирает кадр глазами и по имени,
// которым он его назвал при загрузке. Формулу (`{pic}`) оставляем как
// написана — подменить её подписью нельзя, значение известно только движку.

import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/widgets/set_image_block_widget.dart';
import 'package:canvas_app/features/resources/services/resource_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _uuidFile =
    '1790009583255_0d202795-7499-4abc-8f5a-d861150a7662.png';
const String _friendly = 'Одинокое дерево';

void main() {
  Future<SetImageBlock> pump(WidgetTester tester, String source) async {
    final block = SetImageBlock(itemId: 'photo', source: source);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          questResourceNamesProvider(
            'q1',
          ).overrideWith((ref) async => {_uuidFile: _friendly}),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SetImageBlockWidget(block: block, questId: 'q1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return block;
  }

  testWidgets('путь к картинке подписан её именем из библиотеки', (
    tester,
  ) async {
    await pump(tester, 'res/images/$_uuidFile');

    expect(find.text(_friendly), findsOneWidget);
    expect(find.text(_uuidFile), findsNothing);
  });

  testWidgets('формула показывается как написана', (tester) async {
    await pump(tester, '{настроение}');

    expect(find.text('{настроение}'), findsOneWidget);
  });

  testWidgets('неизвестный файл остаётся как есть', (tester) async {
    await pump(tester, 'res/images/нет_в_библиотеке.png');

    expect(find.text('res/images/нет_в_библиотеке.png'), findsOneWidget);
  });

  testWidgets('источник в блоке не меняется из-за подписи', (tester) async {
    final block = await pump(tester, 'res/images/$_uuidFile');

    expect(block.source, 'res/images/$_uuidFile');
    expect(block.toJson()['source'], 'res/images/$_uuidFile');
  });
}
