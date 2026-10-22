import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/reorderable_block_list.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
//  CROSSFADE BLOCK — Material 3 (тема)
// ============================================================================

typedef OnBlockDrop =
    void Function(
      VisualScriptBlock droppedBlock,
      List<VisualScriptBlock> targetList,
    );

class CrossfadeBlockWidget extends ConsumerStatefulWidget {
  final CrossfadeBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;
  final OnBlockDrop onBlockDrop;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const CrossfadeBlockWidget({
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
  ConsumerState<CrossfadeBlockWidget> createState() =>
      _CrossfadeBlockWidgetState();
}

class _CrossfadeBlockWidgetState extends ConsumerState<CrossfadeBlockWidget> {
  Future<void> _openExpressionEditor() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ExpressionEditorScreen(
          initialValue: widget.block.durationExpression,
          questId: widget.questId,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.block.durationExpression = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('Кроссфейд (затемнение)'),
      icon: Icons.blur_on_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      menuScope: blockScope(widget.block).noun,
      // Действия перехода — плоскими карточками под блоком.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ScriptBranchCaption(
            label: tr('ВО ВРЕМЯ ПЕРЕХОДА'),
            icon: Icons.playlist_play_rounded,
          ),
          ReorderableBlockList(
            blocks: widget.block.children,
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
      endLabel: tr('Конец кроссфейда'),
      child: ScriptFieldTile(
        label: tr('Длительность (мс)'),
        value: widget.block.durationExpression,
        placeholder: tr('напр. 300'),
        icon: Icons.timer_outlined,
        onTap: _openExpressionEditor,
      ),
    );
  }
}
