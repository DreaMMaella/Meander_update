import 'dart:io';

import 'package:canvas_app/core/l10n/app_language.dart';
import 'package:canvas_app/core/l10n/app_localizations.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Корневой `MaterialApp` обязан давать `MaterialLocalizations` на каждом
/// языке реестра.
///
/// Flutter из коробки знает только английский: без делегатов из
/// `flutter_localizations` словарь Material-виджетов не находится, если
/// `locale` задан вручную. Поймано живым запуском — `NavigationRail` в рельсе
/// меню падал с «No MaterialLocalizations found» (navigation_rail.dart
/// зовёт `MaterialLocalizations.of`), а виджет-тесты качают свой `MaterialApp`
/// и корневой не видят.
///
/// НЕГАТИВНЫЙ КОНТРОЛЬ: второй тест качает тот же корень без делегатов и
/// требует, чтобы `MaterialLocalizations.of` бросил ровно ту ошибку. Третий
/// читает исходник `app.dart` — делегаты, вычеркнутые из корня, ловит он.
void main() {
  final supportedLocales = [
    for (final language in L10n.supported) language.locale,
  ];

  /// Качает корень с указанными делегатами и возвращает контекст из-под
  /// `Localizations`: на нём и проверяем, найден ли словарь.
  Future<({BuildContext context, MaterialLocalizations? found})> pumpRoot(
    WidgetTester tester, {
    required Locale locale,
    required List<LocalizationsDelegate<Object>> delegates,
    required bool withRail,
  }) async {
    BuildContext? rootContext;
    MaterialLocalizations? found;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: supportedLocales,
        localizationsDelegates: delegates,
        home: Builder(
          builder: (context) {
            found = Localizations.of<MaterialLocalizations>(
              context,
              MaterialLocalizations,
            );
            rootContext = context;
            return withRail
                ? NavigationRail(
                    selectedIndex: 0,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home),
                        label: Text('Главная'),
                      ),
                    ],
                  )
                : const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(rootContext, isNotNull, reason: 'дом не построился');
    return (context: rootContext!, found: found);
  }

  for (final language in L10n.supported) {
    testWidgets('${language.code}: рельс собирается и словарь на месте', (
      tester,
    ) async {
      final root = await pumpRoot(
        tester,
        locale: language.locale,
        delegates: appLocalizationsDelegates,
        withRail: true,
      );
      expect(
        root.found,
        isNotNull,
        reason:
            '${language.code}: MaterialLocalizations пуст — любой Material-'
            'виджет с of() бросит исключение',
      );
      expect(
        GlobalMaterialLocalizations.delegate.isSupported(language.locale),
        isTrue,
        reason:
            '${language.code}: в flutter_localizations нет словаря — язык '
            'нужно добавлять вместе с делегатами',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('без делегатов of() падает с той самой ошибкой', (tester) async {
    final root = await pumpRoot(
      tester,
      locale: const Locale('ru'),
      delegates: const [],
      withRail: false,
    );
    expect(root.found, isNull);

    Object? thrown;
    try {
      MaterialLocalizations.of(root.context);
    } catch (error) {
      thrown = error;
    }
    expect(thrown, isNotNull, reason: 'негативный контроль не сработал');
    expect(
      thrown.toString(),
      contains('No MaterialLocalizations found'),
      reason: 'проверяем ровно тот краш, что увидел пользователь',
    );
    // Фреймворк сам предупреждает о той же причине — предупреждение и есть
    // диагноз, оно остаётся в очереди исключений этого теста.
    expect(
      tester.takeException().toString(),
      contains('is not supported by all of its localization delegates'),
    );
  });

  test('корень приложения передаёт делегаты MaterialApp', () {
    final source = File('lib/app/app.dart').readAsStringSync();
    expect(
      source,
      contains('localizationsDelegates: appLocalizationsDelegates'),
      reason:
          'locale задан вручную, а словарь Material остался английским — '
          'экраны падают на запуске',
    );
    expect(source, contains('locale: language.materialLocale'));
  });

  /// Языковой пакет из настроек приносит код, которого нет в списке
  /// `flutter_localizations` («qq», «eo», выдуманная маркировка). Отдай его
  /// `MaterialApp` как есть — и приложение падёт ровно той ошибкой, которую
  /// этот файл ловит сверху: обвескаMaterial останется без словаря.
  test('язык без словаря Material отдаёт обвеске английский', () {
    final exotic = AppLanguage(
      code: 'qq',
      nativeName: 'Qux',
      englishName: 'Qux',
      custom: true,
    );
    expect(
      GlobalMaterialLocalizations.delegate.isSupported(exotic.locale),
      isFalse,
      reason: 'тест опирается на то, что Material этого языка не знает',
    );
    expect(exotic.materialLocale, kFallbackMaterialLocale);
    // Вшитые языки ничего не теряют: у них свой словарь Material.
    expect(L10n.byCode('ru').materialLocale, const Locale('ru'));
    expect(L10n.byCode('en').materialLocale, const Locale('en'));
  });
}
