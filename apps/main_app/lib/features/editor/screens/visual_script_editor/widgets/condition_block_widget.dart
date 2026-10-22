import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/reorderable_block_list.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
//  CONDITION BLOCK — Material 3 (тема, ListTile-стиль)
// ============================================================================

typedef OnBlockDrop =
    void Function(
      VisualScriptBlock droppedBlock,
      List<VisualScriptBlock> targetList,
    );

class ConditionBlockWidget extends ConsumerStatefulWidget {
  final ConditionBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;
  final OnBlockDrop onBlockDrop;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const ConditionBlockWidget({
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
  ConsumerState<ConditionBlockWidget> createState() =>
      _ConditionBlockWidgetState();
}

class _ConditionBlockWidgetState extends ConsumerState<ConditionBlockWidget> {
  Future<void> _openExpressionEditor() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ExpressionEditorScreen(
          initialValue: widget.block.expression,
          questId: widget.questId,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.block.expression = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.control,
      title: tr('Если / Иначе'),
      icon: Icons.call_split_rounded,
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
      // Chip с выражением прямо в шапке
      headerSuffix: ShellValueChip(
        value: widget.block.expression,
        placeholder: tr('условие…'),
        onTap: _openExpressionEditor,
      ),
      // Ветки — плоскими карточками под блоком, с подписями в цвет контейнера:
      // раньше они тонули внутри цветного корпуса и блок был толстым.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ScriptBranchCaption(
            label: tr('Если истина'),
            icon: Icons.check_rounded,
          ),
          ReorderableBlockList(
            blocks: widget.block.thenBlocks,
            questId: widget.questId,
            onBlockDrop: widget.onBlockDrop,
            allowEventBlocks: false,
            emptyPlaceholder: tr('Перетащите действия'),
            onDragUpdate: widget.onDragUpdate,
            onDragStart: widget.onDragStart,
            onDragEnd: widget.onDragEnd,
          ),
          ScriptBranchCaption(label: tr('Иначе'), icon: Icons.east_rounded),
          ReorderableBlockList(
            blocks: widget.block.elseBlocks,
            questId: widget.questId,
            onBlockDrop: widget.onBlockDrop,
            allowEventBlocks: false,
            emptyPlaceholder: tr('Перетащите действия'),
            onDragUpdate: widget.onDragUpdate,
            onDragStart: widget.onDragStart,
            onDragEnd: widget.onDragEnd,
          ),
        ],
      ),
      endLabel: tr('Конец условия'),
    );
  }
}
