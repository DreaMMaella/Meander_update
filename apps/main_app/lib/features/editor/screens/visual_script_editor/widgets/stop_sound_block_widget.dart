import 'package:mnd_player/utils/file_storage.dart';
import 'package:canvas_app/features/editor/screens/audio_selection_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';
import 'package:mnd_core/utils/quest_paths.dart';

// ============================================================================
//  STOP SOUND BLOCK — остановить звук(и)
// ============================================================================

class StopSoundBlockWidget extends StatefulWidget {
  final StopSoundBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const StopSoundBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<StopSoundBlockWidget> createState() => _StopSoundBlockWidgetState();
}

class _StopSoundBlockWidgetState extends State<StopSoundBlockWidget> {
  Future<void> _selectAudio() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AudioSelectionScreen(
          questId: widget.questId,
          selectedAudioId: widget.block.audioId,
        ),
      ),
    );
    if (result != null && mounted) {
      await _updateAudioInfo(result);
    }
  }

  Future<void> _enterAudioIdManually() async {
    final newId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpressionEditorScreen(
          initialValue: widget.block.audioId ?? '',
          questId: widget.questId,
        ),
      ),
    );
    if (newId != null && newId.isNotEmpty && mounted) {
      await _updateAudioInfo(newId);
    }
  }

  Future<void> _updateAudioInfo(String audioId) async {
    String name =
        'ID: ${audioId.length > 8 ? audioId.substring(0, 8) : audioId}…';
    try {
      final metadataPath = QuestPaths.metadata(widget.questId);
      if (await FileStorage.exists(metadataPath)) {
        final metadata = await FileStorage.readJsonFile(metadataPath);
        if (metadata.containsKey(audioId)) {
          final val = metadata[audioId];
          if (val is String) {
            name = val;
          } else if (val is Map) {
            name = val['name'] as String? ?? name;
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      widget.block.audioId = audioId;
      widget.block.audioName = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSpecific = widget.block.target == 'specific';
    final hasAudio = widget.block.audioId != null;
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('Остановить звук'),
      icon: Icons.stop_circle_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldsGroup(
        children: [
          ScriptFieldSegmented<String>(
            label: tr('Что остановить'),
            icon: Icons.filter_alt_rounded,
            value: widget.block.target,
            options: [
              (
                value: 'all',
                label: tr('Все звуки'),
                icon: Icons.all_inclusive_rounded,
              ),
              (
                value: 'specific',
                label: tr('Конкретный'),
                icon: Icons.audiotrack_rounded,
              ),
            ],
            onChanged: (v) => setState(() {
              widget.block.target = v;
              if (v == 'all') {
                widget.block.audioId = null;
                widget.block.audioName = 'Все звуки';
              }
            }),
          ),
          if (isSpecific)
            ScriptFieldTile(
              label: tr('Аудио'),
              value: widget.block.audioName,
              placeholder: tr('не выбрано'),
              icon: Icons.audiotrack_rounded,
              onTap: _selectAudio,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr('Ввести ID вручную'),
                    onPressed: _enterAudioIdManually,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    child: Icon(
                      hasAudio
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 16,
                      color: hasAudio
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
