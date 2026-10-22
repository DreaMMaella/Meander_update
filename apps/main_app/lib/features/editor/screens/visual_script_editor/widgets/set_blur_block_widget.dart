import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  SET BLUR BLOCK — установить размытие фона
// ============================================================================

class SetBlurBlockWidget extends StatefulWidget {
  final SetBlurBlock block;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const SetBlurBlockWidget({
    super.key,
    required this.block,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<SetBlurBlockWidget> createState() => _SetBlurBlockWidgetState();
}

class _SetBlurBlockWidgetState extends State<SetBlurBlockWidget> {
  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('Установить размытие'),
      icon: Icons.blur_on_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldsGroup(
        children: [
          ScriptFieldSegmented<String>(
            label: tr('Цель'),
            icon: Icons.layers_outlined,
            value: widget.block.target,
            options: [
              (value: 'node', label: tr('Нода'), icon: Icons.crop_square_rounded),
              (
                value: 'tag',
                label: tr('Глава'),
                icon: Icons.bookmark_outline_rounded,
              ),
              (value: 'quest', label: tr('Квест'), icon: Icons.public_rounded),
            ],
            onChanged: (v) => setState(() => widget.block.target = v),
          ),
          ScriptFieldSlider(
            label: tr('Размытие'),
            icon: widget.block.blurValue <= 0
                ? Icons.blur_off_rounded
                : Icons.blur_on_rounded,
            value: widget.block.blurValue,
            min: 0,
            max: 30,
            divisions: 30,
            formatter: (v) => v.toStringAsFixed(1),
            onChanged: (v) => setState(() => widget.block.blurValue = v),
          ),
        ],
      ),
    );
  }
}
