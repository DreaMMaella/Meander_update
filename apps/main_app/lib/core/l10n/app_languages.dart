import 'app_language.dart';
import 'dictionaries/ar.dart';
import 'dictionaries/de.dart';
import 'dictionaries/en.dart';
import 'dictionaries/es.dart';
import 'dictionaries/fr.dart';
import 'dictionaries/hi.dart';
import 'dictionaries/it.dart';
import 'dictionaries/ja.dart';
import 'dictionaries/ko.dart';
import 'dictionaries/pt_br.dart';
import 'dictionaries/tr.dart';
import 'dictionaries/zh_cn.dart';

/// Русский — язык-источник: строки приложения написаны по-русски, словарь ему
/// не нужен (промах по словарю = русский оригинал).
const AppLanguage sourceLanguage = AppLanguage(
  code: kSourceLanguageCode,
  nativeName: 'Русский',
  englishName: 'Russian',
  pluralOf: slavicPlural,
);

final AppLanguage english = AppLanguage(
  code: 'en',
  nativeName: 'English',
  englishName: 'English',
  dictionary: enStrings,
  plurals: enPlurals,
);

/// Живые языки: недопереведённое добирают у английского (`fallbackCode`),
/// поэтому словарь можно наполнять по частям и на экране не появляется
/// кириллица среди немецких подписей.
///
/// Правило числа (`pluralOf`) — часть языка, а не перевода: список форм в
/// словаре обязан иметь ровно столько элементов, сколько индексов у правила.
/// `otherOnly` (китайский, японский, корейский) — одна форма, `arabicPlural`
/// — шесть в порядке ноль/один/два/немного/много/прочее.
final List<AppLanguage> supportedLanguages = [
  sourceLanguage,
  english,
  AppLanguage(
    code: 'zh-CN',
    nativeName: '简体中文',
    englishName: 'Chinese (Simplified)',
    dictionary: zhCnStrings,
    plurals: zhCnPlurals,
    pluralOf: otherOnly,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'ja',
    nativeName: '日本語',
    englishName: 'Japanese',
    dictionary: jaStrings,
    plurals: jaPlurals,
    pluralOf: otherOnly,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'de',
    nativeName: 'Deutsch',
    englishName: 'German',
    dictionary: deStrings,
    plurals: dePlurals,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'es',
    nativeName: 'Español',
    englishName: 'Spanish',
    dictionary: esStrings,
    plurals: esPlurals,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'pt-BR',
    nativeName: 'Português (Brasil)',
    englishName: 'Portuguese (Brazil)',
    dictionary: ptBrStrings,
    plurals: ptBrPlurals,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'fr',
    nativeName: 'Français',
    englishName: 'French',
    dictionary: frStrings,
    plurals: frPlurals,
    pluralOf: moreThanOne,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'it',
    nativeName: 'Italiano',
    englishName: 'Italian',
    dictionary: itStrings,
    plurals: itPlurals,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'ko',
    nativeName: '한국어',
    englishName: 'Korean',
    dictionary: koStrings,
    plurals: koPlurals,
    pluralOf: otherOnly,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'hi',
    nativeName: 'हिन्दी',
    englishName: 'Hindi',
    dictionary: hiStrings,
    plurals: hiPlurals,
    pluralOf: moreThanOne,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'tr',
    nativeName: 'Türkçe',
    englishName: 'Turkish',
    dictionary: trStrings,
    plurals: trPlurals,
    fallbackCode: 'en',
  ),
  AppLanguage(
    code: 'ar',
    nativeName: 'العربية',
    englishName: 'Arabic',
    dictionary: arStrings,
    plurals: arPlurals,
    pluralOf: arabicPlural,
    fallbackCode: 'en',
  ),
];
