/// Язык интерфейса: импорт своего перевода, шаблон и ошибки языкового пакета.
/// Ключ — русская строка ровно как в коде (регистр и знаки включно).
final Map<String, String> enB10Languages = {
  // features/settings/widgets/interface_language_dialog.dart
  'Выберите файл языка': 'Choose a language file',
  'Файл языка не читается': 'The language file cannot be read',
  'Файл языка слишком большой': 'The language file is too large',
  'Язык импортирован: {name}': 'Language imported: {name}',
  'Язык импортирован: {name}. Пропущено записей: {skipped}':
      'Language imported: {name}. Skipped entries: {skipped}',
  'Не удалось импортировать язык': 'Could not import the language',
  'Шаблон для перевода': 'Translation template',
  'Шаблон со всеми строками сохранён в выбранный файл':
      'The template with every string is saved to the file you chose',
  'Не удалось сохранить шаблон': 'Could not save the template',
  'Удалить язык {name}?': 'Remove {name}?',
  'Файл языка удалится из приложения.':
      'The language file will be removed from the app.',
  'Язык удалён': 'Language removed',
  'Импортированные языки': 'Imported languages',
  'Строка без перевода остаётся русской — перевод можно дополнять по частям.':
      'A string without a translation stays Russian — you can add translations part by part.',
  'Импортировать язык': 'Import a language',
  'Удалить язык': 'Remove language',
  // Причины отказа языкового пакета — их подбирает экран импорта.
  'Файл языка не читается как JSON': 'The language file is not valid JSON',
  'Файл языка должен быть объектом JSON с полями code и strings':
      'The language file must be a JSON object with code and strings fields',
  'Неизвестная версия формата языка: {version}':
      'Unknown language format version: {version}',
  'В файле не указан код языка': 'The file does not give a language code',
  'Код языка должен быть строчными буквами, например de или pt-BR':
      'The language code must be lowercase letters, for example de or pt-BR',
  'Язык с кодом {code} уже есть в списке':
      'A language with the code {code} is already in the list',
  'В файле не указано название языка': 'The file does not give a language name',
  'Неизвестное правило множественного числа: {rule}':
      'Unknown plural rule: {rule}',
  'В файле нет ни одной переведённой строки':
      'The file has no translated strings at all',
  'Слишком много строк в файле языка': 'Too many strings in the language file',
};
