import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  SCRIPT BLOCK SHELL — блок залит цветом категории, текст белый
// ============================================================================
//
//  Цвет = категория, и это единственный способ найти нужный блок в списке из
//  двадцати: раньше корпус брался из ролей темы, а категорию задавала трёх-
//  пиксельная полоса слева (решение #224/#237, разворот по просьбе автора).
//  Полосы больше нет: корпус целиком в цвете категории, у заголовка иконка,
//  слева ручка перетаскивания, поля — тёмные плашки с подчёркиванием.
//
//  От темы остаётся только оттенок: в светлой теме тот же цвет затемнён,
//  чтобы белый текст держал контраст (проверяется тестом, а не глазом).
//
//  Контейнер (событие, цикл, условие) НЕ обнимает детей цветным корпусом:
//  его карточка — только шапка и собственные поля, а вложенные блоки идут
//  плоскими карточками под ней ([ScriptBlockShell.body]). Раньше дети сидели
//  в затемнённой шахте внутри корпуса, и событие раздувалось на весь скрипт
//  — блок превращался в фон чужого содержимого. Где область контейнера
//  кончается — говорит [ScriptBlockShell.endLabel] и подпись ветки
//  [ScriptBranchCaption]; у события заглушка не нужна: следующая шляпа
//  начинает новый скрипт.
//
//  У блока события верхняя кромка поднимается слева «шляпой» — это начало
//  скрипта, и видеть его надо краем карточки, а не ещё одним блоком списка.
//
//  Внутренние плашки (поле, слайдер, сегменты) берут цвета из [ShellInherited]
//  — правка здесь меняется сразу во всех блоках, ни один виджет трогать не
//  нужно.
// ============================================================================

/// Цвет корпуса блока = цвет категории.
///
/// Белый текст на корпусе обязан читаться: пара `блокFg : корпус` держит
/// контраст WCAG AA для обычного текста (4.5:1) в каждой яркости — за этим
/// следит тест, а не глаз. Светлее этих значений можно только вместе с тёмным
/// текстом, тогда правьте и [blockFg].
Color blockAccent(Brightness brightness, BlockCategory category) {
  final isDark = brightness == Brightness.dark;
  switch (category) {
    case BlockCategory.event:
      return isDark ? const Color(0xFFAC4F24) : const Color(0xFF8E3F18);
    case BlockCategory.control:
      return isDark ? const Color(0xFF8F6A17) : const Color(0xFF85600F);
    case BlockCategory.variable:
      return isDark ? const Color(0xFFC1514D) : const Color(0xFFA33D39);
    case BlockCategory.action:
      return isDark ? const Color(0xFF3E77B8) : const Color(0xFF2C5F99);
    case BlockCategory.script:
      return isDark ? const Color(0xFF8E5FA6) : const Color(0xFF71478A);
    case BlockCategory.comment:
      return isDark ? const Color(0xFF7A736B) : const Color(0xFF5F5952);
  }
}

/// Текст на залитом корпусе. Роли темы здесь не работают: в светлой теме
/// `onSurface` почти чёрный и на насыщенном корпусе его не видно.
///
/// Контраст этой пары с каждым корпусом считает тест
/// `block_chrome_theme_test.dart` — цвета рампы подбирать глазом неудобно:
/// золотой корпус «Цикла» на глаз сочен, а с белым текстом даёт 3.8:1, и
/// только счёт видит, что надо затемнять.
const Color blockFg = Colors.white;

/// Подложка поля внутри блока: тёмная плашка поверх цветного корпуса — поле
/// читается как поле, а не как текст на пятне, и одинаково на любом корпусе.
const Color blockFieldFill = Color(0x42000000);

/// Насколько кромка блока события поднимается слева — «шляпа» начала скрипта.
///
/// Меньше шести пикселей не читается вовсе, больше двенадцати — съедает
/// отступ между карточками, и список начинает казаться разреженным.
const double blockHatRise = 10;

/// Пустое обязательное поле. Красная рамка из темы для этого не годится:
/// `colorScheme.error` в светлой теме почти чёрный и на красном или
/// оранжевом корпусе не читается. Сигнал — белая рамка по всему периметру
/// вместо обычной черты снизу (см. [_ChipSurface]).
const Color blockFieldAlert = Color(0xE6FFFFFF);

/// Приглушённый белый: подписи полей и строки-подсказки внутри блока.
///
/// Белее нельзя (подпись сольётся со значением), темнее нельзя — на самом
/// светлом корпусе подписи не хватит даже 3:1, тест это ловит.
const Color blockFgMuted = Color(0xD1FFFFFF);

/// Светло-красный для сигналов внутри блока — тот же довод, что у
/// [blockFieldAlert]: тему-овский `error` на залитом корпусе тонет.
const Color blockFgAlert = Color(0xFFFFB4AB);

