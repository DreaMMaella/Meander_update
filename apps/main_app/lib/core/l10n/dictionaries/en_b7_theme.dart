/// Английский словарь модуля `b7_theme`: роли цветовой схемы и подсказки
/// вариантов темы (`core/theme/theme_engine.dart`).
///
/// Ключ — русская строка ровно как в коде (регистр и знаки включно);
/// перевод обязан сохранять плейсхолдеры `{...}`.
///
/// Названия ролей — не выдумка: это человеческие имена полей Material 3
/// `ColorScheme`, поэтому перевод сверяется с официальными именами ролей
/// (onSurfaceVariant — «secondary text», surfaceContainerHigh — «layer 3»).
final Map<String, String> enB7Theme = {
  // Роли ColorScheme.
  'Текст на основном': 'Text on primary',
  'Основной контейнер': 'Primary container',
  'Текст в основном контейнере': 'Text in primary container',
  'Текст на вторичном': 'Text on secondary',
  'Вторичный контейнер': 'Secondary container',
  'Текст во вторичном контейнере': 'Text in secondary container',
  'Текст на третичном': 'Text on tertiary',
  'Третичный контейнер': 'Tertiary container',
  'Текст в третичном контейнере': 'Text in tertiary container',
  'Текст на ошибке': 'Text on error',
  'Контейнер ошибки': 'Error container',
  'Текст в контейнере ошибки': 'Text in error container',
  'Текст на фоне': 'Text on background',
  'Поверхность': 'Surface',
  'Вариант поверхности': 'Surface variant',
  'Вторичный текст': 'Secondary text',
  'Поверхность приглушённая': 'Surface dim',
  'Поверхность светлая': 'Surface bright',
  'Слой 0 (самый низкий)': 'Layer 0 (lowest)',
  'Слой 1': 'Layer 1',
  'Слой 2': 'Layer 2',
  'Слой 3': 'Layer 3',
  'Слой 4 (самый верхний)': 'Layer 4 (highest)',
  'Инверсная поверхность': 'Inverse surface',
  'Текст в инверсной': 'Text on inverse surface',
  'Инверсный основной': 'Inverse primary',
  'Тонирование': 'Surface tint',
  'Контур': 'Outline',
  'Контур светлый': 'Outline variant',
  // Что выбрать в выпадающем списке вариантов seed-темы.
  'Точная — оттенок и насыщенность seed сохраняются один в один':
      'Exact — the seed hue and chroma carry over one to one',
  'Яркая — насыщенность seed усиливается, цвет отличается от исходного':
      'Vibrant — seed chroma is boosted, so the colour differs from the seed',
  'Material 3 по умолчанию — мягкая, слегка приглушённая':
      'Material 3 default — soft, slightly muted',
  'Эмоциональная — сине-родовые акценты, оттенок seed уходит':
      'Expressive — blue-leaning accents, the seed hue fades out',
  'Из самого seed, включая его оттенок у поверхностей':
      'Built from the seed itself, keeping its hue on surfaces',
  'Почти монохром — акцент тусклый, всё в серых тонах':
      'Nearly monochrome — dull accent, everything in greys',
  'Графит — оттенок игнорируется полностью, только серые':
      'Graphite — the hue is ignored entirely, greys only',
  'Игрушечная — оттенок seed в тему не попадает вовсе':
      'Playful — the seed hue never reaches the theme',
  'Игрушечная, фруктовая — как rainbow, но мягче':
      'Playful, fruit salad — like rainbow, but softer',
};
