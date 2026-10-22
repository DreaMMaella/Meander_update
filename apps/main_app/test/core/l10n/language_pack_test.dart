import 'dart:convert';

import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/l10n/language_pack.dart';
import 'package:canvas_app/features/settings/widgets/interface_language_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Языковой пакет, который пользователь приносит из настроек.
///
/// Проверяем не «красивый ли JSON», а две вещи, на которых импорт и ломается:
/// пакет обязан отказать молча-опасному входу (кривой файл, чужой код,
/// неизвестное правило числа) и обязан пропустить отдельную строку, не роняя
/// весь перевод. Плюс шаблон: его пишет ручной `StringBuffer`, и если он
/// выдаст невалидный JSON, переводчик не откроет файл вообще.
void main() {
  String pack(Map<String, Object?> json) => jsonEncode(json);

  Map<String, Object?> valid({
    String code = 'nl',
    Object? nativeName = 'Nederlands',
    Object? strings = const {'Сохранить': 'Opslaan'},
    Object? plurals,
    Object? pluralRule,
  }) => {
    'code': code,
    'nativeName': nativeName,
    if (pluralRule != null) 'pluralRule': pluralRule,
    'strings': strings,
    if (plurals != null) 'plurals': plurals,  };

  LanguagePackException failureOf(String raw) {
    late LanguagePackException error;
    try {
      decodeLanguagePack(raw, takenCodes: const {'ru', 'en'});
      fail('пакет принят, хотя не должен был');
    } on LanguagePackException catch (error_) {
      error = error_;
    }
    return error;
  }

  LanguagePackException failure(Map<String, Object?> json) =>
      failureOf(pack(json));

  group('декод пакета', () {
    test('полный пакет даёт пользовательский язык', () {
      final result = decodeLanguagePack(
        pack(
          valid(
            pluralRule: 'slavic',
            plurals: const {
              'минута': ['Minute', 'Minuten', 'Minuten'],
            },
          ),
        ),
        takenCodes: const {'ru', 'en'},
      );
      expect(result.language.code, 'nl');
      expect(result.language.nativeName, 'Nederlands');
      expect(result.language.custom, isTrue);
      expect(result.language.dictionary, {'Сохранить': 'Opslaan'});
      expect(result.language.plurals['минута'], ['Minute', 'Minuten', 'Minuten']);
      expect(result.stringCount, 1);
      expect(result.pluralCount, 1);
      expect(result.skipped, isEmpty);
      // Правило числа берётся из файла: без `slavic` форма для 5 была бы
      // `one_other`, и «5 Minuten» выпало бы из списка трёх форм.
      expect(result.language.pluralOf(5), 2);
    });

    test('язык без правила числа живёт по one_other', () {
      final result = decodeLanguagePack(
        pack(valid()),
        takenCodes: const {'ru', 'en'},
      );
      expect(result.language.pluralOf(1), 0);
      expect(result.language.pluralOf(2), 1);
    });

    test('кривой JSON, не-объект и пустой пакет отклоняются', () {
      expect(failureOf('{').issue, LanguagePackIssue.notJson);
      expect(failureOf('[1,2]').issue, LanguagePackIssue.notObject);
      expect(
        failure(valid(strings: 'nope')).issue,
        LanguagePackIssue.nothingTranslated,
      );
    });

    test('поля code и nativeName обязательны, код — строчные буквы', () {
      expect(failure(valid(code: '')).issue, LanguagePackIssue.missingCode);
      expect(failure(valid(code: 'DE')).issue, LanguagePackIssue.badCode);
      expect(failure(valid(code: 'deutsch')).issue, LanguagePackIssue.badCode);
      expect(
        failure(valid(nativeName: '  ')).issue,
        LanguagePackIssue.missingName,
      );
      // Код с регионом законен: `nb-NO` — другой перевод, а не ошибка. Тот же
      // `pt-BR` теперь вшит, и пакет на него отклоняют как дубликат.
      expect(
        decodeLanguagePack(
          pack(valid(code: 'nb-NO')),
          takenCodes: const {'ru', 'en'},
        ).language.code,
        'nb-NO',
      );
    });

    test('вшитый код не переимпортируется', () {
      final error = failure(valid(code: 'en'));
      expect(error.issue, LanguagePackIssue.duplicateCode);
      expect(error.detail, 'en');
    });

    test('неизвестное правило числа и чужая версия формата', () {
      expect(
        failure(valid(pluralRule: 'french')).issue,
        LanguagePackIssue.unknownPluralRule,
      );
      final version = failure({...valid(), 'formatVersion': 2});
      expect(version.issue, LanguagePackIssue.unknownVersion);
      expect(version.detail, '2');
      // Версия 1 и её отсутствие — ок: шаблон и старые файлы совпадают.
      expect(
        decodeLanguagePack(
          pack({...valid(), 'formatVersion': 1}),
          takenCodes: const {},
        ).stringCount,
        1,
      );
    });

    test('строка с чужим плейсхолдером пропускается, остальное берётся', () {
      final result = decodeLanguagePack(
        pack(
          valid(
            strings: const {
              'Привет, {name}': 'Hello, {name}',
              'Удалить?': 'Löschen {x}?',
              'Закрыть': '',
              'Отмена': 42,
            },
          ),
        ),
        takenCodes: const {},
      );
      // `{x}` в переводе trf() не подставит: на экране остались бы фигурные
      // скобки, поэтому запись не берётся вовсе.
      expect(result.language.dictionary, {'Привет, {name}': 'Hello, {name}'});
      expect(result.skipped, ['Удалить?', 'Отмена']);
    });

    test('поля strings и plurals не обязательны, но не должны быть мусором', () {
      final result = decodeLanguagePack(
        pack({
          'code': 'nl',
          'nativeName': 'Nederlands',
          'strings': 'Opslaan',
          'plurals': const {
            'минута': ['Minute', 'Minuten'],
          },
        }),
        takenCodes: const {},
      );
      // Кривое поле роняет не весь пакет: множественное число берётся, а
      // строки уходят в пропуски.
      expect(result.language.dictionary, isEmpty);
      expect(result.pluralCount, 1);
      // Имя поля в skipped: экран показывает счётчик пропусков, а ядро
      // перевода вне зоны гард-сканера, поэтому переводимой фразы здесь нет.
      expect(result.skipped, ['strings']);
    });

    test('формы числа: пустая форма или длинный список — пропуск', () {
      final result = decodeLanguagePack(
        pack(
          valid(
            plurals: const {
              'минута': ['Minute', 'Minuten'],
              'год': ['год', ''],
              'день': ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
              'файл': 'файла',
            },
          ),
        ),
        takenCodes: const {},
      );
      expect(result.language.plurals.keys, ['минута']);
      expect(result.skipped, containsAll(['год', 'день', 'файл']));
    });

    test('слишком большой файл и слишком много строк', () {
      expect(
        failureOf(
          '${pack(valid())}${' ' * kLanguagePackMaxBytes}',
        ).issue,
        LanguagePackIssue.tooLarge,
      );

      final many = {
        for (var i = 0; i <= kLanguagePackMaxStrings; i++) 'строк $i': 'row $i',
      };
      expect(
        failure(valid(strings: many)).issue,
        LanguagePackIssue.tooManyStrings,
      );
    });
  });

  group('шаблон для переводчика', () {
    test('шаблон читается как JSON и покрывает все ключи', () {
      final json = jsonDecode(
        buildLanguageTemplate(
          stringKeys: const ['Сохранить', 'Отмена', 'а"б'],
          pluralLemmas: const ['минута', 'год'],
        ),
      ) as Map<String, Object?>;
      expect(json['code'], 'xx');
      expect(json['pluralRule'], 'one_other');
      expect(json['formatVersion'], kLanguagePackFormatVersion);
      // Ключ с кавычкой внутри — ровно та причина, по которой шаблон пишут
      // через jsonEncode, а не конкатенацией.
      // Порядок ключей в файле — по кодовым символам: переводчик видит
      // стабильный diff и не тонет в переставленных строках.
      expect(
        (json['strings']! as Map<String, Object?>).keys,
        ['Отмена', 'Сохранить', 'а"б'],
      );
      final plurals = json['plurals']! as Map<String, Object?>;
      expect(plurals.keys, ['год', 'минута']);
      expect(plurals['минута'], List.filled(kLanguagePackTemplatePluralForms, ''));
      // Пустой шаблон импорт не примет: сначала переводчик обязан назвать
      // язык, потом заполнить хоть одну строку.
      expect(
        failureOf(jsonEncode(json)).issue,
        LanguagePackIssue.missingName,
      );
      expect(
        failureOf(
          jsonEncode({...json, 'nativeName': 'Test', 'code': 'zz'}),
        ).issue,
        LanguagePackIssue.nothingTranslated,
      );
    });

    test('пустой шаблон всё равно валидный JSON', () {
      final json = jsonDecode(
        buildLanguageTemplate(stringKeys: const [], pluralLemmas: const []),
      ) as Map<String, Object?>;
      expect(json['strings'], isEmpty);
      expect(json['plurals'], isEmpty);
    });
  });

  group('текст отказа', () {
    test('каждая причина имеет перевод на английском', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      L10n.setCurrent(L10n.byCode('en'));
      try {
        for (final issue in LanguagePackIssue.values) {
          final text = languagePackMessage(
            LanguagePackException(issue, detail: 'xx'),
          );
          // Кириллица в английском режиме = ключ есть в коде, но не в
          // словаре: экран показал бы русскую фразу.
          expect(
            text.contains(RegExp('[а-яА-ЯёЁ]')),
            isFalse,
            reason: '$issue не переведён: «$text»',
          );
          expect(text, isNotEmpty);
        }
      } finally {
        L10n.setCurrent(L10n.byCode('ru'));
      }
    });

    test('подстановка причины доживает до экрана', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      L10n.setCurrent(L10n.byCode('en'));
      try {
        expect(
          languagePackMessage(
            LanguagePackException(
              LanguagePackIssue.duplicateCode,
              detail: 'en',
            ),
          ),
          contains('en'),
        );
        expect(
          languagePackMessage(
            LanguagePackException(
              LanguagePackIssue.unknownPluralRule,
              detail: 'french',
            ),
          ),
          contains('french'),
        );
      } finally {
        L10n.setCurrent(L10n.byCode('ru'));
      }
    });

    test('в русском режиме причина остаётся русской', () {
      expect(
        languagePackMessage(LanguagePackException(LanguagePackIssue.notJson)),
        'Файл языка не читается как JSON',
      );
    });
  });
}
