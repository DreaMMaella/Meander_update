import 'dart:convert';

import 'app_language.dart';

// Языковой пакет, который пользователь импортирует из настроек: JSON со
// словарём «русская строка -> перевод».
//
// Формат:
// ```json
// {
//   "formatVersion": 1,
//   "code": "de",
//   "nativeName": "Deutsch",
//   "englishName": "German",
//   "pluralRule": "one_other",
//   "strings": {"Сохранить": "Speichern"},
//   "plurals": {"минута": ["Minute", "Minuten"]}
// }
// ```
//
// Пакет не обязан быть полным: промах по строке означает «осталась русская»,
// поэтому перевод можно выкладывать по частям и править на живом интерфейсе.

/// Версия формата, которую читает это приложение.
const int kLanguagePackFormatVersion = 1;

/// Разумный предел: файл на десятки мегабайт — это не перевод интерфейса, а
/// ошибка или чужой формат.
const int kLanguagePackMaxBytes = 8 * 1024 * 1024;
const int kLanguagePackMaxStrings = 30000;

/// Пустая форма числа в шаблоне: столько же, сколько у правила `one_other`.
const int kLanguagePackTemplatePluralForms = 2;

/// Почему пакет не подошёл. Текст для человека подбирает экран импорта:
/// ядро перевода гард-сканер не разбирает (`lib/core/l10n/` исключён), поэтому
/// завёрнутые в `tr()` строки остались бы без проверки на мёртвый ключ.
enum LanguagePackIssue {
  tooLarge,
  notJson,
  notObject,
  unknownVersion,
  missingCode,
  badCode,
  duplicateCode,
  missingName,
  unknownPluralRule,
  nothingTranslated,
  tooManyStrings,
}

/// Ошибка с кодом причины: её показывают в диалоге импорта.
class LanguagePackException implements Exception {
  LanguagePackException(this.issue, {this.detail = ''});

  final LanguagePackIssue issue;

  /// Что именно не подошло: версия формата, код языка, имя правила числа.
  final String detail;

  @override
  String toString() =>
      'LanguagePackException(${issue.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// Разобранный пакет: язык плюс список пропущенных записей.
class LanguagePack {
  LanguagePack({required this.language, required this.skipped});

  final AppLanguage language;

  /// Что не удалось взять и почему — показывать счётчиком, а не молча.
  final List<String> skipped;

  int get stringCount => language.dictionary.length;

