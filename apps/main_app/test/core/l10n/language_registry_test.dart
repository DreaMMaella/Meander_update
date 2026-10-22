import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

/// Реестр импортированных языков внутри `L10n`.
///
/// Файл хранит `CustomLanguageStore`, а здесь живёт список языков, который
/// видят настройки и `MaterialApp`. Опасны два места: вшитый язык нельзя
/// переопределить пользовательским (иначе «английский» станет два, и
/// неизвестно, чей словарь побеждает), и замена текущего языка обязана
/// позвать слушателей (иначе человек правит перевод, а экраны остаются со
/// старыми строками).
///
/// Коды пользовательских языков взяты вне реестра (`nl`, `sv`, `pl`, `da`):
/// живые языки интерфейса теперь вшиты, и `register` на них молча не срабатывает.
void main() {
  const builtinCount = 13; // ru + en + 11 живых языков в `app_languages.dart`
  final added = <String>[];

  AppLanguage custom(String code, {String name = 'Test', int version = 1}) =>
      AppLanguage(
        code: code,
        nativeName: '$name v$version',
        englishName: code,
        dictionary: {'Сохранить': 'save-v$version'},
        custom: true,
      );

  tearDown(() {
    for (final code in added) {
      L10n.unregister(code);
    }
    added.clear();
    L10n.setCurrent(L10n.byCode(kSourceLanguageCode));
  });

  test('вшитый язык подменить нельзя', () {
    L10n.register(custom('en', name: 'English', version: 9));
    expect(L10n.isCustom('en'), isFalse);
    // Словарь остаётся репозиторный: иначе перевод из файла победил бы
    // перевод, который проверяет гард и видит `MaterialApp`.
    expect(L10n.byCode('en').dictionary['Сохранить'], 'Save');
    expect(L10n.byCode('en').nativeName, 'English');

    // Тот же контроль на живом языке: их одиннадцать, и каждый вшит.
    L10n.register(custom('de', name: 'Deutsch', version: 9));
    expect(L10n.isCustom('de'), isFalse);
    expect(L10n.byCode('de').nativeName, 'Deutsch');
    expect(L10n.supported.where((l) => l.code == 'de'), hasLength(1));
  });

  test('непользовательский язык — ошибка, а не тихий вход в список', () {
    expect(
      () => L10n.register(
        const AppLanguage(
          code: 'nl',
          nativeName: 'Nederlands',
          englishName: 'Dutch',
        ),
      ),
      throwsArgumentError,
    );
    expect(L10n.isCustom('nl'), isFalse);
  });

  test('импорт добавляет язык в конец списка и позволяет выбрать его', () {
    final before = L10n.supported.length;
    L10n.register(custom('nl'));
    added.add('nl');
    expect(L10n.supported.length, before + 1);
    expect(L10n.supported.last.code, 'nl');
    L10n.setCurrent(L10n.byCode('nl'));
    expect(L10n.code, 'nl');
    expect(tr('Сохранить'), 'save-v1');
  });

  test('перезапись текущего языка обновляет словарь и зовёт слушателей', () {
    L10n.register(custom('sv'));
    added.add('sv');
    L10n.setCurrent(L10n.byCode('sv'));
    var notified = 0;
    void listener() => notified++;
    L10n.addListener(listener);
    try {
      // Тот же код, выбранный язык, новый файл: `setCurrent` промолчит по
      // определению, извещение обязано идти от `register`.
      L10n.register(custom('sv', version: 2));
      expect(notified, 1);
      expect(L10n.current.nativeName, 'Test v2');
      expect(tr('Сохранить'), 'save-v2');
      expect(
        L10n.supported.where((language) => language.code == 'sv'),
        hasLength(1),
      );
    } finally {
      L10n.removeListener(listener);
    }
  });

  test('перезапись не выбранного языка слушателей не трогает', () {
    L10n.register(custom('pl'));
    added.add('pl');
    var notified = 0;
    void listener() => notified++;
    L10n.addListener(listener);
    try {
      L10n.register(custom('pl', version: 2));
      expect(notified, 0);
    } finally {
      L10n.removeListener(listener);
    }
  });

  test('удаление убирает язык, а с выбранным возвращает на русский', () {
    expect(L10n.unregister('zz'), isFalse);
    expect(L10n.unregister('en'), isFalse, reason: 'вшитый язык не удаляется');
    expect(L10n.unregister('ar'), isFalse, reason: 'живой язык не удаляется');

    L10n.register(custom('da'));
    L10n.setCurrent(L10n.byCode('da'));
    var notified = 0;
    void listener() => notified++;
    L10n.addListener(listener);
    try {
      expect(L10n.unregister('da'), isTrue);
      expect(notified, 1);
      expect(L10n.code, kSourceLanguageCode);
      expect(L10n.isCustom('da'), isFalse);
      expect(tr('Сохранить'), 'Сохранить');
    } finally {
      L10n.removeListener(listener);
    }
  });

  test('вшитые языки не помечаются пользовательскими', () {
    expect(L10n.supported.first.code, kSourceLanguageCode);
    for (final language in L10n.supported.take(builtinCount)) {
      expect(language.custom, isFalse, reason: language.code);
    }
  });
}
