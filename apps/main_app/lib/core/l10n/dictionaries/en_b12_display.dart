/// Доводка остатка: подписи перечислений (слоты, редкости, метрики наград,
/// темы PDF), строки внутри `build()`, подписи статистики и витрины маркета.
/// Ключ — русская строка ровно как в коде (регистр и знаки включно).
final Map<String, String> enB12Display = {
  // quest_analytics_screen.dart — строкиLifetime
  'Просмотров за всё время': 'Views all time',
  'Разных людей смотрели': 'Unique viewers',
  'Скачиваний всего': 'Downloads all time',
  'Игроков всего': 'Players all time',
  'Наиграно суммарно': 'Playtime in total',
  'Лайков / дизлайков': 'Likes / dislikes',
  'Отзывов': 'Reviews',
  'Отзывов с ответом автора': 'Reviews with an author reply',
  '{p0} из {p1} одобрено': '{p0} of {p1} approved',
  // analytics_charts.dart — подпись масштаба столбика
  '{p0} макс.': '{p0} max',
  // author_analytics_screen.dart — легенда графика
  'скачивания': 'downloads',
  'игроки': 'players',
  // quest_pdf_options.dart — темы и размер шрифта
  'Сепия': 'Sepia',
  'Пергамент': 'Parchment',
  'Бумажная классика': 'Classic paper',
  'Для чтения в темноте': 'For reading in the dark',
  'Тёплая бумага': 'Warm paper',
  'Винтажная стилизация': 'Vintage styling',
  'Мелкий': 'Small',
  'Крупный': 'Large',
  'Очень крупный': 'Extra large',
  // cosmetic_model.dart — слоты и редкости
  'Обложка': 'Banner',
  'Рамка аватара': 'Avatar frame',
  'Стиль ника': 'Username style',
  'Эффект профиля': 'Profile effect',
  'Доступно всем': 'Open to everyone',
  'Редкое': 'Rare',
  'Эпическое': 'Epic',
  'Легендарное': 'Legendary',
  // rewards_provider.dart — метрики наград
  'Дни подряд': 'Day streak',
  'Игровые дни': 'Days played',
  // quest_editor_shell.dart — подсказки навигации воркспейса
  'Список глав и нод квеста': 'List of the quest chapters and nodes',
  'Картинки, аудио, Lua-скрипты': 'Images, audio, Lua scripts',
  'Шаблоны контента': 'Content templates',
  'Тестовый запуск квеста': 'Test run of the quest',
  'Продолжить из сохранения': 'Continue from a save',
  // market_screen.dart — короткие подписи rail-меню и чипов
  'Тренды': 'Trending',
  'Выбор': 'Picks',
  // report_dialog.dart — причины жалобы; на сервер уходит русская
  'Спам': 'Spam',
  'Неподходящий контент': 'Inappropriate content',
  'Оскорбления': 'Harassment',
  'Мошенничество': 'Scam',
  'Нарушение авторских прав': 'Copyright violation',
  'Другое': 'Other',
  // quest_market_details_screen.dart — шаги модерации
  'Проверка токсичности...': 'Checking toxicity...',
  'Проверка на спам...': 'Checking for spam...',
  'Проверка контента...': 'Checking content...',
  'Публикация отзыва...': 'Publishing the review...',
  // button_module_preview_screen.dart — образцы надписей на кнопке
  'ПРИМЕР ТЕКСТА': 'SAMPLE TEXT',
  'Вы можете собрать Василию:\n- Я не видел Олега сегодня':
      'You can gather Vasilisa:\n- I haven\'t seen Oleg today',
  // splash_screen.dart — советы и факты на загрузке
  'Совет: не стоит создавать много скриптов — можно обойтись кучей функций в одном скрипте':
      'Tip: you don\'t need many scripts — a bunch of functions in one script is often enough',
  'Факт: первой текстовой игрой считается Colossal Cave Adventure (1976) — она была основана на реальной пещерной системе в Кентукки, которую исследовал автор игры':
      'Fact: Colossal Cave Adventure (1976) is usually called the first text game — it was based on a real cave system in Kentucky that its author had explored',
  'Факт: Zork (1977) стал одной из первых коммерчески успешных текстовых игр и породил движок Z-machine, который используется энтузиастами до сих пор':
      'Fact: Zork (1977) was one of the first commercially successful text games and gave birth to the Z-machine, still used by enthusiasts today',
  'Факт: в 1980-х текстовые квесты нередко продавались с дополнительными физическими предметами в коробке — картами, письмами, монетами — которые были нужны для решения загадок':
      'Fact: in the 1980s text games often shipped with physical extras in the box — maps, letters, coins — that puzzles actually required',
  'Факт: некоторые текстовые квесты 80-х были настолько сложными, что издатели прикладывали к коробке телефон горячей линии подсказок':
      'Fact: some 80s text games were so hard that publishers put a hint hotline phone number in the box',
  'Факт: в классических парсерных играх движок обычно понимал от 200 до 300 глаголов-команд':
      'Fact: a classic parser engine typically understood 200 to 300 command verbs',
  'Факт: одна из главных проблем классических текстовых квестов — «проблема лабиринта»: игроки легко теряются в однотипных комнатах без визуальной карты':
      'Fact: one of the classic text game pitfalls is the maze problem — players get lost easily in look-alike rooms with no visual map',
  'Факт: «пустая комната» без уникального описания — один из главных признаков слабого левел-дизайна в текстовом квесте':
      'Fact: an empty room with no unique description is one of the clearest signs of weak level design in a text game',
  'Факт: с 1995 года ежегодно проводится IFComp — конкурс интерактивной прозы, в котором участвуют сотни авторов со всего мира':
      'Fact: since 1995 IFComp has run every year — an interactive fiction contest drawing hundreds of authors worldwide',
  'Факт: ветвящийся сюжет в современных движках (Twine, Ink, Meander) часто визуализируют как граф узлов — это прямое развитие идей из ранних текстовых квестов':
      'Fact: modern engines (Twine, Ink, Meander) draw branching stories as a graph of nodes — a direct descendant of early text game ideas',
  'Факт: жанр текстовых квестов почти исчез в 90-х с приходом графических игр, но выжил благодаря энтузиастам и продолжает существовать в виде инди-сцены':
      'Fact: text games nearly vanished in the 90s when graphical games arrived, but enthusiasts kept them alive as an indie scene',
  'Факт: в interactive fiction вся «графика» существует только в воображении игрока — жанр целиком держится на тексте и структуре повествования':
      'Fact: in interactive fiction all the "graphics" live in the player\'s imagination — the genre rests entirely on text and story structure',
  'Факт: жанр visual novel во многом вырос из текстовых квестов, добавив статичные иллюстрации и музыку к тексту':
      'Fact: the visual novel genre grew out of text games, adding static artwork and music to the text',
  // script_block_shell.dart — тултип ручки перетаскивания блока
  'Удерживайте, чтобы перетащить блок': 'Hold to drag the block',
};
