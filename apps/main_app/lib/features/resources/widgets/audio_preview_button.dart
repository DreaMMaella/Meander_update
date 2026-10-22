import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;

import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_core/utils/quest_paths.dart';

/// Кнопка предпросмотра аудио-ресурса. Сама управляет проигрыванием
/// (just_audio на мобильных, audioplayers на desktop).
class AudioPreviewButton extends StatefulWidget {
  final String questId;
  final String resourcePath;
  final bool small;

  const AudioPreviewButton({
    super.key,
    required this.questId,
    required this.resourcePath,
    this.small = false,
  });

  @override
  State<AudioPreviewButton> createState() => _AudioPreviewButtonState();
}

class _AudioPreviewButtonState extends State<AudioPreviewButton> {
  ja.AudioPlayer? _jaPlayer;
  AudioPlayer? _apPlayer;
  StreamSubscription<ja.PlayerState>? _jaStateSub;
  bool _isPlaying = false;

  bool get _useJustAudio => !(Platform.isWindows || Platform.isLinux);

  void _log(String message) {
    debugPrint('[QuestAudio][preview][${widget.resourcePath}] $message');
  }

  Future<String> _resolveAudioPath() async {
    final raw = widget.resourcePath;
    if (p.isAbsolute(raw)) return raw;

    final appDir = await FileStorage.getAppDirectory();
    final appPath = p.normalize(appDir.path);
    final normalizedRaw = p.normalize(raw);
    final questPrefix = p.normalize(
      p.join(QuestPaths.questsDir, widget.questId),
    );

    var relative = normalizedRaw;
    if (normalizedRaw.startsWith(questPrefix) &&
        appPath.endsWith(questPrefix)) {
      relative = p.relative(normalizedRaw, from: questPrefix);
    }

    return p.join(appPath, relative);
  }

  @override
  void initState() {
    super.initState();
    if (_useJustAudio) {
      _jaPlayer = ja.AudioPlayer();
      _jaStateSub = _jaPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ja.ProcessingState.completed) {
          _jaPlayer!.seek(Duration.zero);
          if (mounted) setState(() => _isPlaying = false);
        }
      });
    } else {
      _apPlayer = AudioPlayer();
      _apPlayer!.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
    }
  }

  @override
  void dispose() {
    _jaStateSub?.cancel();
    _jaPlayer?.stop();
    _jaPlayer?.dispose();
    _apPlayer?.stop();
    _apPlayer?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      if (mounted) setState(() => _isPlaying = false);
      if (_useJustAudio) {
        await _jaPlayer?.stop();
      } else {
        await _apPlayer?.stop();
      }
      _log('stop');
    } else {
      if (mounted) setState(() => _isPlaying = true);
      try {
        final path = await _resolveAudioPath();
        if (!await File(path).exists()) {
          _log('missing file: $path');
          if (mounted) setState(() => _isPlaying = false);
          return;
        }
        _log('play start path=$path');
        if (_useJustAudio) {
          await _jaPlayer?.setFilePath(path);
          await _jaPlayer?.play();
        } else {
          await _apPlayer?.play(DeviceFileSource(path));
        }
      } catch (e) {
        _log('play error: $e');
        if (mounted) setState(() => _isPlaying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (widget.small) {
      return IconButton(
        icon: Icon(
          _isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_rounded,
          color: scheme.primary,
        ),
        onPressed: _togglePlay,
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(4),
      );
    }

    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _togglePlay,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
            color: scheme.onPrimary,
            size: 20,
          ),
        ),
      ),
    );
  }
}