  int get pluralCount => language.plurals.length;
}

/// Код языка: строчные ISO-639 с опциональным регионом (`pt`, `pt-BR`).
final RegExp _codePattern = RegExp(r'^[a-z]{2,3}(-[A-Za-z]{2,4})?$');

final RegExp _placeholderPattern = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

Set<String> _placeholders(String value) =>
    _placeholderPattern.allMatches(value).map((m) => m.group(1)!).toSet();

/// Разобрать текст пакета; бросает [LanguagePackException] с объяснением для
/// человека, который принёс не тот файл.
LanguagePack decodeLanguagePack(String raw, {required Set<String> takenCodes}) {
  if (raw.codeUnits.length > kLanguagePackMaxBytes) {
    throw LanguagePackException(LanguagePackIssue.tooLarge);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw LanguagePackException(LanguagePackIssue.notJson);
  }
  if (decoded is! Map) {
    throw LanguagePackException(LanguagePackIssue.notObject);
  }
  final json = Map<String, dynamic>.from(decoded);

  final version = json['formatVersion'];
  if (version != null && version != kLanguagePackFormatVersion) {
    throw LanguagePackException(
      LanguagePackIssue.unknownVersion,
      detail: '$version',
    );
  }

  final code = (json['code'] as Object?)?.toString().trim() ?? '';
  if (code.isEmpty) {
    throw LanguagePackException(LanguagePackIssue.missingCode);
  }
  if (!_codePattern.hasMatch(code)) {
    throw LanguagePackException(LanguagePackIssue.badCode, detail: code);
  }
  if (takenCodes.contains(code)) {
    throw LanguagePackException(
      LanguagePackIssue.duplicateCode,
      detail: code,
    );
  }

  final nativeName = (json['nativeName'] as Object?)?.toString().trim() ?? '';
  if (nativeName.isEmpty) {
    throw LanguagePackException(LanguagePackIssue.missingName);
  }
  final englishName =
      (json['englishName'] as Object?)?.toString().trim() ?? nativeName;

  final ruleName = (json['pluralRule'] as Object?)?.toString().trim();
  final pluralOf = kPluralRules[ruleName];
  if (ruleName != null && ruleName.isNotEmpty && pluralOf == null) {
    throw LanguagePackException(
      LanguagePackIssue.unknownPluralRule,
      detail: ruleName,
    );
  }

  final skipped = <String>[];
  final dictionary = _readStrings(json['strings'], skipped);
  final plurals = _readPlurals(json['plurals'], skipped);

  if (dictionary.isEmpty && plurals.isEmpty) {
    throw LanguagePackException(LanguagePackIssue.nothingTranslated);
  }

  return LanguagePack(
    language: AppLanguage(
      code: code,
      nativeName: nativeName,
      englishName: englishName,
      dictionary: dictionary,
      plurals: plurals,
      pluralOf: pluralOf ?? oneOrMany,
      custom: true,
    ),
    skipped: skipped,
  );
}

Map<String, String> _readStrings(Object? value, List<String> skipped) {
  if (value == null) return const {};
  if (value is! Map) {
    // Имя поля вместо переводимой фразы: список пропущенного экран показывает
    // счётчиком, а ядро перевода вне зоны действия гарда-сканера.
    skipped.add('strings');
    return const {};
  }
  if (value.length > kLanguagePackMaxStrings) {
    throw LanguagePackException(LanguagePackIssue.tooManyStrings);
  }
  final out = <String, String>{};
  value.forEach((key, translation) {
    final ru = key.toString();
    if (translation is! String) {
      skipped.add(ru);
      return;
    }
    // Пустое значение — «ещё не переведено»: остаётся русский оригинал.
    if (translation.trim().isEmpty) return;
    final extra = _placeholders(translation).difference(_placeholders(ru));
    if (extra.isNotEmpty) {
      // Подстановка, которой нет в оригинале, показала бы на экране `{x}`.
      skipped.add(ru);
      return;
    }
    out[ru] = translation;
  });
  return out;
}

Map<String, List<String>> _readPlurals(Object? value, List<String> skipped) {
  if (value == null) return const {};
  if (value is! Map) {
    skipped.add('plurals');
    return const {};
  }
  final out = <String, List<String>>{};
  value.forEach((key, forms) {
    final lemma = key.toString();
    if (forms is! List || forms.isEmpty || forms.length > 6) {
      skipped.add(lemma);
      return;
    }
    // Одна пустая форма — «не переведено»: берём русские формы целиком, иначе
    // язык показал бы пустое слово рядом с числом.
    if (forms.any((form) => form is! String || form.trim().isEmpty)) {
      skipped.add(lemma);
      return;
    }
    out[lemma] = forms.map((form) => form.toString()).toList();
  });
  return out;
}

/// Чистый шаблон для переводчика: все строки приложения с пустыми значениями.
///
/// Инвентарь ключей берётся из английского словаря — это ровно тот набор,
/// который проверяет гард `l10n_guard_test.dart`, поэтому шаблон не отстаёт от
/// интерфейса и не требует отдельного списка «что переводить».
String buildLanguageTemplate({
  required Iterable<String> stringKeys,
  required Iterable<String> pluralLemmas,
}) {
  final keys = stringKeys.toList()..sort();
  final lemmas = pluralLemmas.toList()..sort();
  final blanks = List<String>.filled(kLanguagePackTemplatePluralForms, '');
  final buffer = StringBuffer()
    ..writeln('{')
    ..writeln('  "formatVersion": $kLanguagePackFormatVersion,')
    ..writeln('  "code": "xx",')
    ..writeln('  "nativeName": "",')
    ..writeln('  "englishName": "",')
    ..writeln('  "pluralRule": "one_other",')
    ..writeln('  "strings": {');
  for (var i = 0; i < keys.length; i++) {
    buffer.write('    ${jsonEncode(keys[i])}: ""');
    buffer.writeln(i == keys.length - 1 ? '' : ',');
  }
  buffer
    ..writeln('  },')
    ..writeln('  "plurals": {');
  for (var i = 0; i < lemmas.length; i++) {
    buffer.write('    ${jsonEncode(lemmas[i])}: ${jsonEncode(blanks)}');
    buffer.writeln(i == lemmas.length - 1 ? '' : ',');
  }
  buffer
    ..writeln('  }')
    ..write('}');
  return buffer.toString();
}
