/// Форматирование значений переменных для отображения в тексте.
library;

/// Отформатировать значение переменной в строку. Целые числа и double (15.0)
/// выводятся как целые («15»); остальные значения — через `toString()`.
String formatScriptValue(dynamic value) {
  if (value == null) return '';
  if (value is num) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (RegExp(r'^-?\d+\.0+$').hasMatch(trimmed)) {
      return trimmed.split('.').first;
    }
    return value;
  }
  return value.toString();
}