/// Тема внутри карточки блока.
///
/// Виджеты блоков рисуют подсказки, галочки и плашки ролями темы, но на
/// залитом корпусе тема говорит неправду: `onSurfaceVariant` в светлой теме
/// почти чёрный и на красном корпусе не читается, `surfaceContainerHighest`
/// светлее корпуса — плашка на нём теряется. Поэтому под карточкой роли
/// переопределены одним [Theme]: текст белый, подложка затемнённая, акцент
/// — тот же белый. Это правка в одном месте вместо двух десятков виджетов;
/// диалоги и пикеры в неё не попадают — они строятся над карточкой.
ThemeData blockCardTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      primary: blockFg,
      secondary: blockFg,
      onSurface: blockFg,
      onSurfaceVariant: blockFgMuted,
      surfaceContainerHigh: blockFieldFill,
      surfaceContainerHighest: blockFieldFill,
      primaryContainer: blockFg.withValues(alpha: 0.22),
      onPrimaryContainer: blockFg,
      secondaryContainer: blockFg.withValues(alpha: 0.22),
      onSecondaryContainer: blockFg,
      outlineVariant: blockFg.withValues(alpha: 0.26),
      error: blockFgAlert,
    ),
  );
}

IconData iconForCategory(BlockCategory c) {
  switch (c) {
    case BlockCategory.event:
      return Icons.flash_on_rounded;
    case BlockCategory.control:
      return Icons.call_split_rounded;
    case BlockCategory.variable:
      return Icons.edit_note_rounded;
    case BlockCategory.action:
      return Icons.play_arrow_rounded;
    case BlockCategory.script:
      return Icons.code_rounded;
    case BlockCategory.comment:
      return Icons.chat_bubble_outline_rounded;
  }
}

// ============================================================================
//  ПОДТВЕРЖДЕНИЕ УДАЛЕНИЯ
// ============================================================================

Future<bool> confirmBlockDeletion(
  BuildContext context, {
  String? title,
  String? message,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? tr('Удалить блок?')),
      content: Text(message ?? tr('Действие нельзя отменить.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Отмена')),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
          ),
          child: Text(tr('Удалить')),
        ),
      ],
    ),
  );
  return result == true;
}

// ============================================================================
//  SCRIPT BLOCK SHELL
// ============================================================================

/// Действия контекстного меню (одиночный тап по блоку).
enum ScriptBlockMenuAction { copy, cut, duplicate, paste, delete }

/// Строка результата операции над блоком: существительное берётся из
/// [blockScope], поэтому операция над целым событием читается как «Событие
/// продублировано со всем содержимым», а не «Блок продублирован».
String blockOperationToast(
  ScriptBlockMenuAction action,
  VisualScriptBlock block,
) {
  final scope = blockScope(block);
  final word = switch (action) {
    ScriptBlockMenuAction.copy =>
      scope.neuter ? tr('скопировано') : tr('скопирован'),
    ScriptBlockMenuAction.cut => scope.neuter ? tr('вырезано') : tr('вырезан'),
    ScriptBlockMenuAction.duplicate =>
      scope.neuter ? tr('продублировано') : tr('продублирован'),
    _ => '',
  };
  if (word.isEmpty) return '';
  final noun = _displayScopeNoun(scope.noun);
  final subject = '${noun[0].toUpperCase()}${noun.substring(1)}';
  final contents = scope.container ? tr(' со всем содержимым') : '';
  return '$subject $word$contents';
}

/// Существительное на витрину. `noun` — данные (по нему различают контейнер и
/// листовой блок), поэтому снимается перевод здесь, литералами: гард видит
/// только литералы и не проверяет `tr(переменная)`.
String _displayScopeNoun(String noun) {
  return switch (noun) {
    'событие' => tr('событие'),
    'условие' => tr('условие'),
    'цикл' => tr('цикл'),
    'кроссфейд' => tr('кроссфейд'),
    _ => tr('блок'),
  };
}

/// Подсказки-заполнители полей блока. Значения по умолчанию живут в модели
/// и в файлах квестов (`block_models.dart`), поэтому перевести их в данных
/// нельзя — старые файлы остались бы русскими. Снимаем на витрине и только
/// известные заглушки: всё, что автор ввёл сам, проходит как есть.
String displayFieldSentinel(String value) {
  return switch (value) {
    'Не выбрана' => tr('Не выбрана'),
    'Не выбран' => tr('Не выбран'),
    'Не выбрано' => tr('Не выбрано'),
    'Выберите объект' => tr('Выберите объект'),
    'Выберите ноду' => tr('Выберите ноду'),
    'Выберите скрипт' => tr('Выберите скрипт'),
    'Выберите функцию' => tr('Выберите функцию'),
    'Выберите аудио' => tr('Выберите аудио'),
    'Выберите музыку' => tr('Выберите музыку'),
    'Выберите .lua' => tr('Выберите .lua'),
    'Все звуки' => tr('Все звуки'),
    'имя_переменной' => tr('имя_переменной'),
    'Нода' => tr('Нода'),
    'Скрипт не найден' => tr('Скрипт не найден'),
    _ => value,
  };
}

/// Глобальные настройки отображения полей блоков. Позже легко привязать к
/// пользовательским настройкам редактора (кому-то удобнее с иконками).
class ScriptBlockFieldStyle {
  ScriptBlockFieldStyle._();

