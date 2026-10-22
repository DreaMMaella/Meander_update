import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;

/// Код языка-источника: все строки в коде написаны по-русски, он же резервный
/// при неизвестном коде в настройках.
const String kSourceLanguageCode = 'ru';

/// Код языка для Material-обвески, когда собственного словаря Material нет.
const Locale kFallbackMaterialLocale = Locale('en');

/// Правило выбора формы множественного числа языка: по количеству возвращает
/// индекс формы в списке словаря.
typedef PluralSelector = int Function(int count);

/// «одно/много» как в английском и немецком: форма 1 только для ±1.
int oneOrMany(int count) => count.abs() == 1 ? 0 : 1;

/// «одно/много» как во французском и испанском: 0 и 1 — единственное.
int moreThanOne(int count) => count.abs() <= 1 ? 0 : 1;

/// Одна форма на все случаи: китайский, японский и корейский не меняют слово
/// по количеству. Список формы в словаре обязан быть из одного элемента —
/// иначе `pluralOf` никогда не дойдёт до второй.
int otherOnly(int count) => 0;

/// Арабское правило: ноль / один / два / немного (3–10) / много (11–99) /
/// остальное. Порядок форм в словаре — ровно этот.
int arabicPlural(int count) {
  final n = count.abs();
  if (n == 0) return 0;
  if (n == 1) return 1;
  if (n == 2) return 2;
  final mod100 = n % 100;
  if (mod100 >= 3 && mod100 <= 10) return 3;
  if (mod100 >= 11 && mod100 <= 99) return 4;
  return 5;
}

/// Восточнославянское правило (русский, украинский, белорусский): одна /
/// мало / много. Порядок форм в слове `[минута, минуты, минут]`.
int slavicPlural(int count) {
  final n = count.abs();
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 2;
  return switch (n % 10) {
    1 => 0,
    2 || 3 || 4 => 1,
    _ => 2,
  };
}

/// Импортные имена правила числа — те же, что пишутся в JSON языкового
/// пакета. Новое правило = одна строка здесь, и оно становится доступно
/// пользователям без пересборки приложения под каждый язык.
const Map<String, PluralSelector> kPluralRules = {
  'one_other': oneOrMany,
  'zero_one_other': moreThanOne,
  'other_only': otherOnly,
  'arabic': arabicPlural,
  'slavic': slavicPlural,
};

/// Язык интерфейса = код + самоназвание + словарь-надстройка над русским.
///
/// Русский — язык-источник: все строки в коде написаны по-русски и служат
/// ключом перевода. Проммах по словарю идёт в `fallbackCode` (для импортированных
/// живых языков — английский), и только затем остаётся русский оригинал,
/// поэтому язык можно наполнять по частям, а новый язык добавляется одним
/// файлом словаря + одной строкой в реестре `app_languages.dart`.
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.nativeName,
    required this.englishName,
    this.dictionary = const <String, String>{},
    this.plurals = const <String, List<String>>{},
    this.pluralOf = oneOrMany,
    this.fallbackCode,
    this.custom = false,
  });

  /// ISO-639-1, при необходимости с регионом (`pt-BR`).
  final String code;

  /// Название на языке самого языка — так своё имя можно узнать, какой бы
  /// язык интерфейса ни был выбран.
  final String nativeName;

  /// Название по-английски: для логов, тестов и отладки.
  final String englishName;

  /// Русская строка -> перевод.
  final Map<String, String> dictionary;

  /// Формы множественного числа: lemma русской формы (первая в `trp`) ->
  /// список форм языка в порядке его `pluralOf`.
  final Map<String, List<String>> plurals;

  final PluralSelector pluralOf;

  /// Код языка, чей словарь добирает промахи этого. Пустое значение в
  /// переводе считается промахом: недопереведённая строка не должна показывать
  /// кириллицу. `null` — промах остаётся русским (так ведёт себя английский).
  final String? fallbackCode;

  /// Язык пришёл не из реестра `app_languages.dart`, а импортирован пользователем.
  /// Только такие языки можно удалить из настроек.
  final bool custom;

  /// `Locale('pt-BR')` — это languageCode `pt-BR`, и словарь Material на такой
  /// паре не находится. Регион отдаём отдельным аргументом.
  Locale get locale {
    final dash = code.indexOf('-');
    return dash < 0
        ? Locale(code)
        : Locale(code.substring(0, dash), code.substring(dash + 1));
  }

  /// Locale для `MaterialApp`. flutter_localizations знает конечный список
  /// языков: на коде вроде `eo` словарь Material не находится, и любой
  /// `MaterialLocalizations.of` бросает «No MaterialLocalizations found» —
  /// тот самый краш, что уже ловился живым запуском. Поэтому обвеске отдаём
  /// английский, а собственные строки `tr()` продолжают брать наш словарь.
  Locale get materialLocale =>
      GlobalMaterialLocalizations.delegate.isSupported(locale)
      ? locale
      : kFallbackMaterialLocale;
}
