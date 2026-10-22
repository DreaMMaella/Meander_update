import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  COMMENT BLOCK — заметка автора, не исполняется
// ============================================================================

class CommentBlockWidget extends StatefulWidget {
  final CommentBlock block;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const CommentBlockWidget({
    super.key,
    required this.block,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<CommentBlockWidget> createState() => _CommentBlockWidgetState();
}

class _CommentBlockWidgetState extends State<CommentBlockWidget> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.block.text);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.comment,
      title: tr('Комментарий'),
      icon: Icons.chat_bubble_outline_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TextField(
          controller: _ctrl,
          maxLines: null,
          minLines: 1,
          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            hintText: tr('Заметка автора…'),
          ),
          onChanged: (v) => widget.block.text = v,
        ),
      ),
    );
  }
}