  /// Показывать ли иконку-обозначение слева в каждом поле блока.
  static bool showFieldIcons = false;

  /// Показывать ли стрелку (chevron) справа в полях с действием.
  static bool showFieldChevrons = false;

  /// Показывать ли крестик удаления в шапке каждого блока. По умолчанию нет:
  /// удаление живёт в меню блока (тап по карточке), а постоянный крестик на
  /// двадцати карточках подряд превращал список в сетку кнопок удаления.
  static bool showHeaderDelete = false;
}

class ScriptBlockShell extends StatefulWidget {
  /// Подпись меню листового блока. Любая другая подпись означает контейнер:
  /// операции над ним захватывают его содержимое.
  static const String leafScope = 'блок';

  final BlockCategory category;
  final String title;
  final IconData? icon;

  /// Собственные поля блока — внутри карточки, под шапкой.
  final Widget? child;

  /// Вложенные блоки контейнера — ПЛОСКИМИ карточками под его карточкой, а не
  /// внутри цветного корпуса. Так событие перестаёт быть фоном для всего
  /// скрипта, а цикл — толстым конвертом вокруг своих действий.
  final Widget? body;

  /// Заглушка, которой кончается область контейнера («Конец цикла»). Пусто —
  /// область кончается следующим блоком того же уровня (так у события:
  /// следующая шляпа начинает новый скрипт).
  final String? endLabel;

  final VoidCallback? onDelete;
  final bool confirmDelete;

  /// Меню действий по одиночному тапу.
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;

  /// Можно ли сворачивать содержимое блока.
  final bool collapsible;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  /// Дополнительный виджет в шапке — встраивается после заголовка,
  /// перед Spacer.
  final Widget? headerSuffix;

  /// Чему принадлежат операции меню: «блок» (листовой блок) или «событие»,
  /// «условие», «цикл», «кроссфейд» (контейнер). Подпись появляется в пунктах
  /// меню, в подсказке крестика и в подтверждении удаления, а для контейнера
  /// меню вешается только на шапку: поля и дети контейнера живут под ней, и
  /// тап по их пустым местам открывал меню всего контейнера — «дублируешь
  /// один блок, а дублируется целое событие».
  ///
  /// Берут из [blockScope]: `menuScope: blockScope(block).noun`.
  final String menuScope;

  const ScriptBlockShell({
    super.key,
    required this.category,
    required this.title,
    this.icon,
    this.child,
    this.body,
    this.endLabel,
    this.onDelete,
    this.confirmDelete = true,
    this.onMenuAction,
    this.collapsible = false,
    this.collapsed = false,
    this.onToggleCollapse,
    this.headerSuffix,
    this.menuScope = leafScope,
  });

  /// true, если меню относится к контейнеру, а не к листовому блоку.
  bool get targetsContainer => menuScope != leafScope;

  @override
  State<ScriptBlockShell> createState() => _ScriptBlockShellState();
}

class _ScriptBlockShellState extends State<ScriptBlockShell> {
  // Координаты последнего тапа — чтобы открыть меню у точки касания.
  Offset _lastTapPosition = Offset.zero;
  // Время начала нажатия — чтобы отличить короткий тап (меню) от долгого
  // удержания (перетаскивание блока через LongPressDraggable).
  DateTime? _pointerDownAt;
  // Сдвинулся ли палец заметно с момента нажатия (значит это скролл/драг,
  // а не тап по блоку для открытия меню).
  bool _movedSinceDown = false;
  Offset _downGlobalPosition = Offset.zero;

