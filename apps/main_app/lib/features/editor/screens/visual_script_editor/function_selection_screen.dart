import 'package:mnd_core/engine/script_executor.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_core/contracts/script_runtime.dart';
import 'package:flutter/material.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

class SelectableFunction {
  final String scriptId;
  final String scriptName;
  final String functionEntry;
  final bool isInternal;

  const SelectableFunction({
    required this.scriptId,
    required this.scriptName,
    required this.functionEntry,
    required this.isInternal,
  });

  String get displayName => '$scriptName :: $functionEntry';
}

class FunctionSelectionScreen extends StatefulWidget {
  final String questId;

  const FunctionSelectionScreen({super.key, required this.questId});

  @override
  State<FunctionSelectionScreen> createState() =>
      _FunctionSelectionScreenState();
}

class _FunctionSelectionScreenState extends State<FunctionSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<SelectableFunction> _functions = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFunctions();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFunctions() async {
    setState(() => _isLoading = true);
    final loaded = <SelectableFunction>[];
    final tasks = <Future<List<SelectableFunction>>>[];

    final folders = [
      (QuestPaths.scriptsDir(widget.questId), false),
      (QuestPaths.internalScriptsDir(widget.questId), true),
    ];

    for (final (folder, isInternal) in folders) {
      if (!await FileStorage.exists(folder)) continue;
      final files = await FileStorage.listFiles(folder, extension: '.json');
      for (final fileName in files) {
        tasks.add(
          _extractFunctionsFromFile(
            folder: folder,
            fileName: fileName,
            isInternal: isInternal,
          ),
        );
      }
    }

    final chunks = await Future.wait(tasks);
    for (final chunk in chunks) {
      loaded.addAll(chunk);
    }

    loaded.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    if (!mounted) return;
    setState(() {
      _functions = loaded;
      _isLoading = false;
    });
  }

  Future<List<SelectableFunction>> _extractFunctionsFromFile({
    required String folder,
    required String fileName,
    required bool isInternal,
  }) async {
    final dotIndex = fileName.lastIndexOf('.');
    final scriptId = dotIndex == -1
        ? fileName
        : fileName.substring(0, dotIndex);
    if (scriptId.isEmpty) return const [];

    try {
      final data = await FileStorage.readJsonFile('$folder/$fileName');
      final scriptNameRaw = data['name']?.toString().trim();
      final scriptName = (scriptNameRaw == null || scriptNameRaw.isEmpty)
          ? fileName
          : scriptNameRaw;

      final blocks = data['blocks'] as List<dynamic>? ?? const [];
      final functionEntries = <String>{};
      for (final block in blocks) {
        if (block is! Map<String, dynamic>) continue;
        if (block['type']?.toString() != 'event') continue;
        if (block['eventType']?.toString() != EventType.function.name) {
          continue;
        }
        final entry = block['functionName']?.toString().trim();
        if (entry == null || entry.isEmpty) {
          functionEntries.add('main');
        } else {
          functionEntries.add(entry);
        }
      }

      if (functionEntries.isEmpty &&
          ScriptExecutor.checkScriptEventType(data) == EventType.function) {
        functionEntries.add('main');
      }

      return functionEntries
          .map(
            (entry) => SelectableFunction(
              scriptId: scriptId,
              scriptName: scriptName,
              functionEntry: entry,
              isInternal: isInternal,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _functions.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.displayName.toLowerCase().contains(_searchQuery) ||
          item.scriptId.toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          tr('Выбор функции'),
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: AdaptiveContent(
        maxWidth: 800,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: tr('Поиск функции'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: scheme.primary),
                    )
                  : filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.search_off_rounded,
                                color: scheme.onSurfaceVariant,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              tr('Функции не найдены'),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final iconBg = item.isInternal
                            ? scheme.tertiaryContainer
                            : scheme.primaryContainer;
                        final iconFg = item.isInternal
                            ? scheme.onTertiaryContainer
                            : scheme.onPrimaryContainer;
                        return Material(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: iconBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                item.isInternal
                                    ? Icons.lock_outline_rounded
                                    : Icons.functions_rounded,
                                color: iconFg,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              item.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              item.scriptId,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: scheme.onSurfaceVariant.withOpacity(0.5),
                            ),
                            onTap: () => Navigator.pop(context, item),
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
