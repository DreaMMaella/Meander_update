import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/reorderable_block_list.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/variable_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  FOR EACH BLOCK — цикл по строкам таблицы
// ============================================================================

typedef OnBlockDrop =
    void Function(
      VisualScriptBlock droppedBlock,
      List<VisualScriptBlock> targetList,
    );

class ForEachBlockWidget extends StatefulWidget {
  final ForEachBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;
  final OnBlockDrop onBlockDrop;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const ForEachBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
    required this.onBlockDrop,
    this.onDragUpdate,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<ForEachBlockWidget> createState() => _ForEachBlockWidgetState();
}

class _ForEachBlockWidgetState extends State<ForEachBlockWidget> {
  /// Дефолты движка (`for_each.rs`): пустое поле = `row`, а не имя таблицы.
  String get _prefix {
    final raw = widget.block.varPrefix.trim();
    return raw.isEmpty ? 'row' : raw;
  }

  String get _counter {
    final raw = widget.block.indexVariable.trim();
    return raw.isEmpty ? 'i' : raw;
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.control,
      title: tr('Для каждой строки'),
      icon: Icons.loop_rounded,
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
      headerSuffix: ShellValueChip(
        value: widget.block.tableName,
        placeholder: tr('таблица…'),
        onTap: () => _editTable(context),
      ),
      // Тело цикла — плоские карточки под блоком.
      body: ReorderableBlockList(
        blocks: widget.block.children,
        questId: widget.questId,
        onBlockDrop: widget.onBlockDrop,
        allowEventBlocks: false,
        emptyPlaceholder: tr('Перетащите действия'),
        onDragUpdate: widget.onDragUpdate,
        onDragStart: widget.onDragStart,
        onDragEnd: widget.onDragEnd,
      ),
      endLabel: tr('Конец цикла'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Поля таблица/префикс/индекс
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Column(
              children: [
                // Таблица
                ScriptFieldTile(
                  label: tr('Таблица'),
                  icon: Icons.dataset_rounded,
                  value: widget.block.tableName,
                  placeholder: tr('имя таблицы'),
                  hint: tr('ряды сетки, не ключи хранилища'),
                  onTap: () => _editTable(context),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: ScriptFieldTile(
                        label: tr('Префикс'),
                        icon: Icons.label_outline_rounded,
                        value: widget.block.varPrefix,
                        placeholder: _prefix,
                        onTap: () => _editPrefix(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: ScriptFieldTile(
                        label: tr('Индекс'),
                        icon: Icons.tag_rounded,
                        value: widget.block.indexVariable,
                        placeholder: _counter,
                        onTap: () => _editIndex(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Имена переменных собирает движок из префикса и столбцов.
                // Без строки-подсказки автор угадывает и получает пустоту
                // вместо `{row_name}` в тексте.
                Text(
                  trf('Столбцы строки: {{p0}_имя_столбца}, номер: {{_counter}}', {'p0': _prefix, '_counter': _counter}),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editTable(BuildContext context) {
    _pickTableFromConfig(context);
  }

  Future<void> _pickTableFromConfig(BuildContext context) async {
    // Try to load tables from quest config
    List<String> tableNames = [];
    try {
      final configPath = QuestPaths.config(widget.questId);
      if (await FileStorage.exists(configPath)) {
        final config = await FileStorage.readJsonFile(configPath);
        final tablesJson = config['tables'] as List<dynamic>? ?? [];
        for (final t in tablesJson) {
          if (t is Map<String, dynamic>) {
            tableNames.add((t['name'] ?? '').toString());
          }
        }
      }
    } catch (_) {
      // Fall through to manual entry
    }

    if (!context.mounted) return;

    // Always show manual entry option
    final result = await showAdaptiveSheet<String>(
      context: context,
      scrollable: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  tr('Выберите таблицу'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (tableNames.isNotEmpty) ...[
                ...tableNames.map(
                  (name) => ListTile(
                    leading: const Icon(Icons.dataset_rounded, size: 20),
                    title: Text(name),
                    dense: true,
                    onTap: () => Navigator.pop(ctx, name),
                  ),
                ),
                const Divider(),
              ],
              if (tableNames.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    tr('Нет таблиц в конфигурации квеста'),
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ListTile(
                leading: Icon(
                  Icons.edit_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  tr('Ввести вручную…'),
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
                dense: true,
                onTap: () {
                  Navigator.pop(ctx, '__manual__');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (result == null || !context.mounted) return;

    if (result == '__manual__') {
      _showInlineEditor(context, 'Имя таблицы', widget.block.tableName, (v) {
        setState(() => widget.block.tableName = v);
      });
    } else {
      setState(() => widget.block.tableName = result);
    }
  }

  /// Имя переменной — через общий экран выбора/создания переменных.
  Future<void> _editPrefix(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => VariableSelectionScreen(
          questId: widget.questId,
          selectedVariable: widget.block.varPrefix,
        ),
      ),
    );
    if (result != null && context.mounted) {
      setState(() => widget.block.varPrefix = result);
    }
  }

  Future<void> _editIndex(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => VariableSelectionScreen(
          questId: widget.questId,
          selectedVariable: widget.block.indexVariable,
        ),
      ),
    );
    if (result != null && context.mounted) {
      setState(() => widget.block.indexVariable = result);
    }
  }

  void _showInlineEditor(
    BuildContext context,
    String title,
    String initial,
    ValueChanged<String> onSaved,
  ) {
    final ctrl = TextEditingController(text: initial);
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                ctx,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                onSaved(ctrl.text);
                Navigator.pop(ctx);
              },
              child: Text(tr('Готово')),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
