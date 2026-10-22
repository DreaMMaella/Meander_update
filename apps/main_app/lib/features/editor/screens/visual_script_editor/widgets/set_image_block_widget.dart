import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/content_item_picker_model.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/content_item_selection_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/resources/services/resource_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
//  SET IMAGE BLOCK — сменить картинку у айтема
// ============================================================================

/// Движок пишет переопределение в служебную переменную, клиент подхватывает
/// его при разрешении пути картинки — модель квеста при этом не меняется.
class SetImageBlockWidget extends ConsumerStatefulWidget {
  final SetImageBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const SetImageBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  ConsumerState<SetImageBlockWidget> createState() =>
      _SetImageBlockWidgetState();
}

class _SetImageBlockWidgetState extends ConsumerState<SetImageBlockWidget> {
  Future<void> _selectItem() async {
    final result = await Navigator.push<ContentItemChoice>(
      context,
      MaterialPageRoute(
        builder: (context) => ContentItemSelectionScreen(
          questId: widget.questId,
          allowedTypes: const ['image'],
          selectedItemId: widget.block.itemId,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        widget.block.itemId = result.item.id;
        widget.block.itemName = _labelOf(result);
      });
    }
  }

  /// Подпись в блоке: имя из библиотеки и где лежит айтем. `itemId` — ссылка,
  /// по которой блок работает; имя нужно автору, чтобы через неделю понять,
  /// какую из сорока картинок он имел в виду.
  static String _labelOf(ContentItemChoice choice) {
    final location = choice.location;
    if (location.isEmpty || location == choice.label) return choice.label;
    return '${choice.label} · $location';
  }

  Future<void> _editSource() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ExpressionEditorScreen(
          initialValue: widget.block.source,
          questId: widget.questId,
          title: tr('Источник картинки'),
          isTemplate: true,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.block.source = result);
    }
  }

  /// Подпись источника — имя картинки из библиотеки, а не
  /// `1790024448511_<uuid>.png`: по такому хвосту автор не помнит, какой из
  /// двух кадров он подставил. Формула (`{pic}`) показывается как написана, а
  /// сырой путь остаётся в редакторе формул, куда ведёт это поле.
  String _sourceLabel() {
    final source = widget.block.source.trim();
    if (source.isEmpty) return source;
    final names =
        ref.watch(questResourceNamesProvider(widget.questId)).valueOrNull ??
        const <String, String>{};
    final named = names[source.split('/').last]?.trim();
    return (named == null || named.isEmpty) ? source : named;
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('Сменить картинку'),
      icon: Icons.swap_horiz_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldsGrid(
        children: [
          ScriptFieldTile(
            label: tr('объект'),
            icon: Icons.image_rounded,
            value: widget.block.itemId == null ? '' : widget.block.itemName,
            placeholder: tr('выберите картинку'),
            onTap: _selectItem,
          ),
          ScriptFieldTile(
            label: tr('источник'),
            icon: Icons.functions_rounded,
            value: _sourceLabel(),
            placeholder: tr('путь, имя ресурса или {формула}'),
            onTap: _editSource,
          ),
        ],
      ),
    );
  }
}
