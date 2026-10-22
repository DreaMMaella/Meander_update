import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/function_selection_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/features/editor/workspace/editor_document_launcher.dart';
import 'package:canvas_app/features/editor/services/trigger_service.dart';
import 'package:canvas_app/features/resources/services/resource_service.dart';
import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  CALL FUNCTION BLOCK — вызов функции скрипта
// ============================================================================

class CallFunctionBlockWidget extends StatefulWidget {
  final CallFunctionBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const CallFunctionBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<CallFunctionBlockWidget> createState() =>
      _CallFunctionBlockWidgetState();
}

class _CallFunctionBlockWidgetState extends State<CallFunctionBlockWidget> {
  Future<void> _selectOrCreateFunction() async {
    final scheme = Theme.of(context).colorScheme;
    final choice = await showAdaptiveSheet<String>(
      context: context,
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
                tr('Новая функция'),
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
                child: Icon(
                  Icons.functions_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              title: Text(
                tr('Существующая функция'),
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
      final result = await Navigator.push<SelectableFunction>(
        context,
        MaterialPageRoute(
          builder: (_) => FunctionSelectionScreen(questId: widget.questId),
        ),
      );
      if (result == null || !mounted) return;
      setState(() {
        widget.block.functionId = result.scriptId;
        widget.block.functionEntry = result.functionEntry;
        widget.block.functionName = result.displayName;
      });
      return;
    }

    // Мгновенное создание (План 014, A2): авто-имя, без FolderPicker,
    // шаблон функции, сразу редактор.
    final resources = ResourceService.forQuest(widget.questId);
    final scripts = ScriptService(resources: resources);
    final created = await resources.createScript(
      initialBlocks: TriggerService.jsonFunctionBlocks(),
    );

    if (!mounted) return;
    setState(() {
      widget.block.functionId = created.id;
      widget.block.functionEntry = 'main';
      widget.block.functionName = '${created.name} :: main';
    });

    await scripts.openEditor(context, created.questRelativePath);
  }

  Future<void> _editSelectedFunction() async {
    final functionId = widget.block.functionId;
    if (functionId == null || functionId.isEmpty) return;
    await EditorDocumentLauncher.openVisualScript(
      context,
      widget.questId,
      functionId,
      title: widget.block.functionName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFunction = widget.block.functionId != null;
    return ScriptBlockShell(
      category: BlockCategory.script,
      title: tr('Вызвать функцию'),
      icon: Icons.functions_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldTile(
        label: tr('Функция'),
        value: widget.block.functionName,
        placeholder: tr('не выбрана'),
        icon: Icons.tag_rounded,
        onTap: _selectOrCreateFunction,
        trailing: hasFunction
            ? IconButton(
                tooltip: tr('Открыть редактор функции'),
                onPressed: _editSelectedFunction,
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                visualDensity: VisualDensity.compact,
              )
            : null,
      ),
    );
  }
}
