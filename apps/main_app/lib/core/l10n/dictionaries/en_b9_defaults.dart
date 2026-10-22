/// Заполнители полей и имена по умолчанию, которые создаёт сам редактор
/// (новая нода, группа, копия, скрипт). Ключ — русская строка ровно как в
/// коде (регистр и знаки включно).
final Map<String, String> enB9Defaults = {
  // features/editor/logic/stack_canvas_session.dart
  'Группа {p0}': 'Group {p0}',
  // features/editor/providers/canvas_provider.dart
  'Новая группа': 'New group',
  'Новая нода {p0}': 'New node {p0}',
  // features/editor/providers/node_provider.dart
  // features/editor/providers/tag_provider.dart
  '{p0} (Копия)': '{p0} (Copy)',
  // features/editor/screens/canvas_screen.dart
  ' (шаблон)': ' (template)',
  // features/editor/screens/node_settings_screen.dart
  // features/editor/screens/visual_script_editor/block_models.dart
  'Выберите объект': 'Choose an object',
  'Выберите ноду': 'Choose a node',
  'Выберите скрипт': 'Choose a script',
  'Выберите функцию': 'Choose a function',
  'Выберите музыку': 'Choose music',
  'Выберите .lua': 'Choose .lua',
  'имя_переменной': 'variable_name',
  // features/editor/workspace/editor_document.dart
  'Документ': 'Document',
  // features/editor/providers/canvas_provider.dart — стартовый набор нод
  'Начало': 'Beginning',
  'Ты стоишь на перепутье. Слева — тёмный лес, справа — мост через реку. Куда пойдёшь?':
      'You stand at a crossroads: a dark forest to the left, a bridge over the river to the right. Which way will you go?',
  'Лес': 'Forest',
  'Ты идёшь в тёмный лес. Здесь продолжится история…':
      'You walk into the dark forest. The story continues here…',
  'Мост': 'Bridge',
  'Ты идёшь к мосту через реку. Здесь продолжится история…':
      'You walk toward the bridge over the river. The story continues here…',
  // features/hub/widgets/background_preview.dart — служебный квест предпросмотра
  'Превью фона': 'Background preview',
  'Временный квест для превью фона из маркета':
      'Temporary quest for the market background preview',
  'Так фон будет выглядеть в квесте: текст читается поверх картинки, кнопки кликабельны.':
      'This is how the background will look in a quest: text stays readable over the image, buttons are clickable.',
  'Обычная кнопка': 'Regular button',
  'Длинный текст на кнопке не ломается': 'Long button text does not break',
};
