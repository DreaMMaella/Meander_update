import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show TextDirection;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Цепочка «язык -> `fallbackCode`» и правила числа живых языков.
///
/// Пока словарь языка неполный, интерфейс обязан выглядеть переведённым:
/// промах по своему словарю идёт добирать у английского, и только если
/// английский молчит остаётся русский. Без этого мультиязычность формальная:
/// в списке квестов немецкий соседствовал бы с кириллицей.
///
/// Негативные контроли: `en` без `fallbackCode` (промах обязан остаться
/// русским), язык без цикла в цепочке (иначе `_chain` завис бы на `while`),
/// зажатие индекса форм (арабское правило просит шестую форму там, где
/// английский дал две — без зажатия это `RangeError`).
void main() {
  tearDown(() => L10n.setCurrent(L10n.byCode(kSourceLanguageCode)));

  final imported = <String>[];

  AppLanguage import({
    required String code,
    String? fallback,
    Map<String, String> strings = const {},
    Map<String, List<String>> plurals = const {},
    PluralSelector pluralOf = oneOrMany,
  }) {
    final language = AppLanguage(
      code: code,
      nativeName: code,
      englishName: code,
      dictionary: strings,
      plurals: plurals,
      pluralOf: pluralOf,
      fallbackCode: fallback,
      custom: true,
    );
    L10n.register(language);
    imported.add(code);
    return language;
  }

  tearDown(() {
    for (final code in imported) {
      L10n.unregister(code);
    }
    imported.clear();
  });

  group('правила числа', () {
    test('oneOrMany: форма 1 только для одного', () {
      expect([0, 1, 2, 5, 21].map(oneOrMany).toList(), [1, 0, 1, 1, 1]);
      expect(oneOrMany(-1), 0, reason: 'отрицательное считает по модулю');
    });

    test('moreThanOne: ноль и один — единственное', () {
      expect([0, 1, 2, 5].map(moreThanOne).toList(), [0, 0, 1, 1]);
      // Французское «0 fichiers» — единственное: правило обязано отличаться от
      // английского, иначе два правила в реестре бессмысленны.
      expect(moreThanOne(0), isNot(oneOrMany(0)));
    });

    test('otherOnly: сколько ни считай, форма одна', () {
      expect([0, 1, 2, 100].map(otherOnly).toSet(), {0});
    });

    test('slavicPlural: одна / мало / много', () {
      expect(
        [1, 2, 4, 5, 11, 14, 21, 22].map(slavicPlural).toList(),
        [0, 1, 1, 2, 2, 2, 0, 1],
      );
    });

    test('arabicPlural: шесть форм, и все достижимы', () {
      expect(
        [0, 1, 2, 3, 10, 11, 99, 100, 101, 111].map(arabicPlural).toList(),
        [0, 1, 2, 3, 3, 4, 4, 5, 5, 4],
      );
      // Если бы правило схлопнулось к «один/много», половина списка форм в
      // словаре никогда не использовалась бы.
      expect(
        List.generate(120, arabicPlural).toSet(),
        {0, 1, 2, 3, 4, 5},
      );
    });

    test('импортные имена правил доступны пакетам', () {
      expect(kPluralRules['other_only'], isNotNull);
      expect(kPluralRules['other_only']!(5), 0);
      expect(kPluralRules['arabic'], isNotNull);
      expect(kPluralRules['arabic']!(2), 2);
      expect(kPluralRules['french'], isNull, reason: 'выдуманное имя принять нельзя');
    });
  });

  group('цепочка fallback', () {
    test('промах по своему словарю идёт добирать к английскому', () {
      import(
        code: 'nl',
        fallback: 'en',
        strings: const {'Сохранить': 'Opslaan'},
      );
      L10n.setCurrent(L10n.byCode('nl'));
      expect(tr('Сохранить'), 'Opslaan');
      // Своя запись побеждает, даже когда английский знает ключ: иначе
      // правка пользователя перекрывалась бы репозиторным переводом.
      expect(tr('Отмена'), 'Cancel');
      // Пустое значение — «ещё не переведено», а не перевод: подстановка из
      // шаблона не должна показывать пустоту.
      expect(tr('Закрыть'), 'Close');
    });

    test('язык без fallback остаётся русским', () {
      import(code: 'sv', strings: const {'Сохранить': 'Spara'});
      L10n.setCurrent(L10n.byCode('sv'));
      expect(tr('Сохранить'), 'Spara');
      // Негативный контроль пары: английский не подставляет вместо русского.
      expect(tr('Отмена'), 'Отмена');
      expect(L10n.byCode('en').fallbackCode, isNull);
    });

    test('замкнутый fallback не зацикливает поиск', () {
      import(code: 'pl', fallback: 'pl', strings: const {'Сохранить': 'Zapisz'});
      L10n.setCurrent(L10n.byCode('pl'));
      expect(tr('Сохранить'), 'Zapisz');
      expect(tr('Отмена'), 'Отмена');

      import(code: 'da', fallback: 'pl');
      L10n.setCurrent(L10n.byCode('da'));
      expect(tr('Сохранить'), 'Zapisz', reason: 'цепочка обязана идти дальше одного шага');
    });

    test('цепочка обрывается на неизвестном коде', () {
      import(code: 'fi', fallback: 'zz', strings: const {'Сохранить': 'Tallenna'});
      L10n.setCurrent(L10n.byCode('fi'));
      expect(tr('Сохранить'), 'Tallenna');
      expect(tr('Отмена'), 'Отмена');
    });

    test('формы числа добирает тот же обход', () {
      import(code: 'et', fallback: 'en');
      L10n.setCurrent(L10n.byCode('et'));
      // Своего списка форм нет, английский есть: «5 дней» по-эстонски через
      // английские формы, а не русская форма посреди эстонского текста.
      expect(trp(['день', 'дня', 'дней'], 5), 'days');
      expect(trp(['день', 'дня', 'дней'], 1), 'day');
    });

    test('индекс правила зажимается длиной взятого списка', () {
      import(
        code: 'ms',
        fallback: 'en',
        plurals: const {'блок': ['blok']},
      );
      L10n.setCurrent(L10n.byCode('ms'));
      // Своя форма одна: `oneOrMany` для нуля просит индекс 1, его зажимает к
      // единственной форме вместо RangeError.
      expect(trp(['блок', 'блока', 'блоков'], 0), 'blok');
      expect(trp(['блок', 'блока', 'блоков'], 3), 'blok');
      // Арабское правило просит шестую форму там, где английский дал две.
      // Формы из fallback считают правилом текущего языка — несовершенный, но
      // предсказуемый результат вместо падения.
      L10n.setCurrent(
        import(
          code: 'ug',
          fallback: 'en',
          pluralOf: arabicPlural,
        ),
      );
      expect(trp(['лайк', 'лайка', 'лайков'], 100), 'likes');
      expect(trp(['лайк', 'лайка', 'лайков'], 1), 'likes');
      expect(trp(['лайк', 'лайка', 'лайков'], 0), 'like');
    });
  });

  group('реестр живых языков', () {
    test('каждый язык кроме источника и английского добирает английский', () {
      for (final language in L10n.supported) {
        final expected = switch (language.code) {
          kSourceLanguageCode || 'en' => null,
          _ => 'en',
        };
        expect(
          language.fallbackCode,
          expected,
          reason: '${language.code}: без fallback недопереведённое покажет кириллицу',
        );
      }
    });

    test('правило числа назначено каждому языку', () {
      const expected = {
        'ru': slavicPlural,
        'en': oneOrMany,
        'zh-CN': otherOnly,
        'ja': otherOnly,
        'ko': otherOnly,
        'de': oneOrMany,
        'es': oneOrMany,
        'pt-BR': oneOrMany,
        'fr': moreThanOne,
        'it': oneOrMany,
        'hi': moreThanOne,
        'tr': oneOrMany,
        'ar': arabicPlural,
      };
      expect(L10n.supported.map((l) => l.code).toSet(), expected.keys.toSet());
      for (final language in L10n.supported) {
        expect(
          language.pluralOf(5),
          expected[language.code]!(5),
          reason: language.code,
        );
        expect(
          language.pluralOf(1),
          expected[language.code]!(1),
          reason: language.code,
        );
      }
    });

    test('Material знает каждый язык реестра: подмена locale не нужна', () {
      for (final language in L10n.supported) {
        expect(
          GlobalMaterialLocalizations.delegate.isSupported(
            language.materialLocale,
          ),
          isTrue,
          reason: '${language.code}: обвеска Material без словаря падает',
        );
        expect(
          language.materialLocale,
          language.locale,
          reason: '${language.code}: язык есть в Material, английский не подставляем',
        );
      }
    });

    test('арабский интерфейс зеркалит, остальные — нет', () async {
      Future<TextDirection> directionOf(String code) async {
        final localizations = await GlobalWidgetsLocalizations.delegate
            .load(L10n.byCode(code).locale);
        return localizations.textDirection;
      }

      expect(await directionOf('ar'), TextDirection.rtl);
      // Негативный контроль: `rtl` обязана быть одной языковой строкой, а не
      // ответом делегата на любой locale.
      expect(await directionOf('de'), TextDirection.ltr);
      expect(await directionOf('zh-CN'), TextDirection.ltr);
      expect(await directionOf('hi'), TextDirection.ltr);
    });
  });
}
