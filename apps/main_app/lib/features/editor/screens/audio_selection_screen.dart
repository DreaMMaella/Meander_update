import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/quest_store.dart';
import 'package:flutter/material.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

// План 020-C4.5: операции над квестом — через ядро (QuestStore).
Future<QuestStore> _qs() => QuestStore.defaultInstance();
Future<Map<String, dynamic>> _readMap(String rel) async =>
    await (await _qs()).readJson(rel) ?? <String, dynamic>{};

class AudioResource {
  final String id;
  final String name;
  final String path;

  AudioResource({required this.id, required this.name, required this.path});
}

class AudioSelectionScreen extends StatefulWidget {
  final String questId;
  final String? selectedAudioId;

  const AudioSelectionScreen({
    super.key,
    required this.questId,
    this.selectedAudioId,
  });

  @override
  State<AudioSelectionScreen> createState() => _AudioSelectionScreenState();
}

class _AudioSelectionScreenState extends State<AudioSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<AudioResource> _audioFiles = [];
  bool _isLoading = true;
  final AudioPlayer _previewPlayer = AudioPlayer();
  StreamSubscription? _completeSub;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _loadAudioFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _completeSub?.cancel();
    _previewPlayer.stop();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadAudioFiles() async {
    setState(() => _isLoading = true);
    try {
      final audioDir = QuestPaths.resAudioDir(widget.questId);
      final files = await FileStorage.listFiles(audioDir);

      Map<String, dynamic> metadata = {};
      final metadataPath = QuestPaths.metadata(widget.questId);
      if (await (await _qs()).exists(metadataPath)) {
        metadata = await _readMap(metadataPath);
      }

      final resources = <AudioResource>[];
      for (final fileName in files) {
        final ext = fileName.split('.').last.toLowerCase();
        if (!['mp3', 'wav', 'ogg', 'm4a', 'flac', 'aac'].contains(ext))
          continue;

        String friendlyName = fileName;
        if (metadata.containsKey(fileName)) {
          final val = metadata[fileName];
          if (val is String) {
            friendlyName = val;
          } else if (val is Map) {
            friendlyName = val['name'] as String? ?? fileName;
          }
        }

        resources.add(
          AudioResource(
            id: fileName,
            name: friendlyName,
            path: QuestPaths.resAudio(widget.questId, fileName),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _audioFiles = resources;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _previewAudio(AudioResource audio) async {
    try {
      if (_playingId == audio.id) {
        await _previewPlayer.stop();
        if (!mounted) return;
        setState(() => _playingId = null);
        return;
      }

      await _previewPlayer.stop();
      final fullPath = await FileStorage.getFilePath(audio.path);
      if (!await File(fullPath).exists()) return;
      if (!mounted) return;
      setState(() => _playingId = audio.id);
      await _previewPlayer.play(DeviceFileSource(fullPath));
      // Подписка одна: на каждом тапе слушатель не должен копиться.
      _completeSub?.cancel();
      _completeSub = _previewPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playingId = null);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(trf('Ошибка воспроизведения: {p0}', {'p0': friendlyError(e)})),
          ),
        );
      }
    }
  }

  List<AudioResource> get _filteredFiles {
    if (_searchQuery.isEmpty) return _audioFiles;
    return _audioFiles.where((a) {
      return a.name.toLowerCase().contains(_searchQuery) ||
          a.id.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(tr('Выбор аудио'), style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AdaptiveContent(
        maxWidth: 800,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('Поиск аудио...'),
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value.toLowerCase());
                },
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    )
                  : _filteredFiles.isEmpty
                  ? Center(
                      child: Text(
                        tr('Аудио файлы не найдены'),
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      itemCount: _filteredFiles.length,
                      itemBuilder: (context, index) {
                        final audio = _filteredFiles[index];
                        final isSelected = widget.selectedAudioId == audio.id;
                        final isPlaying = _playingId == audio.id;

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.teal.withOpacity(0.2)
                                : const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.tealAccent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          // Material поверх цветного фона: ListTile рисует
                          // фон/ink на ближайшем Material-предке.
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              leading: Icon(
                                isPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                                color: isPlaying
                                    ? Colors.tealAccent
                                    : Colors.white70,
                              ),
                              title: Text(
                                audio.name,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.tealAccent
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                audio.id,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.teal,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, audio.id),
                              onLongPress: () => _previewAudio(audio),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
