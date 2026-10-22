import 'dart:async';
import 'dart:io';

import 'package:mnd_player/utils/file_storage.dart';
import 'package:flutter/material.dart';
import 'package:canvas_app/features/editor/services/trigger_service.dart';
import 'package:canvas_app/features/editor/workspace/editor_back_handler.dart';
import 'package:canvas_app/features/editor/workspace/editor_document_lifecycle.dart';
import 'package:canvas_app/features/editor/workspace/editor_workspace_controller.dart';
import 'package:canvas_app/features/editor/workspace/editor_workspace_scope.dart';
import 'package:canvas_app/features/resources/services/resource_service.dart';
import 'package:canvas_app/features/resources/widgets/lua_code_field.dart';
import 'package:canvas_app/features/resources/widgets/lua_editor_scaffold.dart';
import 'package:canvas_app/features/resources/screens/lua_docs_screen.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

// ============================================================================
//  РЕДАКТОР LUA (файл) — Material 3
// ============================================================================

class LuaEditorScreen extends StatefulWidget {
  final String questId;
  final String fileName;

  const LuaEditorScreen({
    super.key,
    required this.questId,
    required this.fileName,
  });

  @override
  State<LuaEditorScreen> createState() => _LuaEditorScreenState();
}

class _LuaEditorScreenState extends State<LuaEditorScreen> {
  String _initialCode = '';
  String _savedCode = '';
  String _code = '';
  String? _questTitle;
  String? _friendlyName;
  String? _folder;
  bool _isLoading = true;
  bool _isSaving = false;
  Timer? _autoSaveTimer;

  String get _filePath =>
      QuestPaths.scriptPath(widget.questId, widget.fileName);

  String get _displayPath {
    final parts = <String>[];
    final title = _questTitle?.trim();
    if (title != null && title.isNotEmpty) parts.add(title);
    final folder = (_folder ?? '').trim();
    if (folder.isNotEmpty && folder != '/') parts.add(folder);
    final display = (_friendlyName ?? '').trim().isNotEmpty
        ? _friendlyName!.trim()
        : widget.fileName;
    parts.add(
      display == widget.fileName || parts.isEmpty
          ? widget.fileName
          : '$display  (${widget.fileName})',
    );
    return parts.join(' / ');
  }

  @override
  void initState() {
    super.initState();
    _loadAndInitController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _docHandle?.registerRuntime(
        EditorDocumentRuntime(
          onSave: () async {
            await _saveScript();
            return true;
          },
          onBeforeClose: () async {
            await _saveSilently();
            return true;
          },
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Захватываем хэндл документа: таймер автосейва и колбэки после await
    // переживают деактивацию элемента — контекстные lookup'ы там запрещены.
    _docHandle = EditorDocumentLifecycle.capture(context);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _docHandle?.invalidated = true;
    super.dispose();
  }

  /// Захваченная ссылка на документ воркспейса.
  EditorDocumentHandle? _docHandle;

  Future<void> _loadAndInitController() async {
    String initialText;
    String? loadedTitle;
    String? loadedName;
    String? loadedFolder;

    try {
      // Читаем имя квеста из config.json
      final configPath = QuestPaths.config(widget.questId);
      if (await FileStorage.exists(configPath)) {
        try {
          final cfg = await FileStorage.readJsonFile(configPath);
          loadedTitle = (cfg['name'] as String?)?.trim().isNotEmpty == true
              ? cfg['name'] as String
              : (cfg['title'] as String?)?.trim();
        } catch (_) {}
      }

      // Человекочитаемое имя и папка — из metadata через ResourceService.
      try {
        final resources = ResourceService.forQuest(widget.questId);
        final res = await resources.findResourceByFileName(widget.fileName);
        if (res != null) {
          loadedName = res.friendlyName;
          loadedFolder = res.folder;
        }
      } catch (_) {}

      if (await FileStorage.exists(_filePath)) {
        final filePath = await FileStorage.getFilePath(_filePath);
        initialText = await File(
          filePath,
        ).readAsString(); // чтение при открытии — вне горячего пути
      } else {
        // Шаблон для нового .lua скрипта.
        initialText = '''-- Новый Lua-скрипт
function start()
    core.set_var('x', 42)
end
''';
      }
    } catch (e) {
      initialText = '-- Ошибка загрузки: ${friendlyError(e)}';
    }

    if (mounted) {
      setState(() {
        _questTitle = loadedTitle;
        _friendlyName = loadedName;
        _folder = loadedFolder;
        _initialCode = initialText;
        _savedCode = initialText;
        _code = initialText;
        _isLoading = false;
      });
    }
  }

  void _onCodeChanged(String newCode) {
    _code = newCode;
    _docHandle?.markDirty(true);
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1200), () {
      _saveSilently();
    });
  }

