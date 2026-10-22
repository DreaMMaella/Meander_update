import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/features/editor/workspace/editor_document_launcher.dart';
import 'package:canvas_app/features/editor/services/trigger_service.dart';
import 'package:canvas_app/features/resources/screens/resource_selection_screen.dart';
import 'package:canvas_app/features/resources/services/resource_service.dart';
import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  CALL SCRIPT BLOCK — вызов внешнего скрипта
// ============================================================================

class CallScriptBlockWidget extends StatefulWidget {
  final CallScriptBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const CallScriptBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<CallScriptBlockWidget> createState() => _CallScriptBlockWidgetState();
}

class _CallScriptBlockWidgetState extends State<CallScriptBlockWidget> {
  Future<void> _selectOrCreateScript() async {
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
                tr('Новый скрипт'),
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
                tr('Существующий скрипт'),
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

    if (!mounted) return;

    if (choice == 'existing') {
      final result = await Navigator.push<SelectableResource>(
        context,
        MaterialPageRoute(
          builder: (_) => ResourceSelectionScreen(
            questId: widget.questId,
            allowedTypes: const ['script'],
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          widget.block.scriptId = result.name.replaceAll('.json', '');
          widget.block.scriptName = result.friendlyName;
        });
      }
    } else if (choice == 'new') {
      // Мгновенное создание (План 014, A2): авто-имя, шаблон функции,
      // без FolderPicker — сразу редактор.
      final resources = ResourceService.forQuest(widget.questId);
      final scripts = ScriptService(resources: resources);
      final created = await resources.createScript(
        initialBlocks: TriggerService.jsonFunctionBlocks(),
      );

      if (!mounted) return;
      setState(() {
        widget.block.scriptId = created.id;
        widget.block.scriptName = created.name;
      });

      await scripts.openEditor(context, created.questRelativePath);
    }
  }

  Future<void> _editSelectedScript() async {
    final scriptId = widget.block.scriptId;
    if (scriptId == null || scriptId.isEmpty) return;
    await EditorDocumentLauncher.openVisualScript(
      context,
      widget.questId,
      scriptId,
      title: widget.block.scriptName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasScript = widget.block.scriptId != null;
    return ScriptBlockShell(
      category: BlockCategory.script,
      title: tr('Запустить скрипт'),
      icon: Icons.code_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldTile(
        label: tr('Скрипт'),
        value: widget.block.scriptName,
        placeholder: tr('не выбран'),
        icon: Icons.terminal_rounded,
        onTap: _selectOrCreateScript,
        trailing: hasScript
            ? IconButton(
                tooltip: tr('Открыть редактор скрипта'),
                onPressed: _editSelectedScript,
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
