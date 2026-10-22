import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  SET VOLUME BLOCK — установить громкость
// ============================================================================

class SetVolumeBlockWidget extends StatefulWidget {
  final SetVolumeBlock block;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const SetVolumeBlockWidget({
    super.key,
    required this.block,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<SetVolumeBlockWidget> createState() => _SetVolumeBlockWidgetState();
}

class _SetVolumeBlockWidgetState extends State<SetVolumeBlockWidget> {
  IconData get _volumeIcon {
    if (widget.block.volume <= 0) return Icons.volume_off_rounded;
    if (widget.block.volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('Установить громкость'),
      icon: Icons.tune_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldsGroup(
        children: [
          ScriptFieldSegmented<String>(
            label: tr('Цель'),
            icon: Icons.speaker_rounded,
            value: widget.block.target,
            options: [
              (
                value: 'tagAudio',
                label: tr('Музыка главы'),
                icon: Icons.library_music_rounded,
              ),
              (
                value: 'contentAudio',
                label: tr('Звуки ноды'),
                icon: Icons.graphic_eq_rounded,
              ),
            ],
            onChanged: (v) => setState(() => widget.block.target = v),
          ),
          ScriptFieldSlider(
            label: tr('Громкость'),
            icon: _volumeIcon,
            value: widget.block.volume,
            divisions: 20,
            formatter: (v) => '${(v * 100).toInt()}%',
            onChanged: (v) => setState(() => widget.block.volume = v),
          ),
        ],
      ),
    );
  }
}
