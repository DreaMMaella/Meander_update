// «Импортировать .mnd» — вторая по частоты кнопка новичка (первая — «Создать»),
// и первая, где он ошибается: выбирает выгрузку из Ren'Py, текстовик или архив.
// Экран печатал причину как `'$e'`, то есть человек читал снэкбар
// «Ошибка импорта: Exception: Выбран неверный тип файла. Пожалуйста, выберите
// файл с расширением .mnd, .qst или .urq» — полезная фраза тонула в префиксе
// класса, а при отказе `dart:io` — ещё и в дампе с путём.
//
// Здесь держим два инварианта: причина до человека доходит одна строка без
// префикса класса, а отмена выбора файла не оформляется как ошибка.
//
// НЕГАТИВНЫЙ КОНТРОЛЬ (проверено): вернуть в `_importQuest`
// `_showSnack('Ошибка импорта: $e', error: true)` — падает первый тест
// («неверный тип файла»): в снэкбаре появляется `Exception:`. Второй тест
// («отмена — не ошибка») контроля не даёт: он проходит и с откатом, потому что
// держит другое решение — молча отменённый выбор не надо печатать как отказ.

import 'dart:typed_data';

import 'package:canvas_app/features/quests/providers/quest_provider.dart';
import 'package:canvas_app/features/quests/screens/my_quests_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Заглушка пикера: отдаёт заранее подготовленный список, как это сделал бы
/// человек в системном диалоге выбора файла.
class _StubPicker extends FilePickerPlatform {
  _StubPicker(this.picked);

  final List<PlatformFile> picked;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => picked;
}

/// Файл, выбранный «человеком»: сервис смотрит только на путь и расширение.
base class _PickedFile extends PlatformFile {
  _PickedFile(this._path);

  final String _path;

  @override
  String get name => _path.split('/').last;

  @override
  Uri get uri => Uri.file(_path);

  @override
  int? lengthSync() => null;

  @override
  Future<int> length() => throw UnsupportedError(_path);

  @override
  Future<Uint8List> readAsBytes() => throw UnsupportedError(_path);

  @override
  Stream<Uint8List> readAsByteStream() => throw UnsupportedError(_path);

  @override
  Never get xFile => throw UnsupportedError(_path);
}

void main() {
  late FilePickerPlatform realPicker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    realPicker = FilePickerPlatform.instance;
  });

  tearDown(() => FilePickerPlatform.instance = realPicker);

  Future<void> pumpEmptyLibrary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // Пустая библиотека — то состояние, где новичок и жмёт «Импорт».
        overrides: [questsProvider.overrideWith((ref) async => [])],
        child: MaterialApp(home: const MyQuestsScreen(isRoot: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pickAndImport(WidgetTester tester, String path) async {
    FilePickerPlatform.instance = _StubPicker([_PickedFile(path)]);
    final button = find.text('Импортировать .mnd');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('неверный тип файла — фраза сервиса, а не Exception:', (
    WidgetTester tester,
  ) async {
    await pumpEmptyLibrary(tester);
    await pickAndImport(tester, '/tmp/обложка.txt');

    expect(
      find.textContaining('Выбран неверный тип файла'),
      findsOneWidget,
      reason: 'новичок должен понять, что именно он выбрал не так',
    );
    expect(find.byType(SnackBar), findsOneWidget);
    final snackText = tester.widget<SnackBar>(find.byType(SnackBar)).content;
    final shown = (snackText as Text).data!;
    expect(shown, isNot(contains('Exception')));
    expect(shown, isNot(contains('\n')));
    expect(shown, startsWith('Ошибка импорта: '));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('отмена выбора файла не оформляется как ошибка', (
    WidgetTester tester,
  ) async {
    await pumpEmptyLibrary(tester);
    // Пустой список — так выглядит «закрыл диалог».
    FilePickerPlatform.instance = _StubPicker(const []);
    final button = find.text('Импортировать .mnd');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
