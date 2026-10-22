import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  DELAY BLOCK — «Ждать N мс»
// ============================================================================
//  Категория action, sub-tone harmony (зелёный). Одно поле — выражение
//  времени ожидания.

class DelayBlockWidget extends StatefulWidget {
  final DelayBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const DelayBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<DelayBlockWidget> createState() => _DelayBlockWidgetState();
}

class _DelayBlockWidgetState extends State<DelayBlockWidget> {
  Future<void> _editExpression() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpressionEditorScreen(
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
      category: BlockCategory.action,
      title: tr('Ждать'),
      icon: Icons.hourglass_top_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldTile(
        label: tr('Длительность (мс)'),
        value: widget.block.expression,
        placeholder: '1000',
        icon: Icons.timer_outlined,
        onTap: _editExpression,
      ),
    );
  }
}
