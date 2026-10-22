/// Английский словарь модуля `b7_errors`: служебные тексты ошибок
/// (`core/utils/error_text.dart`).
///
/// Ключ — русская строка ровно как в коде (регистр и знаки включно);
/// перевод обязан сохранять плейсхолдеры `{...}`.
///
/// `{p0}` здесь — HTTP-код с бэкенда, `{p1}` — текст бэкенда: оба остаются
/// как есть, переводчику их менять нельзя.
final Map<String, String> enB7Errors = {
  'Сервер на обслуживании': 'Server is under maintenance',
  'Нет соединения с сервером': 'No connection to the server',
  'Доступ запрещён': 'Access denied',
  'Не найдено': 'Not found',
  'Сессия истекла — войдите заново': 'Session expired — sign in again',
  'Сервер не поддерживает это действие (404)':
      'The server does not support this action (404)',
  'Сервер ответил ошибкой': 'The server returned an error',
  'Сервер ответил ошибкой {p0}': 'The server returned error {p0}',
  'Сервер ответил: {p0}': 'The server replied: {p0}',
  'Сервер ответил: {p0} {p1}': 'The server replied: {p0} {p1}',
};
