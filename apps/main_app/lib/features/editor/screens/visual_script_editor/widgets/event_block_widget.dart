import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/reorderable_block_list.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/table_path_picker.dart';
import 'package:canvas_app/models/quest_table_model.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:mnd_player/utils/file_storage.dart';

// ============================================================================
//  EVENT BLOCK — Material 3 (тема)
// ============================================================================
//
//  Корневой блок-контейнер скрипта. Использует тот же `ScriptBlockShell`, что
//  и обычные блоки — но с двумя дополнительными вкладами:
//   • при типе Function — отображается «карточка функции» (ScriptFieldTile)
//   • в теле — заголовок «Содержимое» + ReorderableBlockList
//
//  Все цвета берутся ИСКЛЮЧИТЕЛЬНО из Theme.of(context).colorScheme:
//  primary/primaryContainer для иконки события (через ScriptBlockShell),
//  onSurface/onSurfaceVariant для текста, surfaceContainerHighest для
//  внутренних плашек.
// ============================================================================

typedef OnBlockDrop =
    void Function(
      VisualScriptBlock droppedBlock,
      List<VisualScriptBlock> targetList,
    );

class EventBlockWidget extends ConsumerStatefulWidget {
  final EventBlock block;
  final String questId;
  final List<String> availableFunctionNames;
  final VoidCallback? onDelete;
  final OnBlockDrop onBlockDrop;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// Меню самого события (короткий тап). Операции над списком-владельцем
  /// знает только экран, поэтому обрабатывает он: дубликат и вставка
  /// происходят рядом с событием, а не внутрь его детей.
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;

  /// Резолвер GlobalKey по id блока — нужен экрану, чтобы измерить позиции
  /// дочерних блоков и понять, куда (ближе к центру экрана) вставлять новый.
  final GlobalKey Function(String id)? blockKeyResolver;

  const EventBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.availableFunctionNames = const [],
    this.onDelete,
    required this.onBlockDrop,
    this.onDragUpdate,
    this.onDragStart,
    this.onDragEnd,
    this.onMenuAction,
    this.blockKeyResolver,
  });

  @override
  ConsumerState<EventBlockWidget> createState() => _EventBlockWidgetState();
}

class _EventBlockWidgetState extends ConsumerState<EventBlockWidget> {
  // ---------------------------------------------------------------------------
  //  HELPERS
  // ---------------------------------------------------------------------------

  String _eventTitle(EventType type) {
    switch (type) {
      case EventType.onQuestStart:
        return tr('При запуске квеста');
      case EventType.onNodeEnter:
        return tr('При входе в ноду');
      case EventType.onPress:
        return tr('По нажатию');
      case EventType.onContentAppear:
        return tr('При появлении контента');
      case EventType.onDataChange:
        return tr('При изменении данных');
      case EventType.function:
        return tr('Функция');
    }
  }

  String _eventSubtitle(EventType type) {
    // Используется только в bottom sheet выбора типа события — оставлено как
    // подсказка в списке.
    switch (type) {
      case EventType.onQuestStart:
        return tr('Один раз при запуске игры, до первой ноды. Скрипт с таким блоком в папке scripts/ движок находит сам.');
      case EventType.onNodeEnter:
        return tr('Срабатывает при заходе на ноду');
      case EventType.onPress:
        return tr('Срабатывает при нажатии');
      case EventType.onContentAppear:
        return tr('Срабатывает при показе элемента');
      case EventType.onDataChange:
        return tr('Срабатывает, когда меняется один из указанных путей: переменная, ключ таблицы или ячейка. * — следить за всем.');
      case EventType.function:
        return tr('Вызывается по имени');
    }
  }

  IconData _eventIcon(EventType type) {
    switch (type) {
      case EventType.onQuestStart:
        return Icons.play_circle_outline_rounded;
      case EventType.onNodeEnter:
        return Icons.login_rounded;
      case EventType.onPress:
        return Icons.touch_app_rounded;
      case EventType.onContentAppear:
        return Icons.visibility_rounded;
      case EventType.onDataChange:
        return Icons.change_circle_rounded;
      case EventType.function:
        return Icons.functions_rounded;
    }
  }

  // ---------------------------------------------------------------------------
  //  ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _selectEventType() async {
    final current = widget.block.eventType ?? EventType.onNodeEnter;
    final value = await showAdaptiveSheet<EventType>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  tr('Тип события'),
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ...EventType.values.map((type) {
                final isSelected = type == current;
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _eventIcon(type),
                      color: isSelected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    _eventTitle(type),
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(_eventSubtitle(type)),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: scheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, type),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (value != null && value != current) {
      setState(() => widget.block.eventType = value);
    }
  }

