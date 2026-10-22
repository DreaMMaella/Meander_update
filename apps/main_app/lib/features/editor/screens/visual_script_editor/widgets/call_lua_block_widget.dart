import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/features/editor/workspace/editor_document_launcher.dart';
import 'package:canvas_app/features/resources/screens/lua_inline_editor_screen.dart';
import 'package:canvas_app/features/resources/screens/resource_selection_screen.dart';
import 'package:canvas_app/features/resources/services/resource_service.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  CALL LUA BLOCK — вызов Lua-функции (L3A)
// ============================================================================
//
//  Один блок с переключателем источника: «Из файла» (.lua в scripts/) или
//  «Inline» (код открывается в отдельном полноэкранном редакторе и хранится
//  в блоке). Оба режима имеют поле function — имя вызываемой Lua-функции.
//
// ============================================================================

class CallLuaBlockWidget extends StatefulWidget {
  final CallLuaBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const CallLuaBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<CallLuaBlockWidget> createState() => _CallLuaBlockWidgetState();
}

class _CallLuaBlockWidgetState extends State<CallLuaBlockWidget> {
  bool get _isFileMode => widget.block.scriptId != null;

  Future<void> _selectLuaFile() async {
    final result = await Navigator.push<SelectableResource>(
      context,
      MaterialPageRoute(
        builder: (_) => ResourceSelectionScreen(
          questId: widget.questId,
          allowedTypes: const ['lua'],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      // Сохраняем имя с расширением .lua, которое резолвится движком
      // (нормализация снимает расширение и путь).
      widget.block.scriptId = result.name;
      widget.block.scriptName = result.friendlyName;
    });
  }

  Future<void> _createNewLua() async {
    // Мгновенное создание (План 014, A2): авто-имя, без диалога, метадата —
    // через ResourceService; сразу редактор.
    final resources = ResourceService.forQuest(widget.questId);
    final created = await resources.createLuaScript();

    if (!mounted) return;
    setState(() {
      widget.block.scriptId = created.fileName;
      widget.block.scriptName = created.name;
    });
    await _editSelectedLua();
  }

  Future<void> _editSelectedLua() async {
    final scriptId = widget.block.scriptId;
    if (scriptId == null || scriptId.isEmpty || !mounted) return;
    final resource = await ResourceService.forQuest(widget.questId)
        .findResourceByFileName(scriptId);
    if (!mounted) return;
    await EditorDocumentLauncher.openLua(
      context,
      widget.questId,
      scriptId,
      title: widget.block.scriptName,
      stableId: resource?.stableId,
    );
  }

  Future<void> _showSourceSheet() async {
    final scheme = Theme.of(context).colorScheme;
    final choice = await showAdaptiveSheet<String>(
      context: context,
      scrollable: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                tr('Новый .lua'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(tr('Создать с нуля')),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.code_rounded, color: scheme.onSurfaceVariant),
              ),
              title: Text(
                tr('Существующий .lua'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(tr('Выбрать из списка')),
              onTap: () => Navigator.pop(ctx, 'existing'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'existing') {
      await _selectLuaFile();
    } else {
      await _createNewLua();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScriptBlockShell(
      category: BlockCategory.script,
      title: tr('Вызвать Lua'),
      icon: Icons.data_object_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ScriptFieldSegmented<bool>(
            label: tr('Источник кода'),
            value: _isFileMode,
            options: [
              (value: true, label: tr('Из файла'), icon: Icons.description_rounded),
              (value: false, label: 'Inline', icon: Icons.edit_rounded),
            ],
            onChanged: (isFile) {
              setState(() {
                if (isFile) {
                  widget.block.scriptId = '';
                  widget.block.scriptName = 'Выберите .lua';
                } else {
                  widget.block.scriptId = null;
                }
              });
            },
          ),
          const SizedBox(height: 3),
          if (_isFileMode)
            ScriptFieldTile(
              label: tr('Файл .lua'),
              value: widget.block.scriptName,
              placeholder: tr('не выбран'),
              icon: Icons.description_rounded,
              onTap: _showSourceSheet,
              trailing: (widget.block.scriptId?.isNotEmpty ?? false)
                  ? IconButton(
                      tooltip: tr('Открыть редактор .lua'),
                      onPressed: _editSelectedLua,
                      icon: Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
            )
          else
            ScriptFieldTile(
              label: tr('Код (inline)'),
              value: _inlinePreview,
              placeholder: tr('нажмите, чтобы ввести код'),
              icon: Icons.edit_rounded,
              onTap: _editInlineLua,
            ),
          const SizedBox(height: 3),
          ScriptFieldTile(
            label: tr('Функция'),
            value: widget.block.function,
            placeholder: 'start',
            icon: Icons.functions_rounded,
            onTap: () async {
              final result = await _showTextFieldDialog(
                title: tr('Имя Lua-функции'),
                initial: widget.block.function,
              );
              if (result != null && result.isNotEmpty && mounted) {
                setState(() => widget.block.function = result.trim());
              }
            },
          ),
        ],
      ),
    );
  }

  /// Превью inline-кода для поля блока: первая непустая строка (обрезанная).
  String get _inlinePreview {
    for (final line in widget.block.script.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.length > 40 ? '${trimmed.substring(0, 40)}…' : trimmed;
      }
    }
    return '';
  }

  Future<void> _editInlineLua() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => LuaInlineEditorScreen(initialText: widget.block.script),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.block.script = result);
    }
  }

  Future<String?> _showTextFieldDialog({
    required String title,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(tr('ОК')),
          ),
        ],
      ),
    );
  }
}
