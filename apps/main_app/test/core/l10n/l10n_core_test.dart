import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/l10n/l10n_provider.dart';
import 'package:canvas_app/core/l10n/language_rebuild.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ядро переключения языка. Русский — язык-источник, поэтому главный
/// инвариант механизма: строка без перевода обязана остаться русской, а не
/// пустой и не английской.
///
/// Негативные контроли (каждая мутация валит именно свой тест):
///   * `tr` без `?? ru` -> тест 1;
///   * `setCurrent` без вызова слушателей -> виджет-тест;
///   * славянское правило, сведённое к «один или все» -> тест форм числа;
///   * `select` без записи в prefs -> тест перезапуска;
///   * `_fill` без аргумента `n` -> проверка `{n}` в тесте форм числа.
void main() {
  tearDown(() => L10n.setCurrent(L10n.byCode(kSourceLanguageCode)));

  test('строка без перевода остаётся русской, с переводом — английской', () {
    expect(L10n.tr('Сохранить'), 'Сохранить');
    L10n.setCurrent(L10n.byCode('en'));
    expect(L10n.tr('Сохранить'), 'Save');
    expect(L10n.tr('Совсем уникальная строка'), 'Совсем уникальная строка');
  });

  test('подстановки живут и в русском, и в переводе', () {
    expect(
      L10n.trf('Язык интерфейса: {name}', {'name': 'Русский'}),
      'Язык интерфейса: Русский',
    );
    L10n.setCurrent(L10n.byCode('en'));
    expect(
      L10n.trf('Язык интерфейса: {name}', {'name': 'English'}),
      'Interface language: English',
    );
    // Нет аргумента -> плейсхолдер остаётся на экране: опечатка в коде
    // видна человеку, а не проглатывается пустотой.
    expect(
      L10n.trf('Язык интерфейса: {name}', {}),
      'Interface language: {name}',
    );
    L10n.setCurrent(L10n.byCode(kSourceLanguageCode));
    expect(L10n.trf('нет такого ключа: {x}', {'x': 1}), 'нет такого ключа: 1');
  });

  test('формы множественного числа выбираются по правилу языка', () {
    // Леммы взяты живые (из `enCommonPlurals` и из строк lib/): гард
    // `l10n_guard_test.dart` требует, чтобы каждая форма числа в коде имела
    // запись в словаре, поэтому тест на выдуманной «минуте» просто выдохся бы.
    const forms = ['день', 'дня', 'дней'];
    // Русское правило: 1 -> одна, 2..4 -> мало, 5+ и 11..14 -> много.
    expect(L10n.trp(forms, 1), 'день');
    expect(L10n.trp(forms, 2), 'дня');
    expect(L10n.trp(forms, 5), 'дней');
    expect(L10n.trp(forms, 11), 'дней');
    expect(L10n.trp(forms, 21), 'день');

    // Ключ словаря — первая русская форма, дальше своё правило языка:
    // 21 по-английски уже множественное, хотя по-русски «двадцать один».
    L10n.setCurrent(L10n.byCode('en'));
    expect(L10n.trp(forms, 1), 'day');
    expect(L10n.trp(forms, 21), 'days');
    expect(L10n.trp(forms, 5), 'days');
    expect(L10n.trp(['блок', 'блока', 'блоков'], 3), 'blocks');

    // Количество подставляется в шаблон само, как аргумент n.
    L10n.setCurrent(L10n.byCode(kSourceLanguageCode));
    expect(
      L10n.trp(['{n} день', '{n} дня', '{n} дней'], 5),
      '5 дней',
    );
  });

  test('неизвестный код языка даёт русский, а реестр целый', () {
    // `de` в реестре, поэтому выдуманный код: опечатка в настройках не должна
    // стартовать приложение с пустым словарём.
    expect(L10n.byCode('zz').code, kSourceLanguageCode);
    expect(L10n.byCode('').code, kSourceLanguageCode);
    final codes = L10n.supported.map((l) => l.code).toList();
    expect(codes, contains(kSourceLanguageCode));
    expect(codes.toSet(), hasLength(codes.length));
    for (final language in L10n.supported) {
      expect(language.nativeName, isNotEmpty);
      // `Locale('pt-BR')` одним аргументом — это languageCode «pt-BR», и
      // словарь Material на таком не находится. Регион обязан ехать отдельным
      // полем; `toLanguageTag()` при этом совпадает в обоих случаях, поэтому
      // проверяем именно разделение.
      expect(language.locale.languageCode, isNot(contains('-')));
      expect(language.locale.toLanguageTag(), language.code);
    }
  });

  test('смена языка зовёт слушателей только когда язык правда сменился', () {
    var calls = 0;
    void listener() => calls++;
    L10n.addListener(listener);
    addTearDown(() => L10n.removeListener(listener));

    L10n.setCurrent(L10n.byCode(kSourceLanguageCode));
    expect(calls, 0, reason: 'тот же язык не должен перерисовывать экран');
    L10n.setCurrent(L10n.byCode('en'));
    expect(calls, 1);
    L10n.setCurrent(L10n.byCode('en'));
    expect(calls, 1);
  });

  test('выбор языка переживает перезапуск: prefs + initAppLanguage', () async {
    SharedPreferences.setMockInitialValues({'ui_language': 'en'});
    await initAppLanguage();
    expect(L10n.code, 'en');
    expect(tr('Сохранить'), 'Save');
  });

  test('select пишет выбранный язык в prefs и подтягивает L10n', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = AppLanguageNotifier();
    await notifier.select('en');
    expect(L10n.code, 'en');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ui_language'), 'en');
    await notifier.select('xx');
    expect(L10n.code, kSourceLanguageCode);
    expect(prefs.getString('ui_language'), kSourceLanguageCode);
  });

  testWidgets(
    'язык применяется на месте: экран с LanguageRebuild перерисовывается',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _LabelProbe()));
      expect(find.text('Сохранить'), findsOneWidget);

      L10n.setCurrent(L10n.byCode('en'));
      await tester.pump();
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Сохранить'), findsNothing);

      L10n.setCurrent(L10n.byCode(kSourceLanguageCode));
      await tester.pump();
      expect(find.text('Сохранить'), findsOneWidget);
    },
  );
}

class _LabelProbe extends StatefulWidget {
  const _LabelProbe();

  @override
  State<_LabelProbe> createState() => _LabelProbeState();
}

class _LabelProbeState extends State<_LabelProbe> with LanguageRebuild {
  @override
  Widget build(BuildContext context) => Text(tr('Сохранить'));
}