  Future<void> _editWatchPaths() async {
    final result = await showAdaptiveSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // Скролл внутри шита: подсказки и кнопки должны влезать вместе.
      scrollable: false,
      builder: (ctx) => _WatchPathsSheet(
        questId: widget.questId,
        initial: widget.block.watchPaths,
      ),
    );
    if (result != null) {
      setState(() => widget.block.watchPaths = result);
    }
  }

  Future<void> _selectFunctionName() async {
    final names = <String>{
      'main',
      widget.block.functionName.trim().isEmpty
          ? 'main'
          : widget.block.functionName.trim(),
      ...widget.availableFunctionNames
          .where((e) => e.trim().isNotEmpty)
          .map((e) => e.trim()),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final value = await showAdaptiveSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      scrollable: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('Выбор функции'),
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                title: Text(
                  tr('Новая функция'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(tr('Создать с нуля')),
                onTap: () => Navigator.pop(ctx, '__create__'),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: names.length,
                  itemBuilder: (_, i) {
                    final name = names[i];
                    final isSelected = name == widget.block.functionName;
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isSelected
                              ? Icons.check_rounded
                              : Icons.functions_rounded,
                          color: isSelected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, name),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (value == null) return;
    if (value == '__create__') {
      final created = await _createFunctionName();
      if (created == null) return;
      if (!mounted) return;
      setState(() {
        widget.block.functionName = created;
      });
      return;
    }
    setState(() {
      widget.block.functionName = value;
    });
  }

  Future<String?> _createFunctionName() async {
    final controller = TextEditingController();
    final created = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Новая функция')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Имя функции'),
            hintText: 'checkVisibility',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(tr('Создать')),
          ),
        ],
      ),
    );
    if (created == null || created.isEmpty) return null;
    return created;
  }

  // ---------------------------------------------------------------------------
  //  BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final eventType = widget.block.eventType ?? EventType.onNodeEnter;
    final isFunction = eventType == EventType.function;
    final isDataWatch = eventType == EventType.onDataChange;
    final title = _eventTitle(eventType);

    return ScriptBlockShell(
      category: BlockCategory.event,
      title: title,
      icon: _eventIcon(eventType),
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      menuScope: blockScope(widget.block).noun,
      collapsible: true,
      collapsed: widget.block.collapsed,
      onToggleCollapse: () {
        setState(() {
          widget.block.collapsed = !widget.block.collapsed;
        });
      },
      // Имя и способ запуска видны в свёрнутом блоке: без этого событие-функция
      // выглядит как обычное и юзер ждёт, что нода сама её выполнит.
      headerSuffix: isFunction
          ? _FunctionBadge(name: widget.block.functionName)
          : isDataWatch
          ? _WatchBadge(paths: widget.block.watchPaths)
          : null,
      // Действия скрипта — плоскими карточками под шапкой события, а не
      // внутри цветного корпуса: иначе событие выглядит фоном всего скрипта.
      // Заглушки конца у него нет — следующая шляпа начинает новый скрипт.
      body: ReorderableBlockList(
        blocks: widget.block.children,
        questId: widget.questId,
        onBlockDrop: widget.onBlockDrop,
        allowEventBlocks: false,
        emptyPlaceholder: tr('Перетащите сюда действия'),
        onDragUpdate: widget.onDragUpdate,
        onDragStart: widget.onDragStart,
        onDragEnd: widget.onDragEnd,
        blockKeyResolver: widget.blockKeyResolver,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Компактное pill-поле выбора типа события
          ScriptFieldTile(
            label: tr('Тип'),
            value: title,
            icon: Icons.swap_horiz_rounded,
            onTap: _selectEventType,
          ),
          if (isFunction) ...[
            const SizedBox(height: 4),
            ScriptFieldTile(
              label: tr('Функция'),
              value: widget.block.functionName,
              placeholder: tr('не задана'),
              icon: Icons.tag_rounded,
              onTap: _selectFunctionName,
            ),
            _FunctionHint(),
          ],
          if (isDataWatch) ...[
            const SizedBox(height: 4),
            ScriptFieldTile(
              label: tr('Следить'),
              value: widget.block.watchPaths.join(', '),
              placeholder: tr('любое изменение'),
              icon: Icons.change_circle_rounded,
              onTap: _editWatchPaths,
            ),
            _DataWatchHint(),
          ],
        ],
      ),
    );
  }
}

