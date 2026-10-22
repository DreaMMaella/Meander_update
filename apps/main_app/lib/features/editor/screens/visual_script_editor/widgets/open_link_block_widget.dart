import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  OPEN LINK BLOCK — «Открыть ссылку в браузере»
// ============================================================================

class OpenLinkBlockWidget extends StatefulWidget {
  final OpenLinkBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const OpenLinkBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<OpenLinkBlockWidget> createState() => _OpenLinkBlockWidgetState();
}

class _OpenLinkBlockWidgetState extends State<OpenLinkBlockWidget> {
  Future<void> _editUrl() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpressionEditorScreen(
          initialValue: widget.block.url,
          questId: widget.questId,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.block.url = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('Открыть ссылку'),
      icon: Icons.open_in_new_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldTile(
        label: 'URL',
        value: widget.block.url,
        placeholder: 'https://…',
        icon: Icons.link_rounded,
        onTap: _editUrl,
      ),
    );
  }
}
