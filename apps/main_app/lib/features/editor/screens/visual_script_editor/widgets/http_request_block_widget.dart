import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/variable_selection_screen.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  HTTP REQUEST BLOCK — «HTTP-запрос» (GET/POST/PUT/DELETE/PATCH/HEAD)
// ============================================================================

class HttpRequestBlockWidget extends StatefulWidget {
  final HttpRequestBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const HttpRequestBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<HttpRequestBlockWidget> createState() => _HttpRequestBlockWidgetState();
}

class _HttpRequestBlockWidgetState extends State<HttpRequestBlockWidget> {
  static const _methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD'];

  Future<void> _editText(String initial, ValueChanged<String> onSave) async {
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

  Future<void> _selectVariable(
    String current,
    ValueChanged<String> onSave,
  ) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => VariableSelectionScreen(
          questId: widget.questId,
          selectedVariable: current,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => onSave(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('HTTP-запрос'),
      icon: Icons.http_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldsGroup(
        children: [
          ScriptFieldSegmented<String>(
            label: tr('метод'),
            value: b.method,
            options: [
              for (final m in _methods) (value: m, label: m, icon: null),
            ],
            onChanged: (v) => setState(() => b.method = v),
          ),
          ScriptFieldTile(
            label: 'URL',
            value: b.url,
            placeholder: 'https://…',
            icon: Icons.link_rounded,
            onTap: () => _editText(b.url, (v) => b.url = v),
          ),
          ScriptFieldsGrid(
            children: [
              ScriptFieldTile(
                label: tr('сохранить ответ в'),
                value: b.targetVariable,
                placeholder: tr('переменная'),
                icon: Icons.tag_rounded,
                onTap: () =>
                    _selectVariable(b.targetVariable, (v) => b.targetVariable = v),
              ),
              ScriptFieldTile(
                label: tr('код статуса в'),
                value: b.statusVariable,
                placeholder: tr('переменная'),
                icon: Icons.tag_rounded,
                onTap: () =>
                    _selectVariable(b.statusVariable, (v) => b.statusVariable = v),
              ),
            ],
          ),
          ScriptFieldTile(
            label: tr('тело (для POST/PUT…)'),
            value: b.body,
            placeholder: '…',
            icon: Icons.article_outlined,
            onTap: () => _editText(b.body, (v) => b.body = v),
          ),
          ScriptFieldTile(
            label: tr('заголовки (JSON)'),
            value: b.headers,
            placeholder: '{"Content-Type":"application/json"}',
            icon: Icons.tune_rounded,
            onTap: () => _editText(b.headers, (v) => b.headers = v),
          ),
        ],
      ),
    );
  }
}
