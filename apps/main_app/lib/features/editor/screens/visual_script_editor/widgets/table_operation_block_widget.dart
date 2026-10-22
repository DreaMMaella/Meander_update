import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/table_path_picker.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/variable_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  TABLE OPERATION BLOCK — операции над хранилищем (get/set/add/remove/…)
// ============================================================================

class TableOperationBlockWidget extends StatefulWidget {
  final TableOperationBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const TableOperationBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<TableOperationBlockWidget> createState() =>
      _TableOperationBlockWidgetState();
}

class _TableOperationBlockWidgetState extends State<TableOperationBlockWidget> {
  Future<void> _editExpression(String initial, Function(String) onSave) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpressionEditorScreen(
          initialValue: initial,
          questId: widget.questId,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => onSave(result));
    }
  }

  Future<void> _selectVariable(String initial, Function(String) onSave) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => VariableSelectionScreen(
          questId: widget.questId,
          selectedVariable: initial,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => onSave(result));
    }
  }

  Future<void> _selectTableName() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => VariableSelectionScreen(
          questId: widget.questId,
          pickerMode: true,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.block.tableName = result);
    }
  }

  /// Путь — не свободная строка, а адрес внутри `data` таблицы, поэтому
  /// сначала показываем реальные ключи: автор видит, чем заполнить поле,
  /// и не натыкается на пустой промах блока.
  Future<void> _selectPath() async {
    final result = await pickTablePath(
      context,
      questId: widget.questId,
      tableName: widget.block.tableName,
      operation: widget.block.operation,
      initial: widget.block.path,
    );
    if (result != null && mounted) {
      setState(() => widget.block.path = result);
    }
  }

  IconData _opIcon(TableOperation op) {
    switch (op) {
      case TableOperation.get:
        return Icons.south_west_rounded;
      case TableOperation.set:
        return Icons.save_rounded;
      case TableOperation.add:
        return Icons.add_rounded;
      case TableOperation.remove:
        return Icons.remove_rounded;
      case TableOperation.removeValue:
        return Icons.highlight_remove_rounded;
      case TableOperation.clear:
        return Icons.delete_sweep_rounded;
      case TableOperation.contains:
        return Icons.search_rounded;
    }
  }

  Future<void> _selectOperation() async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showAdaptiveSheet<TableOperation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('Операция'),
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            // Семь операций по три строки не влезают в шит телефона: без
            // Flexible и списка здесь был перепол layout.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final op in TableOperation.values)
                    _operationTile(ctx, scheme, op),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null && result != widget.block.operation) {
      setState(() => widget.block.operation = result);
    }
  }

  Widget _operationTile(
    BuildContext ctx,
    ColorScheme scheme,
    TableOperation op,
  ) {
    final selected = op == widget.block.operation;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          _opIcon(op),
          color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        op.label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      // Разница между «Удалить» и «Удалить значение» без этой строки
      // неочевидна — и автор тыкает в неправильную.
      subtitle: Text(
        op.description,
        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: true,
      trailing: selected ? Icon(Icons.check_rounded, color: scheme.secondary) : null,
      onTap: () => Navigator.pop(ctx, op),
    );
  }

  @override
  Widget build(BuildContext context) {
    final op = widget.block.operation;

    return ScriptBlockShell(
      category: BlockCategory.variable,
      title: op.label,
      icon: _opIcon(op),
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ScriptFieldsGrid(
            children: [
              ScriptFieldTile(
                label: tr('Операция'),
                value: op.label,
                icon: Icons.tune_rounded,
                onTap: _selectOperation,
              ),
              ScriptFieldTile(
                label: tr('Хранилище'),
                value: widget.block.tableName,
                placeholder: 'storage',
                icon: Icons.table_chart_rounded,
                hint: tr('таблица из «Переменные и данные»'),
                onTap: _selectTableName,
              ),
              ScriptFieldTile(
                label: tr('Путь'),
                value: widget.block.path,
                placeholder: op.pathIsOptional
                    ? tr('всё хранилище')
                    : tr('не указан'),
                icon: Icons.account_tree_rounded,
                hint: op.hintFor('path'),
                onTap: _selectPath,
              ),
              if (op.needsValue)
                ScriptFieldTile(
                  label: tr('Значение'),
                  value: widget.block.value,
                  placeholder: '…',
                  icon: Icons.data_object_rounded,
                  hint: op.hintFor('value'),
                  onTap: () => _editExpression(
                    widget.block.value,
                    (v) => widget.block.value = v,
                  ),
                ),
              if (op.needsTarget)
                ScriptFieldTile(
                  label: tr('В переменную'),
                  value: widget.block.targetVariable,
                  placeholder: 'result',
                  icon: Icons.save_alt_rounded,
                  hint: op.hintFor('target'),
                  onTap: () => _selectVariable(
                    widget.block.targetVariable,
                    (v) => widget.block.targetVariable = v,
                  ),
                ),
            ],
          ),
          // Одна строка «что получится» дороже подсказок у каждого поля:
          // спорные случаи («Удалить» по ключу против «Удалить значение»)
          // видно сразу, не открывая список операций.
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
            child: Text(
              op.description,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