  Future<void> _openMenu(BuildContext context, Offset tapPos) async {
    if (widget.onMenuAction == null) return;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final scheme = Theme.of(context).colorScheme;
    // Существительное в пункте меню говорит, ЧТО именно операция: целое
    // событие или один блок внутри него. `menuScope` — данные (по нему
    // различают листовой блок и контейнер), переводят только на витрину.
    final scope = _displayScopeNoun(widget.menuScope);
    final selected = await showMenu<ScriptBlockMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromCenter(center: tapPos, width: 0, height: 0),
        Offset.zero & overlay.size,
      ),
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      // Штатный потолок в 334px не оставляет места подписи «Глагол +
      // существительное».
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 380),
      items: [
        _menuItem(
          ScriptBlockMenuAction.copy,
          Icons.copy_rounded,
          trf('Копировать {scope}', {'scope': scope}),
          scheme,
        ),
        _menuItem(
          ScriptBlockMenuAction.cut,
          Icons.content_cut_rounded,
          trf('Вырезать {scope}', {'scope': scope}),
          scheme,
        ),
        _menuItem(
          ScriptBlockMenuAction.duplicate,
          Icons.copy_all_rounded,
          trf('Дублировать {scope}', {'scope': scope}),
          scheme,
        ),
        _menuItem(
          ScriptBlockMenuAction.paste,
          Icons.content_paste_rounded,
          tr('Вставить'),
          scheme,
        ),
        if (widget.onDelete != null)
          _menuItem(
            ScriptBlockMenuAction.delete,
            Icons.delete_outline_rounded,
            trf('Удалить {scope}', {'scope': scope}),
            scheme,
            danger: true,
          ),
      ],
    );
    if (selected != null) widget.onMenuAction!(selected);
  }

  PopupMenuItem<ScriptBlockMenuAction> _menuItem(
    ScriptBlockMenuAction value,
    IconData icon,
    String label,
    ColorScheme scheme, {
    bool danger = false,
  }) {
    final color = danger ? scheme.error : scheme.onSurface;
    return PopupMenuItem(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          // Подпись с существительным («Копировать событие») длиннее голого
          // глагола, а ширина меню ограничена — без Flexible она лезет за край.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context) async {
    if (widget.onDelete == null) return;
    if (!widget.confirmDelete) {
      widget.onDelete!();
      return;
    }
    final scope = _displayScopeNoun(widget.menuScope);
    final ok = await confirmBlockDeletion(
      context,
      title: trf('Удалить {scope}?', {'scope': scope}),
      message: widget.targetsContainer
          ? trf(
              'Удалится {scope} со всем содержимым. Действие нельзя отменить.',
              {'scope': scope},
            )
          : tr('Действие нельзя отменить.'),
    );
    if (ok) widget.onDelete!();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = blockAccent(theme.brightness, widget.category);
    final tileIcon = widget.icon ?? iconForCategory(widget.category);
    // Шляпа у события: оно начинает скрипт, и в списке его надо видеть краем
    // карточки, а не ещё одним блоком.
    final hatRise = widget.category == BlockCategory.event
        ? blockHatRise
        : 0.0;
    // Собственные поля блока живут в карточке, вложенные блоки — под ней.
    // Сворачивание прячет и те, и другие: шапка обязана остаться читаемой,
    // иначе свёрнутый блок показывает то же, что и развёрнутый.
    final folds = widget.collapsible && widget.collapsed;
    final hasFields = widget.child != null && !folds;
    final hasBody = widget.body != null && !folds;

    final header = _ShellHeader(
      fg: blockFg,
      tileIcon: tileIcon,
      title: widget.title,
      onDelete: ScriptBlockFieldStyle.showHeaderDelete &&
              widget.onDelete != null
          ? () => _handleDelete(context)
          : null,
      deleteTooltip: trf('Удалить {p0}', {
        'p0': _displayScopeNoun(widget.menuScope),
      }),
      collapsible: widget.collapsible,
      collapsed: widget.collapsed,
      onToggleCollapse: widget.onToggleCollapse,
      headerSuffix: widget.headerSuffix,
    );

    // У контейнера меню живёт только на шапке: поля под ней относятся к
    // конкретному полю, а тап по пустому месту строки заголовка всё равно
    // должен открывать меню контейнера — поэтому под шапкой прозрачный
    // ColoredBox, в который попадает хит-тест.
    final cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.targetsContainer)
          _blockGesture(
            context,
            ColoredBox(color: Colors.transparent, child: header),
          )
        else
          header,
        if (hasFields)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 10, 7),
            child: widget.child!,
          ),
      ],
    );

    final card = Padding(
      // 2 px вместо 4: весь rest зазора теперь отдаён зоне вставки (12 px),
      // и карточки не разъезжаются на треть экрана.
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: fill,
        shape: ScriptBlockShape(radius: 16, hatRise: hatRise),
        clipBehavior: Clip.antiAlias,
        // Цвета плашек раздаются отсюда и шапке, и полям: чип значения в
        // шапке сидит на том же залитом корпусе, где роли темы уже не
        // работают.
        child: Theme(
          data: blockCardTheme(context),
          child: ShellInherited(
            onColor: blockFg,
            subtleColor: blockFieldFill,
            child: Padding(
              // Карточка выше на высоту шляпы, и содержимое уходит под неё:
              // иначе заголовок лезет в пустой клин над поднятой кромкой.
              padding: EdgeInsets.only(top: hatRise),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: blockFg),
                child: IconTheme.merge(
                  data: const IconThemeData(color: blockFg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Не const: подпись тултипа зависит от активного языка, а
                      // const-инстанс экран пережил бы смену языка старой
                      // строкой.
                      _BlockDragHandle(),
                      Expanded(
                        child: widget.targetsContainer
                            ? cardContent
                            : _blockGesture(context, cardContent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!hasBody && widget.endLabel == null) return card;

    // Дети контейнера — плоские карточки того же ширины, что и сам контейнер:
    // ни шахты, ни отступа, который съедал бы место на телефоне. Цвет
    // контейнера остаётся виден подписью ветки и заглушкой конца области.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        card,
        ScriptScope(
          accent: fill,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasBody) widget.body!,
              if (widget.endLabel != null)
                _ScopeEndBar(label: widget.endLabel!),
            ],
          ),
        ),
      ],
    );
  }

  /// Меню открываем через Listener + GestureDetector: меню показываем
  /// ТОЛЬКО если палец не сдвинулся (не скролл/драг) И удержание было
  /// коротким (короче delay LongPressDraggable — иначе это «взять блок»).
  /// Так «зажатие» инициирует перетаскивание, а не открывает меню.
  Widget _blockGesture(BuildContext context, Widget content) {
    if (widget.onMenuAction == null) return content;
    return Listener(
      onPointerDown: (event) {
        _pointerDownAt = DateTime.now();
        _downGlobalPosition = event.position;
        _lastTapPosition = event.position;
        _movedSinceDown = false;
      },
      onPointerMove: (event) {
        if ((event.position - _downGlobalPosition).distance > 8) {
          _movedSinceDown = true;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () {
          final downAt = _pointerDownAt;
          _pointerDownAt = null;
          // Палец сдвинулся — это был скролл/драг, не меню.
          if (_movedSinceDown) return;
          // Долгое удержание — это попытка перетащить блок
          // (LongPressDraggable, delay 150мс), а не открытие меню.
          // Порог чуть меньше delay, чтобы зажатие всегда уходило в
          // перетаскивание, а меню открывалось только коротким тапом.
          if (downAt != null &&
              DateTime.now().difference(downAt) >
                  const Duration(milliseconds: 140)) {
            return;
          }
          _openMenu(context, _lastTapPosition);
        },
        // Правая кнопка — ПК-эквивалент короткого тапа: меню блока
        // открывается у курсора и не спорит с драгом за ручку.
        onSecondaryTapUp: (details) =>
            _openMenu(context, details.globalPosition),
        child: content,
      ),
    );
  }
}

