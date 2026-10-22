import 'package:canvas_app/features/editor/providers/tag_provider.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

class ChapterFolderPickerScreen extends StatefulWidget {
  final String title;
  final List<String> folders;
  final String initialFolder;

  const ChapterFolderPickerScreen({
    super.key,
    required this.title,
    required this.folders,
    this.initialFolder = '/',
  });

  @override
  State<ChapterFolderPickerScreen> createState() =>
      _ChapterFolderPickerScreenState();
}

class _ChapterFolderPickerScreenState extends State<ChapterFolderPickerScreen> {
  String _currentFolder = '/';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentFolder = Tag.normalizeFolderPath(widget.initialFolder);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _allFolders {
    final set = <String>{'/'};
    for (final folder in widget.folders) {
      set.add(Tag.normalizeFolderPath(folder));
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> get _subFolders {
    final sub = <String>{};
    for (final folder in _allFolders) {
      if (!folder.startsWith(_currentFolder) || folder == _currentFolder) {
        continue;
      }
      var relative = folder.substring(_currentFolder.length);
      if (relative.startsWith('/')) relative = relative.substring(1);
      if (relative.isEmpty) continue;
      final first = relative.split('/').first;
      if (first.isEmpty) continue;
      final fullPath = _currentFolder == '/'
          ? '/$first'
          : '$_currentFolder/$first';
      sub.add(fullPath);
    }
    final list = sub.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> get _searchResults {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _allFolders
        .where((f) => f == '/' || f.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  String _label(String folderPath) {
    if (folderPath == '/') return tr('Без папки');
    return folderPath.substring(1);
  }

  void _openFolder(String path) {
    setState(() {
      _currentFolder = Tag.normalizeFolderPath(path);
      _searchQuery = '';
      _searchController.text = '';
    });
  }

  void _goUp() {
    if (_currentFolder == '/') return;
    final parts = _currentFolder.split('/');
    if (parts.length <= 2) {
      _openFolder('/');
      return;
    }
    parts.removeLast();
    _openFolder(parts.join('/'));
  }

  @override
  Widget build(BuildContext context) {
    final entries = <String>[if (_currentFolder != '/') '..', ..._subFolders];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AdaptiveContent(
        maxWidth: 720,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1E1E1E),
              child: Row(
                children: [
                  const Icon(Icons.folder_open, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _label(_currentFolder),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('Поиск папки'),
                  hintStyle: TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: _searchQuery.trim().isNotEmpty
                  ? ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final folderPath = _searchResults[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.folder,
                            color: Colors.white70,
                          ),
                          title: Text(
                            _label(folderPath),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: folderPath == '/'
                              ? null
                              : Text(
                                  folderPath,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                          onTap: () => _openFolder(folderPath),
                        );
                      },
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final isBack = entry == '..';
                        return ListTile(
                          leading: Icon(
                            isBack
                                ? Icons.keyboard_return_rounded
                                : Icons.folder,
                            color: isBack ? Colors.white54 : Colors.white70,
                          ),
                          title: Text(
                            isBack ? tr('Назад') : p.basename(entry),
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: isBack ? _goUp : () => _openFolder(entry),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _currentFolder),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    tr('Переместить сюда'),
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
