import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/custom_language_store.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

/// Хранилище импортированных языков: файл в каталоге документов и регистрация
/// в `L10n`.
///
/// Проверяем связку «файл ↔ реестр»: импорт обязан пережить перезапуск
/// (`loadAll`), повторный импорт — заменить словарь, а не завести второй
/// «нидерландский», удаление — убрать и файл, и язык из списка, а отказ удалять
/// вшитый язык не должен трогать чужой файл.
void main() {
  late Directory dir;
  late CustomLanguageStore store;
  final usedCodes = <String>{};

  String packJson({
    required String code,
    String name = 'Test',
    Map<String, String> strings = const {'Сохранить': 'Save'},
  }) => jsonEncode({
    'code': code,
    'nativeName': name,
    'strings': strings,  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mnd_languages_');
    store = CustomLanguageStore(root: () async => dir);
  });

  tearDown(() {
    for (final code in usedCodes) {
      L10n.unregister(code);
    }
    usedCodes.clear();
    L10n.setCurrent(L10n.byCode(kSourceLanguageCode));
    dir.deleteSync(recursive: true);
  });

  test('импорт сохраняет файл и добавляет язык в список', () async {
    final pack = await store.importText(packJson(code: 'nl', name: 'Nederlands'));
    usedCodes.add('nl');
    expect(File('${dir.path}/nl.json').existsSync(), isTrue);
    expect(L10n.isCustom('nl'), isTrue);
    expect(L10n.supported.map((language) => language.code), contains('nl'));
    expect(L10n.byCode('nl').nativeName, 'Nederlands');
    // Выбранный язык сразу переводит строки: ради этого пользователь файл
    // и приносит.
    L10n.setCurrent(L10n.byCode('nl'));
    expect(tr('Сохранить'), 'Save');
    expect(pack.stringCount, 1);
  });

  test('повторный импорт того же кода заменяет словарь', () async {
    await store.importText(packJson(code: 'sv', name: 'Svenska'));
    usedCodes.add('sv');
    await store.importText(
      packJson(code: 'sv', name: 'Svenska (2)', strings: const {
        'Сохранить': 'Spara',
        'Отмена': 'Avbryt',
      }),
    );
    // Два «шведских» в списке — пользователь бы не понял, где его правка.
    expect(
      L10n.supported.where((language) => language.code == 'sv'),
      hasLength(1),
    );
    expect(L10n.byCode('sv').nativeName, 'Svenska (2)');
    expect(L10n.byCode('sv').dictionary, {'Сохранить': 'Spara', 'Отмена': 'Avbryt'});
  });

  test('язык переживает перезапуск: loadAll читает каталог', () async {
    await File('${dir.path}/pl.json').writeAsString(packJson(code: 'pl', name: 'Polski'));
    // битый файл и файл с именем вшитого языка
    await File('${dir.path}/broken.json').writeAsString('{');
    await File('${dir.path}/en.json').writeAsString(packJson(code: 'en'));
    usedCodes.add('pl');

    final broken = await store.loadAll();
    expect(broken, ['broken']);
    expect(L10n.isCustom('pl'), isTrue);
    // Вшитый english не переписывается пользовательским файлом: его словарь
    // живёт в репозитории.
    expect(L10n.isCustom('en'), isFalse);
    expect(L10n.byCode('en').dictionary['Сохранить'], 'Save');
  });

  test('пустой каталог — не ошибка', () async {
    expect(await store.loadAll(), isEmpty);
  });

  test('несуществующий каталог — пустой список, каталог создаётся по запросу', () async {
    final missing = CustomLanguageStore(
      root: () async => Directory('${dir.path}/nope/languages'),
    );
    expect(await missing.loadAll(), isEmpty);
    expect(await (await missing.directory()).exists(), isTrue);
  });

  test('удаление убирает файл и язык, вшитый язык не удаляется', () async {
    await store.importText(packJson(code: 'da', name: 'Dansk'));
    usedCodes.add('da');
    expect(await store.remove('da'), isTrue);
    expect(File('${dir.path}/da.json').existsSync(), isFalse);
    expect(L10n.isCustom('da'), isFalse);
    expect(L10n.byCode('da').code, kSourceLanguageCode);

    // Вшитый язык: false — и файл, который человек положил в каталог руками,
    // остаётся на месте.
    await File('${dir.path}/en.json').writeAsString(packJson(code: 'en'));
    expect(await store.remove('en'), isFalse);
    expect(File('${dir.path}/en.json').existsSync(), isTrue);
  });

  test('удаление выбранного языка возвращает интерфейс на русский', () async {
    await store.importText(packJson(code: 'pl', name: 'Polski'));
    usedCodes.add('pl');
    L10n.setCurrent(L10n.byCode('pl'));
    expect(L10n.code, 'pl');
    await store.remove('pl');
    expect(L10n.code, kSourceLanguageCode);
    expect(tr('Сохранить'), 'Сохранить');
  });

  test('шаблон — это валидный JSON со строками словаря', () async {
    final json = jsonDecode(store.templateJson()) as Map<String, Object?>;
    expect(json['code'], 'xx');
    final strings = json['strings']! as Map<String, Object?>;
    // Инвентарь ключей берут из английского словаря, поэтому шаблон заведомо
    // покрывает интерфейс; значения пустые — их заполняет переводчик.
    expect(strings.containsKey('Сохранить'), isTrue);
    expect(strings['Сохранить'], isEmpty);
    expect(store.templateBytes(), equals(utf8.encode(store.templateJson())));
  });
}