  Future<void> _saveSilently() async {
    if (_code == _savedCode || _isSaving) return;
    try {
      await FileStorage.writeTextFile(_filePath, _code);
      _savedCode = _code;
      _docHandle?.markDirty(false);
    } catch (_) {}
  }

  Future<void> _saveScript({bool popOnSuccess = false}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final text = _code;
    try {
      await FileStorage.writeTextFile(_filePath, text);
      _savedCode = text;
      if (mounted) {
        _docHandle?.markDirty(false);
        _showSnack(tr('Lua-скрипт сохранён'), success: true);
        if (popOnSuccess) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack(trf('Ошибка сохранения: {p0}', {'p0': friendlyError(e)}), error: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _closeDocument() async {
    await _saveSilently();
    if (!mounted) return;
    final document = EditorDocumentContext.maybeOf(context);
    final workspace = EditorWorkspaceScope.maybeOf(context);
    if (document != null && workspace != null) {
      await workspace.closeDocument(document.id);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Кнопка «Назад/Отмена»: внутри воркспейса — браузерная история
  /// (вкладка остаётся открытой), в отдельном маршруте — выход с сейвом.
  Future<void> _handleBackButton() async {
    final document = EditorDocumentContext.maybeOf(context);
    final workspace = EditorWorkspaceScope.maybeOf(context);
    if (document != null && workspace != null) {
      await workspace.requestBack();
      return;
    }
    await _closeDocument();
  }

  void _showSnack(String text, {bool success = false, bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    Color? bg;
    Color? fg;
    if (success) {
      bg = scheme.primary;
      fg = scheme.onPrimary;
    } else if (error) {
      bg = scheme.error;
      fg = scheme.onError;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        showCloseIcon: true,
        closeIconColor: fg,
      ),
    );
  }

  void _openDocs() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => LuaDocsScreen()),
    );
  }

  /// «Сохранить в папку…» — переименование/папка через ResourceService.
  Future<void> _showSaveLocation() async {
    final scripts = ScriptService(
      resources: ResourceService.forQuest(widget.questId),
    );
    // Сначала сохраняем текущий код, чтобы изменение имени/папки легло поверх.
    await _saveSilently();
    if (!mounted) return;
    try {
      final changed = await scripts.showSaveLocationSheet(
        context,
        widget.fileName,
      );
      if (changed && mounted) {
        final updated = await scripts.resources.findResourceByFileName(
          widget.fileName,
        );
        if (updated != null) {
          setState(() {
            _friendlyName = updated.friendlyName;
            _folder = updated.folder;
          });
        }
        _showSnack(tr('Сохранено'), success: true);
      }
    } catch (e) {
      if (mounted) _showSnack(trf('Ошибка: {p0}', {'p0': friendlyError(e)}), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return EditorDocumentBackScope(
      onBackPressed: () async {
        await _closeDocument();
        return true;
      },
      child: LuaEditorScaffold(
        title: widget.fileName,
        subtitle: _displayPath,
        isBusy: _isSaving,
        onHelp: _openDocs,
        onCancel: _isLoading ? null : () => unawaited(_handleBackButton()),
        extraActions: [
          IconButton(
            icon: const Icon(Icons.folder_rounded),
            tooltip: tr('Сохранить в папку…'),
            onPressed: _isLoading || _isSaving ? null : _showSaveLocation,
          ),
        ],
        trailingButton: FilledButton.tonalIcon(
          onPressed: _isLoading || _isSaving ? null : () => _saveScript(),
          icon: const Icon(Icons.save_rounded, size: 18),
          label: Text(tr('Сохранить')),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        content: _isLoading
            ? Center(child: CircularProgressIndicator(color: scheme.primary))
            : LuaCodeField(initialCode: _initialCode, onChange: _onCodeChanged),
      ),
    );
  }
}
