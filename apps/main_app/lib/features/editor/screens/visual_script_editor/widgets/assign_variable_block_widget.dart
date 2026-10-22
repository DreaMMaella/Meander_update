import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/variable_selection_screen.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  ASSIGN VARIABLE BLOCK — компактный M3, единая палитра ScriptBlockShell
// ============================================================================

class AssignVariableBlockWidget extends StatefulWidget {
  final AssignVariableBlock block;
  final String questId;
  final VoidCallback? onDelete;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;

  const AssignVariableBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onDelete,
    this.onMenuAction,
  });

  @override
  State<AssignVariableBlockWidget> createState() =>
      _AssignVariableBlockWidgetState();
}

class _AssignVariableBlockWidgetState extends State<AssignVariableBlockWidget> {
  Future<void> _selectVariable() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => VariableSelectionScreen(
          questId: widget.questId,
          selectedVariable: widget.block.variableName,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.block.variableName = result);
    }
  }

  Future<void> _editValue() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ExpressionEditorScreen(
          initialValue: widget.block.value,
          questId: widget.questId,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.block.value = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.variable,
      title: tr('Присвоить'),
      icon: Icons.edit_note_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            flex: 5,
            child: ScriptFieldTile(
              label: tr('переменная'),
              icon: Icons.tag_rounded,
              value: widget.block.variableName,
              placeholder: tr('имя'),
              onTap: _selectVariable,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.west_rounded, size: 14),
          ),
          Flexible(
            flex: 7,
            child: ScriptFieldTile(
              label: tr('значение'),
              icon: Icons.functions_rounded,
              value: widget.block.value,
              placeholder: '…',
              onTap: _editValue,
            ),
          ),
        ],
      ),
    );
  }
}