/// Ручка перетаскивания блока. Тянуть можно за любое место (LongPressDraggable
/// висит на всём блоке), но без видимой ручки это не найти: черта слева
/// говорит, что блок берут, и не даёт перепутать карточку с обычным списком.
class _BlockDragHandle extends StatelessWidget {
  const _BlockDragHandle();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('Удерживайте, чтобы перетащить блок'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
        child: Icon(
          Icons.sort_rounded,
          size: 18,
          color: blockFg.withValues(alpha: 0.62),
        ),
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  final Color fg;
  final IconData tileIcon;
  final String title;
  final VoidCallback? onDelete;
  final String? deleteTooltip;
  final bool collapsible;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final Widget? headerSuffix;

  const _ShellHeader({
    required this.fg,
    required this.tileIcon,
    required this.title,
    this.onDelete,
    this.deleteTooltip,
    this.collapsible = false,
    this.collapsed = false,
    this.onToggleCollapse,
    this.headerSuffix,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 9, 6, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Иконка категории — белый силуэт без плашки: на цветном корпусе
          // плашка в тон читается как лишнее пятно.
          Icon(tileIcon, color: fg, size: 17),
          const SizedBox(width: 8),
          // Заголовок и чип значения делят одно Expanded: Row-спейсер тоже
          // гибкий, и с ним чип навсегда оставался бы в трети ширины —
          // «Если / Иначе» обрезал условие на двух словах. Короткий
          // заголовок уступает свободное место чипу.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  flex: 2,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: 0.05,
                    ),
                  ),
                ),
                if (headerSuffix != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    flex: 3,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: fg),
                      child: IconTheme.merge(
                        data: IconThemeData(color: fg),
                        child: headerSuffix!,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Стрелка сворачивания — справа, как и у остальных раскрывающихся
          // строк: слева она спорила с ручкой перетаскивания.
          if (collapsible)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggleCollapse,
              child: SizedBox(
                width: 26,
                height: 26,
                child: Center(
                  child: Icon(
                    collapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                    color: fg,
                    size: 18,
                  ),
                ),
              ),
            ),
          if (onDelete != null)
            // Крестик приглушён: ярче заголовка он перетягивает тап.
            IconTheme.merge(
              data: IconThemeData(color: fg.withValues(alpha: 0.6)),
              child: Tooltip(
                message: deleteTooltip ?? tr('Удалить блок'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: onDelete,
                  child: const SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(child: Icon(Icons.close_rounded, size: 16)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
//  ФОРМА КАРТОЧКИ
//
//  У блока события верхняя кромка поднимается слева — «шляпа», как у
//  блоков-стартеров в блочных редакторах. Она говорит про начало скрипта без
//  подписей: список из двадцати карточек читается по краям, а не по тексту.
//  Обычный блок — тот же путь с нулевым подъёмом, то есть скруглённый
//  прямоугольник.
// ============================================================================
class ScriptBlockShape extends ShapeBorder {
  final double radius;

  /// Насколько левый край выше основной кромки; 0 — плоская карточка.
  final double hatRise;

  const ScriptBlockShape({this.radius = 16, this.hatRise = 0});

  static const double _plateauAt = 0.30;
  static const double _footAt = 0.70;

  Path _outer(Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final rad = radius < w / 2 && radius < h / 2 ? radius : (w < h ? w : h) / 2;
    if (hatRise <= 0 || w < radius * 4) {
      return Path()
        ..addRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: Radius.circular(rad),
            topRight: Radius.circular(rad),
            bottomLeft: Radius.circular(rad),
            bottomRight: Radius.circular(rad),
          ),
        );
    }
    final plateau = w * _plateauAt;
    final foot = w * _footAt;
    final bend = (foot - plateau) / 2;
    final path = Path()
      ..moveTo(rad, 0)
      ..lineTo(plateau, 0)
      // Плавный спуск к основной кромке: контрольные точки стоят на своих
      // уровнях, поэтому кромка входит в подъём и в тело без уголка.
      ..cubicTo(plateau + bend, 0, foot - bend, hatRise, foot, hatRise)
      ..lineTo(w - rad, hatRise)
      ..arcToPoint(Offset(w, hatRise + rad), radius: Radius.circular(rad))
      ..lineTo(w, h - rad)
      ..arcToPoint(Offset(w - rad, h), radius: Radius.circular(rad))
      ..lineTo(rad, h)
      ..arcToPoint(Offset(0, h - rad), radius: Radius.circular(rad))
      ..lineTo(0, rad)
      ..arcToPoint(Offset(rad, 0), radius: Radius.circular(rad))
      ..close();
    return path;
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = _outer(rect.size);
    if (rect.left != 0 || rect.top != 0) {
      return path.shift(Offset(rect.left, rect.top));
    }
    return path;
  }

  // Рамки у карточки нет, поэтому внутренняя граница совпадает с внешней.
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  EdgeInsetsGeometry get dimensions =>
      EdgeInsets.fromLTRB(radius, radius + hatRise, radius, radius);

  @override
  ShapeBorder scale(double t) =>
      ScriptBlockShape(radius: radius * t, hatRise: hatRise * t);

  ScriptBlockShape _mix(ScriptBlockShape? other, double t) {
    if (other == null) return this;
    return ScriptBlockShape(
      radius: other.radius + (radius - other.radius) * t,
      hatRise: other.hatRise + (hatRise - other.hatRise) * t,
    );
  }

  @override
  ShapeBorder lerpFrom(ShapeBorder? a, double t) =>
      a is ScriptBlockShape ? _mix(a, t) : this;

  @override
  ShapeBorder lerpTo(ShapeBorder? b, double t) =>
      b is ScriptBlockShape ? _mix(b, t) : this;

  @override
  bool operator ==(Object other) =>
      other is ScriptBlockShape &&
      other.radius == radius &&
      other.hatRise == hatRise;

  @override
  int get hashCode => Object.hash(radius, hatRise);
}

// ============================================================================
//  ОБЛАСТЬ КОНТЕЙНЕРА
//
//  Дети контейнера больше не сидят в его цветном корпусе, поэтому цвет
//  контейнера переехал на подписи: [ScriptBranchCaption] называет ветку,
//  заглушка «Конец цикла» показывает, где область кончается. Обе берут цвет
//  отсюда — виджету блока не нужно знать палитру категорий.
// ============================================================================
class ScriptScope extends InheritedWidget {
  final Color accent;

  const ScriptScope({super.key, required this.accent, required super.child});

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScriptScope>()?.accent ??
      Theme.of(context).colorScheme.primary;

  @override
  bool updateShouldNotify(ScriptScope oldWidget) =>
      oldWidget.accent != accent;
}

/// Подпись ветки контейнера («Если истина», «Во время перехода»).
class ScriptBranchCaption extends StatelessWidget {
  final String label;
  final IconData? icon;

  const ScriptBranchCaption({super.key, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = ScriptScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 1),
      child: Row(
        children: [
          Icon(icon ?? Icons.arrow_right_rounded, size: 14, color: accent),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                fontSize: 9.5,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заглушка конца области — та же карточка и тот же цвет, что у контейнера,
/// но тонкая: она отмечает границу, а не просит внимания к себе.
class _ScopeEndBar extends StatelessWidget {
  final String label;

  const _ScopeEndBar({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 2),
      child: Material(
        color: ScriptScope.of(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          // Отступ как у заголовка блока (ручка + её поля), чтобы подпись
          // конца области стояла в одной вертикали с названиями блоков.
          padding: const EdgeInsets.fromLTRB(32, 6, 14, 6),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: blockFg,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  ЧИП ЗНАЧЕНИЯ В ШАПКЕ — условие, таблица, режим цикла. Язык тот же, что у
//  полей в теле: тёмная плашка поверх цветного корпуса и белая черта снизу.
//  Раньше три блока лепили свой копи-пастом с подложкой из жёсткого чёрного,
//  из-за чего в светлой теме чип выглядел грязным пятном.
// ============================================================================

class ShellValueChip extends StatelessWidget {
  final String value;
  final String placeholder;
  final VoidCallback? onTap;

  /// Потолок ширины — для чипов, где значение всегда короткое (режим цикла).
  final double? maxWidth;

  /// Значок перед значением — для бейджей вроде «функция вызывается извне».
  final IconData? icon;

  const ShellValueChip({
    super.key,
    required this.value,
    required this.placeholder,
    this.onTap,
    this.maxWidth,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inh = ShellInherited.maybeOf(context);
    final onColor = inh?.onColor ?? theme.colorScheme.onSurface;
    final fill = inh?.subtleColor ?? theme.colorScheme.surfaceContainerHigh;
    final isEmpty = value.trim().isEmpty;

    final label = Text(
      isEmpty ? placeholder : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: onColor.withValues(alpha: isEmpty ? 0.6 : 0.95),
        fontWeight: FontWeight.w600,
        fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
        // Значение чипа — идентификатор или выражение: на насыщенном корпусе
        // пропорциональный шрифт сливает `flag_door_open` в кашу.
        fontFamily: isEmpty ? null : 'monospace',
        fontSize: 11,
        letterSpacing: 0.2,
        height: 1.15,
      ),
    );

    final content = icon == null
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11),
              const SizedBox(width: 4),
              Flexible(child: label),
            ],
          );

    Widget chip = _ChipSurface(
      fill: fill,
      lineColor: onColor.withValues(alpha: 0.6),
      radius: 8,
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
      onTap: onTap,
      child: content,
    );
    if (maxWidth != null) {
      chip = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: chip,
      );
    }
    return chip;
  }
}

/// Наследуемый контейнер, чтобы внутренние плашки знали цвета блока.
///
/// Акцент категории сюда не нужен: корпус уже в цвете категории, поэтому
/// плашки различаются яркостью подложки и белой чертой, а не цветом.
class ShellInherited extends InheritedWidget {
  final Color onColor;
  final Color subtleColor;

  const ShellInherited({
    super.key,
    required this.onColor,
    required this.subtleColor,
    required super.child,
  });

  static ShellInherited? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellInherited>();

  @override
  bool updateShouldNotify(ShellInherited old) =>
      onColor != old.onColor || subtleColor != old.subtleColor;
}

// ============================================================================
//  ПЛАШКА ЗНАЧЕНИЯ — тёмная подложка поверх залитого корпуса и белая черта
//  снизу. Роли темы (outlineVariant, error) на цветном корпусе не читаются,
//  поэтому язык плашек один: подложка + черта, а сигнал «пусто и обязательно»
//  — рамка по всему периметру.
// ============================================================================

class _ChipSurface extends StatelessWidget {
  final Color fill;
  final Color lineColor;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool alert;
  final VoidCallback? onTap;
  final Widget child;

  const _ChipSurface({
    required this.fill,
    required this.lineColor,
    required this.radius,
    required this.padding,
    required this.child,
    this.alert = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Padding(padding: padding, child: child);
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: alert
            ? const BorderSide(color: blockFieldAlert, width: 1.4)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (onTap == null)
            inner
          else
            InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: inner,
            ),
          // Черта прижата к нижнему краю и укорочена на радиус — иначе вылезала
          // бы за скругление угла.
          if (!alert)
            Positioned(
              left: radius,
              right: radius,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1.6,
                  decoration: BoxDecoration(
                    color: lineColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
//  ПОЛЕ — подпись и значение в одну строку. Тёмная плашка с белой чертой, чтобы
//  не путалось с обычным текстом на цветном корпусе.
// ============================================================================

class ScriptFieldTile extends StatelessWidget {
  final String label;
  final String value;
  final String placeholder;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Мини-подсказка второй строкой: что сюда писать. видна только когда её
  /// явно попросили — остальные поля блока остаются компактными.
  final String? hint;

  const ScriptFieldTile({
    super.key,
    required this.label,
    required this.value,
    this.placeholder = '…',
    this.icon,
    this.onTap,
    this.trailing,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final inh = ShellInherited.maybeOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onColor = inh?.onColor ?? scheme.onSurface;
    final subtle = inh?.subtleColor ?? scheme.surfaceContainerHigh;
    final labelColor = onColor.withValues(alpha: 0.82);
    final isEmpty = value.trim().isEmpty;

    // Подпись и значение в одну строку: блок читается фразой («переменная
    // flag_door»), а не колонкой из двух строк на каждое поле — из-за колонки
    // скрипт из десяти блоков не влезал в экран. mainAxisSize.min держит
    // плашку по контенту, поэтому короткое значение («X: 100») не растягивается
    // на всю ширину карточки.
    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null && ScriptBlockFieldStyle.showFieldIcons) ...[
          Icon(icon, color: labelColor, size: 13),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              height: 1.1,
              fontSize: 11.5,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            isEmpty ? placeholder : displayFieldSentinel(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isEmpty ? labelColor : onColor,
              fontWeight: FontWeight.w700,
              fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
              fontFamily: isEmpty ? null : 'monospace',
              height: 1.15,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        if (trailing == null &&
            onTap != null &&
            ScriptBlockFieldStyle.showFieldChevrons) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, color: labelColor, size: 14),
        ],
      ],
    );

    // Пустое редактируемое поле помечено рамкой: молчащий блок с пустым
    // «Переменная»/«Путь» был источником жалоб #220 и #222. Рамка белая —
    // `scheme.error` на залитом корпусе не читается, см. [blockFieldAlert].
    return _ChipSurface(
      fill: subtle,
      lineColor: onColor.withValues(alpha: 0.55),
      radius: 8,
      alert: isEmpty && onTap != null,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          line,
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              hint!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                // Не глуше подписи: на цветном корпусе следующий по
                // яркости оттенок уже не дотягивает до читаемого.
                color: labelColor,
                fontStyle: FontStyle.italic,
                height: 1.1,
                fontSize: 9.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ScriptFieldsGroup extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const ScriptFieldsGroup({
    super.key,
    required this.children,
    this.spacing = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: fieldFlowRows(children, spacing),
    );
  }
}

/// Ряды группы полей. Подряд идущие чипы-поля текут по строкам — «X: 100
/// Y: 100» становятся одним рядом, как во фразе. Остальным (слайдер,
/// сегменты, кнопка) нужна полная ширина, поэтому каждый занимает ряд сам.
List<Widget> fieldFlowRows(List<Widget> children, double spacing) {
  final rows = <Widget>[];
  var chips = <Widget>[];

  void addRow(Widget row) {
    if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
    rows.add(row);
  }

  void flushChips() {
    if (chips.isEmpty) return;
    addRow(
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: spacing, runSpacing: spacing, children: chips),
      ),
    );
    chips = <Widget>[];
  }

  for (final child in children) {
    if (child is ScriptFieldTile) {
      chips.add(child);
    } else {
      flushChips();
      addRow(child);
    }
  }
  flushChips();
  return rows;
}

/// Компактная сетка полей. С тех пор как поле стало однострочным и держит
/// ширину по контенту, раскладка «по два в ряд через Expanded» не нужна:
/// сколько коротких полей влезло в строку — столько и стало рядом.
class ScriptFieldsGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const ScriptFieldsGrid({super.key, required this.children, this.spacing = 6});

  @override
  Widget build(BuildContext context) =>
      ScriptFieldsGroup(children: children, spacing: spacing);
}

// ============================================================================
//  SLIDER
// ============================================================================

class ScriptFieldSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double)? formatter;
  final ValueChanged<double>? onChanged;
  final IconData? icon;

  const ScriptFieldSlider({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.formatter,
    this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final inh = ShellInherited.maybeOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onColor = inh?.onColor ?? scheme.onSurface;
    final subtle = inh?.subtleColor ?? scheme.surfaceContainerHigh;
    final labelColor = onColor.withValues(alpha: 0.82);
    final formatted = formatter != null
        ? formatter!(value)
        : value.toStringAsFixed(2);
    return _ChipSurface(
      fill: subtle,
      lineColor: onColor.withValues(alpha: 0.55),
      radius: 8,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null && ScriptBlockFieldStyle.showFieldIcons) ...[
                Icon(icon, color: labelColor, size: 13),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    fontSize: 10.5,
                  ),
                ),
              ),
              Text(
                formatted,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onColor,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          // Белые дорожка и ручка: акцент категории больше не нужен — сам
          // корпус блока этот акцент и рисует.
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: onColor,
              inactiveTrackColor: onColor.withValues(alpha: 0.3),
              thumbColor: onColor,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  SEGMENTED
// ============================================================================

class ScriptFieldSegmented<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<({T value, String label, IconData? icon})> options;
  final ValueChanged<T>? onChanged;
  final IconData? icon;

  const ScriptFieldSegmented({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final inh = ShellInherited.maybeOf(context);
    final theme = Theme.of(context);
    final onColor = inh?.onColor ?? theme.colorScheme.onSurface;
    final subtle = inh?.subtleColor ?? theme.colorScheme.surfaceContainerHigh;
    final labelColor = onColor.withValues(alpha: 0.82);
    return _ChipSurface(
      fill: subtle,
      lineColor: onColor.withValues(alpha: 0.55),
      radius: 8,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null && ScriptBlockFieldStyle.showFieldIcons) ...[
                Icon(icon, color: labelColor, size: 13),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // Компактные сегменты: уменьшенный шрифт и паддинги — чтобы подписи
          // не переносились по буквам и блок не вытягивался по высоте.
          // Цвета заданы явно: дефолт SegmentedButton берёт `secondary` из
          // темы и на залитом корпусе выбранная долька не отличима.
          SegmentedButton<T>(
            showSelectedIcon: false,
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
              side: WidgetStatePropertyAll(
                BorderSide(color: onColor.withValues(alpha: 0.28)),
              ),
              // Выбранная долька светлее остальных: на залитом корпусе цвет
              // акцента темы не читается, поэтому подсветка — белый.
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? onColor.withValues(alpha: 0.24)
                    : Colors.transparent,
              ),
              foregroundColor: WidgetStatePropertyAll(onColor),
            ),
            segments: [
              for (final opt in options)
                ButtonSegment(
                  value: opt.value,
                  label: Text(opt.label, overflow: TextOverflow.ellipsis),
                  icon: opt.icon != null ? Icon(opt.icon, size: 13) : null,
                ),
            ],
            selected: {value},
            onSelectionChanged: onChanged == null
                ? null
                : (set) => onChanged!(set.first),
          ),
        ],
      ),
    );
  }
}
