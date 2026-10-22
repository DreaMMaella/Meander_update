/// Английский словарь модуля `b2_plugins`.
///
/// Ключ — русская строка ровно как в коде (регистр и знаки включно);
/// перевод обязан сохранять плейсхолдеры `{...}`.
final Map<String, String> enB2Plugins = {
  'Активные: {enabledCount} / {total}': 'Active: {enabledCount} / {total}',
  'Ошибка загрузки: {error}': 'Load error: {error}',
  'Плагин — это папка с plugin.json и Lua-скриптом. Включённые плагины исполняются в песочнице прямо на игровом экране.': 'A plugin is a folder with plugin.json and a Lua script. Enabled plugins run in a sandbox directly on the game screen.',
  'Управляйте установленными плагинами и включайте нужные.': 'Manage installed plugins and enable the ones you need.',
};
