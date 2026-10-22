import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/features/resources/services/resource_providers.dart';
import 'package:canvas_app/features/resources/services/resource_service.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';

class FolderPickerScreen extends ConsumerStatefulWidget {
  final String questId;
  final String? excludePath; // Чтобы нельзя было переместить папку саму в себя

  /// Папка, в которой открыт экран по умолчанию (иначе корень «/»).
  final String? initialFolder;

  /// Заголовок экрана (иначе «Переместить в...»).
  final String? title;

  /// Текст кнопки подтверждения внизу (иначе «Переместить сюда»).
  final String? ctaLabel;

  const FolderPickerScreen({
    super.key,
    required this.questId,
    this.excludePath,
    this.initialFolder,
    this.title,
    this.ctaLabel,
  });

  @override
  ConsumerState<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends ConsumerState<FolderPickerScreen> {
  late String _currentFolder = widget.initialFolder != null
      ? _normalizeFolderPath(widget.initialFolder!)
      : '/';
  List<String> _allFolders = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isGridView = true;

  ResourceService get _svc => ref.read(resourceServiceProvider(widget.questId));

  String _normalizeFolderPath(String path) =>
      ResourceService.normalizeFolderPath(path);

  @override
  void initState() {
    super.initState();
    _loadViewPreference();
    _loadFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isGridView = prefs.getBool('resources_grid_view') ?? true;
      });
    }
  }

  Future<void> _toggleViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _isGridView = !_isGridView);
    await prefs.setBool('resources_grid_view', _isGridView);
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    try {
      final combined = await _svc.loadAllFolders();
      if (mounted) {
        setState(() {
          _allFolders = combined;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isExcluded(String folder) {
    final exclude = widget.excludePath;
    if (exclude == null) return false;
    final normalizedFolder = _normalizeFolderPath(folder);
    final normalizedExclude = _normalizeFolderPath(exclude);
    return normalizedFolder == normalizedExclude ||
        normalizedFolder.startsWith('$normalizedExclude/');
  }

  List<String> get _currentSubFolders {
    final sub = <String>{};
    for (final raw in _allFolders) {
      final f = _normalizeFolderPath(raw);
      if (_isExcluded(f)) continue;

      if (f.startsWith(_currentFolder) && f != _currentFolder) {
        var relative = f.substring(_currentFolder.length);
        if (relative.startsWith('/')) relative = relative.substring(1);
        final parts = relative.split('/');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          sub.add(parts[0]);
        }
      }
    }
    return sub.toList()..sort();
  }

  List<String> get _folderEntries {
    final entries = <String>[];
    if (_currentFolder != '/') entries.add('..');
    entries.addAll(_currentSubFolders);
    return entries;
  }

  List<String> get _searchResults {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final results = <String>{};
    for (final raw in _allFolders) {
      final f = _normalizeFolderPath(raw);
      if (_isExcluded(f)) continue;
      final name = p.basename(f).toLowerCase();
      if (name.contains(q) || f.toLowerCase().contains(q)) {
        results.add(f);
      }
    }
    return results.toList()..sort();
  }

  void _goUp() {
    if (_currentFolder == '/') return;
    final parts = _currentFolder.split('/');
    if (parts.length <= 2) {
      setState(() => _currentFolder = '/');
    } else {
      parts.removeLast();
      setState(() => _currentFolder = _normalizeFolderPath(parts.join('/')));
    }
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final name = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Новая папка')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Название'), filled: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(tr('Создать')),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty && !name.contains('/')) {
      final newPath = _normalizeFolderPath(
        _currentFolder == '/' ? '/$name' : '$_currentFolder/$name',
      );

      try {
        await _svc.createFolder(newPath);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _allFolders.add(newPath);
        _currentFolder = newPath;
      });
    }
  }

  void _openFolder(String folderPath) {
    setState(() {
      _currentFolder = _normalizeFolderPath(folderPath);
      _searchQuery = '';
      _searchController.clear();
    });
  }

  Widget _buildSearchResults() {
    final scheme = Theme.of(context).colorScheme;
    final results = _searchResults;
    if (results.isEmpty) {
      return Center(
        child: Text(
          tr('Ничего не найдено'),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final folderPath = results[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _FolderPickerListTile(
            icon: Icons.folder_rounded,
            title: folderPath,
            subtitle: tr('Результат поиска'),
            onTap: () => _openFolder(folderPath),
          ),
        );
      },
    );
  }

  Widget _buildFolderList() {
    final entries = _folderEntries;
    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final name = entries[index];
          final isBack = name == '..';
          return _FolderPickerGridCard(
            icon: isBack ? Icons.keyboard_return_rounded : Icons.folder_rounded,
            title: isBack ? tr('Назад') : name,
            subtitle: isBack ? tr('На уровень выше') : tr('Папка'),
            isBack: isBack,
            onTap: isBack
                ? _goUp
                : () => _openFolder(
                    _currentFolder == '/' ? '/$name' : '$_currentFolder/$name',
                  ),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final name = entries[index];
        final isBack = name == '..';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _FolderPickerListTile(
            icon: isBack ? Icons.keyboard_return_rounded : Icons.folder_rounded,
            title: isBack ? tr('Назад') : name,
            subtitle: isBack ? tr('На уровень выше') : tr('Папка'),
            isBack: isBack,
            onTap: isBack
                ? _goUp
                : () => _openFolder(
                    _currentFolder == '/' ? '/$name' : '$_currentFolder/$name',
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.title ?? tr('Переместить в...')),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
            onPressed: _toggleViewMode,
            tooltip: tr('Вид'),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _createNewFolder,
            tooltip: tr('Создать папку'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.folder_open_rounded,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr('Текущая папка'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentFolder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              height: 52,
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: tr('Поиск папки'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchQuery.trim().isNotEmpty
                ? _buildSearchResults()
                : _buildFolderList(),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _currentFolder),
                  icon: const Icon(Icons.drive_file_move_rounded),
                  label: Text(
                    widget.ctaLabel ?? tr('Переместить сюда'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderPickerGridCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isBack;
  final VoidCallback onTap;

  const _FolderPickerGridCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isBack
                      ? scheme.surfaceContainerHighest
                      : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: isBack
                      ? scheme.onSurfaceVariant
                      : scheme.onSecondaryContainer,
                  size: 28,
                ),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderPickerListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isBack;
  final VoidCallback onTap;

  const _FolderPickerListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isBack
                      ? scheme.surfaceContainerHighest
                      : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isBack
                      ? scheme.onSurfaceVariant
                      : scheme.onSecondaryContainer,
                ),
              ),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
              onTap: onTap,
            ),
          ),
        ),
      ),
    );
  }
}
