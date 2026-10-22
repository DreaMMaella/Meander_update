import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Делегаты локализации для `MaterialApp`.
///
/// Без них Flutter знает только английский: `DefaultMaterialLocalizations`
/// поддерживает единственный `en`, поэтому `locale: Locale('ru')` оставляет
/// `MaterialLocalizations` пустым и обвеска Material-виджетов падает
/// («No MaterialLocalizations found»). Список покрывает все языки, которые
/// умеет intl, — новый язык из реестра переводить здесь не нужно.
const List<LocalizationsDelegate<Object>> appLocalizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