/// Чип в шапке события-функции: имя + напоминание, что запуск только извне.
///
/// В свёрнутом блоке подсказка из тела не видна, а именно в свёрнутом виде
/// событие-функция чаще всего и выглядит как «обычное» — отсюда ожидание,
/// что нода выполнит скрипт сама.
class _FunctionBadge extends StatelessWidget {
  final String name;
  const _FunctionBadge({required this.name});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    return Tooltip(
      message:
          tr('Вызывается извне: блоком «Вызвать функцию» или триггером. Нода этот скрипт сама не запустит.'),
      child: ShellValueChip(
        value: trimmed,
        placeholder: tr('без имени'),
        icon: Icons.call_missed_outgoing_rounded,
      ),
    );
  }
}

/// Подсказка на событии-функции.
///
/// Скрипт, прикреплённый к ноде, движок запускает на «входе в ноду» и «показе
/// контента». Если единственное его событие — функция, он молча не выполнится
/// никогда: именно так «не работает» блок, добавленный в пустой скрипт.
class _FunctionHint extends StatelessWidget {
  const _FunctionHint();

  @override
  Widget build(BuildContext context) {
    final fg =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: fg.withOpacity(0.7),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              tr('Запускается только по вызову: блоком «Вызвать функцию» или триггером. Прикреплённый к ноде скрипт с одним таким событием не выполнится никогда.'),
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: fg.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Чип в шапке события «При изменении данных».
///
/// В свёрнутом блоке тело с полем «Следить» не видно, а именно по подпискам
/// автор понимает, чем это событие отличается от «при входе в ноду».
class _WatchBadge extends StatelessWidget {
  final List<String> paths;
  const _WatchBadge({required this.paths});

  @override
  Widget build(BuildContext context) {
    // Одно значение + счётчик: список путей длиннее двух слов порвал бы
    // заголовок блока.
    final label = paths.isEmpty
        ? ''
        : paths.length == 1
        ? paths.first
        : '${paths.first} +${paths.length - 1}';
    return Tooltip(
      message: paths.isEmpty
          ? tr('Срабатывает на любое изменение данных.')
          : trf('Следит за: {p0}', {'p0': paths.join(', ')}),
      child: ShellValueChip(
        value: label,
        placeholder: tr('любое изменение'),
        icon: Icons.change_circle_rounded,
        maxWidth: 180,
      ),
    );
  }
}

/// Подсказка на событии «При изменении данных».
///
/// Два факта без текста выглядят багом: скрипт ноды следит только в своей
/// ноде, а собственная запись в подписанный путь запускает событие заново.
class _DataWatchHint extends StatelessWidget {
  const _DataWatchHint();

  @override
  Widget build(BuildContext context) {
    final fg =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: fg.withOpacity(0.7),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              tr('Проверяется на каждом шаге игры: что именно изменилось — в {_changed_path} и {_changed_paths}. Скрипт из scripts/ следит всё время, скрипт ноды — только пока игрок в ней. Запись в подписанный путь вызывает событие заново, но глубже четырёх звеньев цепочка обрывается.'),
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: fg.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Одна подсказка в редакторе подписок: путь и что за значение за ним стоит.
class _WatchSuggestion {
  final String path;
  final String detail;
  const _WatchSuggestion(this.path, this.detail);
}

/// Редактор подписок события «При изменении данных».
///
/// Путей может быть сколько угодно: тап по подсказке добавляет, чип удаляет.
/// В поле ввода запятая разделяет несколько путей — список проще вставить
/// целиком, чем набирать по одному.
class _WatchPathsSheet extends StatefulWidget {
  final String questId;
  final List<String> initial;

  const _WatchPathsSheet({required this.questId, required this.initial});

  @override
  State<_WatchPathsSheet> createState() => _WatchPathsSheetState();
}

class _WatchPathsSheetState extends State<_WatchPathsSheet> {
  final List<String> _paths = [];
  final TextEditingController _manual = TextEditingController();
  List<_WatchSuggestion> _variables = const [];
  List<_WatchSuggestion> _tablePaths = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Дубликаты из прошлой сессии редактирования: множество, а не список.
    _paths.addAll(
      <String>{...widget.initial.map((e) => e.trim()).where((e) => e.isNotEmpty)},
    );
    _load();
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final variables = <_WatchSuggestion>[];
    final tablePaths = <_WatchSuggestion>[];
    // Один путь — одна подсказка: у таблицы ключ данных и столбец сетки
    // вполне могут называться одинаково.
    final seen = <String>{};
    try {
      final configPath = QuestPaths.config(widget.questId);
      if (await FileStorage.exists(configPath)) {
        final config = await FileStorage.readJsonFile(configPath);
        for (final raw
            in config['variables'] as List<dynamic>? ?? const <dynamic>[]) {
          if (raw is! Map) continue;
          final name = '${raw['name'] ?? ''}'.trim();
          // `_…` — служебные переменные движка, их изменений он не отдаёт.
          if (name.isEmpty || name.startsWith('_') || !seen.add(name)) continue;
          variables.add(
            _WatchSuggestion(
              name,
              trf('переменная, значение: {p0}', {'p0': TableDataSnapshot.describeValue(raw['defaultValue'])}),
            ),
          );
        }
        for (final raw
            in config['tables'] as List<dynamic>? ?? const <dynamic>[]) {
          if (raw is! Map) continue;
          final table = QuestTable.fromJson(Map<String, dynamic>.from(raw));
          if (seen.add('${table.name}.*')) {
            tablePaths.add(
              _WatchSuggestion('${table.name}.*', tr('любой ключ таблицы')),
            );
          }
          for (final entry in table.data.entries) {
            if (entry.key.startsWith('__')) continue;
            final path = '${table.name}.${entry.key}';
            if (!seen.add(path)) continue;
            tablePaths.add(
              _WatchSuggestion(
                path,
                trf('ключ таблицы: {p0}', {'p0': TableDataSnapshot.describeValue(entry.value)}),
              ),
            );
          }
          for (final column in table.columns) {
            final path = '${table.name}.$column';
            if (!seen.add(path)) continue;
            tablePaths.add(
              _WatchSuggestion(
                path,
                trf('столбец сетки; одна ячейка — {path}.1, номера рядов с 1', {'path': path}),
              ),
            );
          }
        }
      }
    } catch (_) {
      // Конфиг может быть битым: подсказок нет, ручной ввод работает.
    }
    if (!mounted) return;
    setState(() {
      _variables = variables;
      _tablePaths = tablePaths;
      _loaded = true;
    });
  }

  void _addAll(String raw) {
    final parts = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    setState(() {
      for (final part in parts) {
        if (!_paths.contains(part)) _paths.add(part);
      }
      _manual.clear();
    });
  }

  Widget _suggestionChip(_WatchSuggestion suggestion) {
    final added = _paths.contains(suggestion.path);
    return ActionChip(
      label: Text(suggestion.path),
      tooltip: added ? tr('Уже в подписке') : suggestion.detail,
      avatar: Icon(
        added ? Icons.check_rounded : Icons.add_rounded,
        size: 16,
        color: added ? Theme.of(context).colorScheme.primary : null,
      ),
      onPressed: () => _addAll(suggestion.path),
    );
  }

  Widget _group(String title, List<_WatchSuggestion> items) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final item in items) _suggestionChip(item)],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final noSuggestions = _loaded &&
        _variables.isEmpty &&
        _tablePaths.isEmpty;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Следить за изменениями'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Сразу несколько путей: переменная, ключ таблицы, ячейка сетки или * за всем сразу. Пустой список — событие срабатывает на любое изменение.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (_paths.isEmpty)
              Text(
                tr('Пока ничего не выбрано.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final path in _paths)
                    InputChip(
                      label: Text(path),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      onDeleted: () => setState(() => _paths.remove(path)),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _manual,
              textInputAction: TextInputAction.done,
              onSubmitted: _addAll,
              decoration: InputDecoration(
                isDense: true,
                labelText: tr('Добавить путь'),
                hintText: tr('Здоровье, лавка.цена, лавка.цена.3, *'),
                helperText:
                    tr('Несколько путей — через запятую. Таблицу можно писать и с префиксом: table.лавка.цена.'),
                suffixIcon: IconButton(
                  tooltip: tr('Добавить'),
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => _addAll(_manual.text),
                ),
              ),
            ),
            // Подсказки идут общим потоком со всем шитом: на телефоне высота
            // шита ограничена, а список путей длинный — с отдельным
            // прокручиваемым блоком кнопки уезжали за край экрана.
            _group(tr('Быстрое'), [
              _WatchSuggestion('*', tr('любое изменение в квесте')),
            ]),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              if (_variables.isNotEmpty) _group(tr('Переменные'), _variables),
              if (_tablePaths.isNotEmpty) _group(tr('Таблицы'), _tablePaths),
              if (noSuggestions)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    tr('В квесте пока нет ни переменных, ни таблиц — впишите путь вручную.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Отменить')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, List<String>.from(_paths)),
                    child: Text(tr('Готово')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
