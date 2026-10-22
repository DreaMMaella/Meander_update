import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  PAUSE / RESUME BLOCK — пауза или возобновление аудио
// ============================================================================

class PauseResumeBlockWidget extends StatefulWidget {
  final PauseResumeBlock block;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const PauseResumeBlockWidget({
    super.key,
    required this.block,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<PauseResumeBlockWidget> createState() => _PauseResumeBlockWidgetState();
}

class _PauseResumeBlockWidgetState extends State<PauseResumeBlockWidget> {
  IconData get _actionIcon {
    switch (widget.block.action) {
      case 'pause':
        return Icons.pause_rounded;
      case 'resume':
        return Icons.play_arrow_rounded;
      default:
        return Icons.swap_horiz_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('Пауза / Возобновление'),
      icon: _actionIcon,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldsGroup(
        children: [
          ScriptFieldSegmented<String>(
            label: tr('Действие'),
            icon: Icons.bolt_rounded,
            value: widget.block.action,
            options: [
              (
                value: 'toggle',
                label: tr('Переключить'),
                icon: Icons.swap_horiz_rounded,
              ),
              (value: 'pause', label: tr('Пауза'), icon: Icons.pause_rounded),
              (
                value: 'resume',
                label: tr('Играть'),
                icon: Icons.play_arrow_rounded,
              ),
            ],
            onChanged: (v) => setState(() => widget.block.action = v),
          ),
          ScriptFieldSegmented<String>(
            label: tr('Цель'),
            icon: Icons.speaker_rounded,
            value: widget.block.target,
            options: [
              (value: 'all', label: tr('Всё'), icon: Icons.all_inclusive_rounded),
              (
                value: 'music',
                label: tr('Музыка'),
                icon: Icons.library_music_rounded,
              ),
              (value: 'sound', label: tr('Звуки'), icon: Icons.graphic_eq_rounded),
            ],
            onChanged: (v) => setState(() => widget.block.target = v),
          ),
        ],
      ),
    );
  }
}
