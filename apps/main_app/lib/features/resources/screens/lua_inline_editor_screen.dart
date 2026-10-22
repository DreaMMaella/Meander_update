import 'package:flutter/material.dart';
import 'package:canvas_app/features/resources/widgets/lua_code_field.dart';
import 'package:canvas_app/features/resources/widgets/lua_editor_scaffold.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/resources/screens/lua_docs_screen.dart';

// ============================================================================
//  РЕДАКТОР INLINE-LUA — Material 3
// ============================================================================

class LuaInlineEditorScreen extends StatefulWidget {
  final String initialText;

  const LuaInlineEditorScreen({super.key, this.initialText = ''});

  @override
  State<LuaInlineEditorScreen> createState() => _LuaInlineEditorScreenState();
}

class _LuaInlineEditorScreenState extends State<LuaInlineEditorScreen> {
  String _code = '';

  @override
  void initState() {
    super.initState();
    _code = widget.initialText;
  }

  void _openDocs() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LuaDocsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _code);
        }
      },
      child: LuaEditorScaffold(
        title: tr('Код Lua (inline)'),
        subtitle: tr('Код сохранится прямо в блоке call_lua — отдельный файл не создаётся.'),
        onHelp: _openDocs,
        onCancel: () => Navigator.pop(context, widget.initialText),
        trailingButton: FilledButton.tonalIcon(
          onPressed: () => Navigator.pop(context, _code),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(tr('Готово')),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        content: LuaCodeField(
          initialCode: widget.initialText,
          onChange: (code) => _code = code,
        ),
      ),
    );
  }
}
