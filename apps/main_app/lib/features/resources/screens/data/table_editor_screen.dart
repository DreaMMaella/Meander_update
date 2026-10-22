import 'dart:io';

import 'package:canvas_app/core/services/table_export_service.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/resources/screens/data/table_data_keys_sheet.dart';
import 'package:canvas_app/features/resources/screens/data/table_guide.dart';
import 'package:canvas_app/features/resources/screens/resource_selection_screen.dart';
import 'package:canvas_app/models/quest_table_model.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mnd_player/utils/quest_image_source.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

/// Визуальный редактор таблиц («кассета», ведущая себя как базовый Excel):
/// адресная строка, формула-бар, редактируемые ячейки, вставка фото из
/// ресурсов квеста (хранится только путь `res/...`), импорт/экспорт CSV и
/// XLSX. Значения ячеек — строки-формулы, вычисляемые движком.
class TableEditorScreen extends StatefulWidget {
  final QuestTable table;
  final String questId;
  final Function(QuestTable) onSave;

  /// Если `true` — экран работает как пикер ячейки: редактирование скрыто,
  /// тап по ячейке возвращает `Navigator.pop(context, '{имя["колонка"][N]}')`.
  final bool cellPickerMode;

  const TableEditorScreen({
    super.key,
    required this.table,
    required this.questId,
    required this.onSave,
    this.cellPickerMode = false,
  });

  @override
  State<TableEditorScreen> createState() => _TableEditorScreenState();
}

class _TableEditorScreenState extends State<TableEditorScreen> {
  static const double _colWidth = 170;
  static const double _rowHeight = 48;
  static const double _headerHeight = 38;
  static const double _rowNumWidth = 64;
  static const int _maxUndo = 30;

  late QuestTable _table;
  int? _selRow;
  int _selCol = 0;
  bool _hasEdits = false;

  final TextEditingController _formulaCtrl = TextEditingController();
  final TextEditingController _addrCtrl = TextEditingController();
  final FocusNode _formulaFocus = FocusNode();
  final FocusNode _gridFocus = FocusNode();
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  /// Стек отмены: сериализованные снимки `{columns, rows}`.
  final List<Map<String, dynamic>> _undoStack = [];
  bool _editingFormula = false;

  /// Кэш будущих путей ресурсов (чтобы FutureBuilder не пересоздавался на
  /// каждый rebuild — иначе бесконечный цикл перерисовки).
  final Map<String, Future<File?>> _fileFutures = {};

  static final RegExp _imageExt = RegExp(r'\.(png|jpe?g|webp|gif|bmp)$');

  /// Является ли значение ячейки ссылкой на картинку ресурсов квеста.
  static bool isImageResource(String value) {
    final v = value.trim();
    return v.startsWith('res/') && _imageExt.hasMatch(v.toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    _table = QuestTable(
      name: widget.table.name,
      columns: List.of(widget.table.columns),
      rows: widget.table.rows.map((r) => Map<String, dynamic>.from(r)).toList(),
      data: Map.of(widget.table.data),
    );
  }

  @override
  void dispose() {
    _formulaCtrl.dispose();
    _addrCtrl.dispose();
    _formulaFocus.dispose();
    _gridFocus.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  Выбор ячейки / адрес
  // ---------------------------------------------------------------------------

  String _cellAddress(int row, int col) =>
      '${TableExportService.columnLabel(col)}${row + 1}';

  void _selectCell(int row, int col, {bool scrollIntoView = true}) {
    if (row < 0 || row >= _table.rows.length) return;
    if (col < 0 || col >= _table.columns.length) return;
    _commitFormulaEditIfNeeded();
    setState(() {
      _selRow = row;
      _selCol = col;
      final val = _table.rows[row][_table.columns[col]];
      _formulaCtrl.text = val == null ? '' : val.toString();
      _addrCtrl.text = _cellAddress(row, col);
      _editingFormula = false;
    });
    if (scrollIntoView) _ensureCellVisible(row, col);
  }

  void _ensureCellVisible(int row, int col) {
    if (!_vScroll.hasClients || !_hScroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vScroll.hasClients || !_hScroll.hasClients) return;
      final top = row * _rowHeight;
      final bottom = top + _rowHeight;
      final viewTop = _vScroll.offset + 24;
      final viewBottom = _vScroll.offset + _vScroll.position.viewportDimension;
      if (top < viewTop) {
        _vScroll.jumpTo(
          (top - 8).clamp(0.0, _vScroll.position.maxScrollExtent),
        );
      } else if (bottom > viewBottom) {
        final target = bottom - _vScroll.position.viewportDimension + 8;
        _vScroll.jumpTo(target.clamp(0.0, _vScroll.position.maxScrollExtent));
      }

      final left = col * _colWidth;
      final right = left + _colWidth;
      final viewLeft = _hScroll.offset;
      final viewRight = _hScroll.offset + _hScroll.position.viewportDimension;
      if (left < viewLeft) {
        _hScroll.jumpTo(
          (left - 8).clamp(0.0, _hScroll.position.maxScrollExtent),
        );
      } else if (right > viewRight) {
        final target = right - _hScroll.position.viewportDimension + 8;
        _hScroll.jumpTo(target.clamp(0.0, _hScroll.position.maxScrollExtent));
      }
    });
  }

  /// Ссылка вида `{имя["колонка"][N]}` для выбранной ячейки (N — 1-based).
  String _cellRef(int row, int col) {
    final colName = _table.columns[col].replaceAll('"', r'\"');
    // Номер строки обязательно в своих скобках: {т["цена"]1} движок читает как
    // {т["цена"]} + мусор, «1» съедается молча и вместо ячейки приходит весь
    // столбец. Канон — {т["цена"][1]}, он покрыт тестом ядра.
    return '{${_table.name}["$colName"][${row + 1}]}';
  }

  /// Парсит адрес вида «A12» → (row: 11, col: 0).
  (int, int)? _parseAddress(String raw) {
    final m = RegExp(r'^\s*([A-Za-z]{1,3})\s*(\d+)\s*$').firstMatch(raw);
    if (m == null) return null;
    final letters = m.group(1)!.toUpperCase();
    var col = 0;
    for (final ch in letters.split('')) {
      col = col * 26 + (ch.codeUnitAt(0) - 64);
    }
    final row = int.parse(m.group(2)!) - 1;
    return (row, col - 1);
  }

  void _jumpToAddress(String raw) {
    final parsed = _parseAddress(raw);
    if (parsed == null) {
      _snack(tr('Неверный адрес ячейки (пример: A1)'));
      return;
    }
    final (row, col) = parsed;
    if (row < 0 ||
        row >= _table.rows.length ||
        col < 0 ||
        col >= _table.columns.length) {
      _snack(tr('Ячейка вне диапазона таблицы'));
      return;
    }
    _selectCell(row, col);
  }

  // ---------------------------------------------------------------------------
  //  Формула-бар
  // ---------------------------------------------------------------------------

  void _commitFormulaEditIfNeeded() {
    if (!_editingFormula || _selRow == null) return;
    _applyFormula(_formulaCtrl.text);
  }

  void _applyFormula(String raw) {
    if (_selRow == null) return;
    if (_table.rows.isEmpty) return;
    final col = _table.columns[_selCol];
    final row = _selRow!;
    if (row >= _table.rows.length) return;
    if (_table.rows[row][col] == raw) {
      _editingFormula = false;
      return;
    }
    _pushUndo(columns: false, rows: true);
    setState(() {
      _table.rows[row][col] = raw;
      _editingFormula = false;
      _hasEdits = true;
    });
  }

  void _clearCurrentCell() {
    if (_selRow == null) return;
    _pushUndo(columns: false, rows: true);
    setState(() {
      _table.rows[_selRow!][_table.columns[_selCol]] = '';
      _formulaCtrl.clear();
      _hasEdits = true;
    });
  }

  Future<void> _insertImageIntoCurrent() async {
    if (_selRow == null) {
      _snack(tr('Сначала выберите ячейку'));
      return;
    }
    final res = await Navigator.push<SelectableResource>(
      context,
      MaterialPageRoute(
        builder: (_) => ResourceSelectionScreen(
          questId: widget.questId,
          allowedTypes: const ['image'],
        ),
      ),
    );
    if (res == null || !mounted) return;
    _pushUndo(columns: false, rows: true);
    setState(() {
      _table.rows[_selRow!][_table.columns[_selCol]] = res.path;
      _formulaCtrl.text = res.path;
      _hasEdits = true;
    });
  }

  /// Полноценный редактор формул (выбор переменных, операторы) — как в
  /// блоках скриптов. Возвращаемое значение кладётся в ячейку как есть.
  Future<void> _openFormulaEditor() async {
    final expr = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpressionEditorScreen(
          initialValue: _formulaCtrl.text,
          questId: widget.questId,
        ),
      ),
    );
    if (expr == null || !mounted) return;
    if (_selRow != null) {
      setState(() {
        _formulaCtrl.text = expr;
        _applyFormula(expr);
      });
    } else {
      _formulaCtrl.text = expr;
    }
  }

  // ---------------------------------------------------------------------------
  //  Столбцы и строки
  // ---------------------------------------------------------------------------

  void _pushUndo({required bool columns, required bool rows}) {
    _undoStack.add({
      'columns': columns || rows ? List.of(_table.columns) : _table.columns,
      'rows': rows
          ? _table.rows.map((r) => Map<String, dynamic>.from(r)).toList()
          : _table.rows,
      'data': Map<String, dynamic>.of(_table.data),
    });
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final snap = _undoStack.removeLast();
    setState(() {
      _table.columns = List<String>.from(snap['columns'] as List);
      _table.rows = (snap['rows'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final data = snap['data'];
      if (data is Map) {
        _table.data = Map<String, dynamic>.from(data.cast<String, dynamic>());
      }
      _hasEdits = true;
      if (_selCol >= _table.columns.length) _selCol = 0;
      if ((_selRow ?? 0) >= _table.rows.length) _selRow = null;
      _formulaCtrl.clear();
    });
  }

  /// Ключи хранилища скриптов (`data`) — единственное, что видит блок «Данные».
  Future<void> _editDataKeys() async {
    _commitFormulaEditIfNeeded();
    final next = await showTableDataKeysSheet(context, table: _table);
    if (next == null || !mounted) return;
    if (mapEquals(next, _table.data)) return;
    final before = _table.data.length;
    _pushUndo(columns: false, rows: false);
    setState(() {
      _table.data = next;
      _hasEdits = true;
    });
    _snack(trf('Ключей скриптов: было {before}, стало {p0}', {'before': before, 'p0': next.length}));
  }

  Future<void> _addColumn() async {
    final ctrl = TextEditingController();
    final name = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Новый столбец')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Название')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Добавить')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    if (_table.columns.contains(name)) {
      _snack(trf('Столбец «{col}» уже есть', {'col': name}));
      return;
    }
    _pushUndo(columns: true, rows: true);
    setState(() {
      _table.updateColumns([..._table.columns, name]);
      _hasEdits = true;
      _selCol = _table.columns.length - 1;
    });
  }

  Future<void> _renameColumn(int index) async {
    if (index < 0 || index >= _table.columns.length) return;
    final old = _table.columns[index];
    final ctrl = TextEditingController(text: old);
    final name = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Переименовать столбец')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Сохранить')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == old || !mounted) return;
    if (_table.columns.contains(name)) {
      _snack(trf('Столбец «{col}» уже есть', {'col': name}));
      return;
    }
    _pushUndo(columns: true, rows: true);
    final newCols = [..._table.columns];
    newCols[index] = name;
    for (final row in _table.rows) {
      final v = row.remove(old);
      row[name] = v ?? '';
    }
    setState(() {
      _table.columns = newCols;
      _hasEdits = true;
    });
  }

  void _deleteColumn(int index) {
    if (index < 0 || index >= _table.columns.length) return;
    final col = _table.columns[index];
    _pushUndo(columns: true, rows: true);
    final newCols = [..._table.columns]..remove(col);
    setState(() {
      _table.updateColumns(newCols);
      if (_selCol >= _table.columns.length) _selCol = 0;
      _formulaCtrl.clear();
      _hasEdits = true;
    });
    _snackWithUndo(trf('Столбец «{p0}» удалён', {'p0': col}));
  }

  void _deleteRow(int index) {
    if (index < 0 || index >= _table.rows.length) return;
    _pushUndo(columns: false, rows: true);
    setState(() {
      _table.rows.removeAt(index);
      if ((_selRow ?? 0) >= _table.rows.length) {
        _selRow = _table.rows.isEmpty ? null : _table.rows.length - 1;
      }
      _formulaCtrl.clear();
      _hasEdits = true;
    });
    _snackWithUndo(trf('Строка {p0} удалена', {'p0': index + 1}));
  }

  /// Вставляет пустую строку сразу под выбранной (или в конец, если
  /// ничего не выбрано) и выделяет её — как «Вставить» в Excel.
  void _insertRowBelow() {
    final insertAt = _selRow == null ? _table.rows.length : _selRow! + 1;
    _pushUndo(columns: false, rows: true);
    setState(() {
      _table.rows.insert(insertAt, {for (final col in _table.columns) col: ''});
      _selRow = insertAt;
      _formulaCtrl.clear();
      _hasEdits = true;
    });
    if (_selRow != null) _selectCell(_selRow!, _selCol, scrollIntoView: true);
  }

  void _moveRow(int index, int dir) {
    if (index < 0 || index >= _table.rows.length) return;
    final target = index + dir;
    if (target < 0 || target >= _table.rows.length) return;
    _pushUndo(columns: false, rows: true);
    setState(() {
      final row = _table.rows.removeAt(index);
      _table.rows.insert(target, row);
      _selRow = target;
      _formulaCtrl.clear();
      _hasEdits = true;
    });
  }

  /// Вставляет колонку справа от выбранной (или в конец).
  Future<void> _insertColumnRight() async {
    final ctrl = TextEditingController();
    final name = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Новый столбец')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Название')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Добавить')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    if (_table.columns.contains(name)) {
      _snack(trf('Столбец «{col}» уже есть', {'col': name}));
      return;
    }
    final insertAt = _selRow == null
        ? _table.columns.length
        : (_selCol + 1).clamp(0, _table.columns.length);
    _pushUndo(columns: true, rows: true);
    final newCols = [..._table.columns]..insert(insertAt, name);
    setState(() {
      _table.updateColumns(newCols);
      _selCol = insertAt;
      _hasEdits = true;
    });
  }

  void _moveColumn(int index, int dir) {
    if (index < 0 || index >= _table.columns.length) return;
    final target = index + dir;
    if (target < 0 || target >= _table.columns.length) return;
    final old = _table.columns[index];
    final newCols = [..._table.columns];
    newCols.removeAt(index);
    newCols.insert(target, old);
    _pushUndo(columns: true, rows: true);
    setState(() {
      for (final row in _table.rows) {
        final v = row[old];
        row
          ..remove(old)
          ..removeWhere((key, _) => !newCols.contains(key));
        row[old] = v ?? '';
      }
      _table.columns = newCols;
      _selCol = target;
      _formulaCtrl.clear();
      _hasEdits = true;
    });
  }

  // ---------------------------------------------------------------------------
  //  Импорт CSV / экспорт
  // ---------------------------------------------------------------------------

  Future<void> _importCsv() async {
    final files = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (files.isEmpty || files.single.path == null || !mounted) {
      return;
    }
    try {
      final imported = await TableExportService.importTableFromFile(
        files.single.path!,
      );
      _pushUndo(columns: true, rows: true);
      if (!mounted) return;
      setState(() {
        _table.columns = List.of(imported.columns);
        _table.rows = imported.rows
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        _selRow = null;
        _selCol = 0;
        _formulaCtrl.clear();
        _hasEdits = true;
      });
      _snackWithUndo(
        trf('Импортировано: {p0} столбцов, {p1} строк', {
          'p0': _table.columns.length,
          'p1': _table.rows.length,
        }),
      );
    } catch (e) {
      _snack(trf('Ошибка импорта CSV: {p0}', {'p0': friendlyError(e)}));
    }
  }

  Future<void> _export(String format) async {
    _commitFormulaEditIfNeeded();
    try {
      final ok = switch (format) {
        'csv' => await TableExportService.exportTableCsv(_table),
        'xlsx' => await TableExportService.exportTableXlsx(_table),
        'json' => await TableExportService.exportTableJson(_table),
        _ => false,
      };
      if (ok) {
        // CSV физически не умеет пары «ключ → значение»: без этой строки
        // автор теряет хранилище молча и ищет баг в движке.
        _snack(
          format == 'csv' && _table.data.isNotEmpty
              ? trf('CSV сохранён: в нём только сетка, {p0} ключей хранилища остались здесь', {'p0': _table.data.length})
              : tr('Файл сохранён'),
        );
      }
    } catch (e) {
      _snack(trf('Ошибка экспорта: {p0}', {'p0': friendlyError(e)}));
    }
  }

  // ---------------------------------------------------------------------------
  //  Сохранение / выход
  // ---------------------------------------------------------------------------

  void _save() {
    _commitFormulaEditIfNeeded();
    widget.onSave(_table);
    Navigator.pop(context);
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasEdits) return true;
    final action = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Несохранённые изменения')),
        content: Text(tr('Сохранить таблицу перед выходом?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(tr('Не сохранять')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(tr('Остаться')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(tr('Сохранить')),
          ),
        ],
      ),
    );
    if (action == 'save') {
      _save();
      return false;
    }
    if (action == 'cancel' || action == null) return false;
    return true;
  }

  // ---------------------------------------------------------------------------
  //  UI helpers
  // ---------------------------------------------------------------------------

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  void _snackWithUndo(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: tr('Отменить'), onPressed: _undo),
      ),
    );
  }

  Widget _thumbnail(String path) {
    final future = _fileFutures.putIfAbsent(
      path,
      () => _resolveResourceFile(path),
    );
    return FutureBuilder<File?>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final file = snap.data;
        if (file == null || !file.existsSync()) {
          return const Icon(Icons.broken_image, size: 20, color: Colors.red);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            file,
            width: 40,
            height: 28,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image, size: 20, color: Colors.red),
          ),
        );
      },
    );
  }

  Future<File?> _resolveResourceFile(String relativePath) =>
      QuestImageSource.resolve(widget.questId, relativePath);

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_selRow == null || _table.columns.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final dir = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
      _selectCell(
        (_selRow! + dir).clamp(0, _table.rows.length - 1),
        _selCol,
        scrollIntoView: true,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final dir = event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1;
      _selectCell(
        _selRow!,
        (_selCol + dir).clamp(0, _table.columns.length - 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _selectCell(
        (_selRow! + 1).clamp(0, _table.rows.length - 1),
        _selCol,
        scrollIntoView: true,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: widget.cellPickerMode,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
              ),
              Text(
                widget.cellPickerMode ? tr('Выбор ячейки') : tr('Редактор таблицы'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            if (widget.cellPickerMode)
              IconButton(
                tooltip: tr('Вернуться'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            else ...[
              if (_undoStack.isNotEmpty)
                IconButton(
                  tooltip: tr('Отменить'),
                  icon: const Icon(Icons.undo),
                  onPressed: _undo,
                ),
              IconButton(
                tooltip: _table.data.isEmpty
                    ? tr('Ключи скриптов — пусто')
                    : trf('Ключи скриптов: {n}', {'n': _table.data.length}),
                icon: _table.data.isEmpty
                    ? const Icon(Icons.data_object_rounded)
                    : Badge.count(
                        count: _table.data.length,
                        child: const Icon(Icons.data_object_rounded),
                      ),
                onPressed: _editDataKeys,
              ),
              PopupMenuButton<String>(
                tooltip: tr('Экспорт'),
                icon: const Icon(Icons.ios_share),
                onSelected: _export,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'csv',
                    child: _ExportOption(
                      title: 'CSV',
                      note: tr('только сетка: ключи хранилища в файл не пишутся'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'xlsx',
                    child: _ExportOption(
                      title: 'XLSX (Excel)',
                      note: tr('сетка + отдельный лист «Данные»'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'json',
                    child: _ExportOption(
                      title: 'JSON',
                      note: tr('полный слепок: сетка и хранилище'),
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: tr('Сохранить'),
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: _save,
              ),
            ],
          ],
        ),
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Column(
            children: [
              if (!widget.cellPickerMode) ...[
                _buildToolbar(scheme),
                _buildFormulaBar(scheme),
              ],
              Expanded(child: _buildGrid(scheme)),
              _buildStatusBar(scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _addColumn,
                  icon: const Icon(Icons.view_column_rounded, size: 18),
                  label: Text(tr('Столбец')),
                ),
                FilledButton.tonalIcon(
                  onPressed: _insertRowBelow,
                  icon: const Icon(Icons.table_rows_rounded, size: 18),
                  label: Text(tr('Вставить строку ниже')),
                ),
                OutlinedButton.icon(
                  onPressed: _importCsv,
                  icon: const Icon(Icons.description, size: 18),
                  label: Text(tr('Импорт CSV')),
                ),
                IconButton(
                  tooltip: tr('Редактор формулы'),
                  icon: const Icon(Icons.functions, size: 20),
                  onPressed: _selRow == null ? null : _openFormulaEditor,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Отменить изменение'),
            icon: const Icon(Icons.undo, size: 20),
            onPressed: _undoStack.isEmpty ? null : _undo,
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaBar(ColorScheme scheme) {
    final hasSelection = _selRow != null && _table.columns.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: scheme.surfaceContainer,
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64, maxWidth: 96),
            child: TextField(
              controller: _addrCtrl,
              enabled: hasSelection,
              style: GoogleFonts.firaCode(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: scheme.primary),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: scheme.primary),
                ),
                disabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                hintText: 'A1',
                hintStyle: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              onSubmitted: _jumpToAddress,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _formulaCtrl,
              focusNode: _formulaFocus,
              enabled: hasSelection,
              style: GoogleFonts.firaCode(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                hintText: tr('Значение или формула, напр. {gold} + 2'),
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr('Вставить картинку из ресурсов'),
                      icon: const Icon(Icons.image, size: 20),
                      onPressed: hasSelection ? _insertImageIntoCurrent : null,
                    ),
                    IconButton(
                      tooltip: tr('Очистить ячейку'),
                      icon: const Icon(Icons.backspace, size: 20),
                      onPressed: hasSelection ? _clearCurrentCell : null,
                    ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() => _editingFormula = true),
              onSubmitted: (raw) {
                _applyFormula(raw);
                if (_selRow != null) {
                  final nextRow = (_selRow! + 1).clamp(
                    0,
                    _table.rows.length - 1,
                  );
                  _selectCell(nextRow, _selCol);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: applyFormulaTooltip,
            icon: Icon(
              Icons.check,
              size: 22,
              color: _editingFormula ? scheme.primary : scheme.onSurfaceVariant,
            ),
            onPressed: hasSelection && _editingFormula
                ? () => _applyFormula(_formulaCtrl.text)
                : null,
          ),
        ],
      ),
    );
  }

  static String get applyFormulaTooltip => tr('Применить');

  Widget _buildGrid(ColorScheme scheme) {
    if (_table.columns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart, size: 56, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              tr('Нет столбцов'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _addColumn,
              icon: const Icon(Icons.view_column_rounded, size: 18),
              label: Text(tr('Добавить столбец')),
            ),
          ],
        ),
      );
    }

    return Scrollbar(
      controller: _vScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _vScroll,
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: _buildTableBody(scheme),
        ),
      ),
    );
  }

  Widget _buildTableBody(ColorScheme scheme) {
    final headerFill = scheme.surfaceContainerHighest;

    final headerCells = <Widget>[
      _cornerCell(scheme, headerFill),
      for (var c = 0; c < _table.columns.length; c++)
        _columnHeader(scheme, c, headerFill),
    ];

    final bodyRows = <TableRow>[
      TableRow(children: headerCells),
      for (var r = 0; r < _table.rows.length; r++) _dataRow(scheme, r),
    ];

    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(_rowNumWidth),
      for (var c = 0; c < _table.columns.length; c++)
        c + 1: const FixedColumnWidth(_colWidth),
    };

    return Table(
      columnWidths: columnWidths,
      border: TableBorder.all(color: scheme.outlineVariant, width: 1),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: bodyRows,
    );
  }

  Widget _cornerCell(ColorScheme scheme, Color fill) {
    final totalCells = _table.rows.length * _table.columns.length;
    return Container(
      height: _headerHeight,
      width: _rowNumWidth,
      alignment: Alignment.center,
      color: fill,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        totalCells > 0 ? trf('{totalCells} яч.', {'totalCells': totalCells}) : '—',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
      ),
    );
  }

  Widget _columnHeader(ColorScheme scheme, int col, Color fill) {
    final isSelected =
        _selRow != null && _selCol == col && _table.columns.isNotEmpty;
    final name = _table.columns[col];
    return InkWell(
      onTap: () {
        if (_table.rows.isNotEmpty) _selectCell(0, col, scrollIntoView: true);
      },
      onLongPress: () => _columnMenu(scheme, col),
      // ПК: меню колонки по правой кнопке, а не долгим тапом.
      onSecondaryTap: () => _columnMenu(scheme, col),
      child: Container(
        height: _headerHeight,
        constraints: const BoxConstraints(minWidth: _colWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : fill,
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 4),
            _tinyButton(
              tooltip: tr('Влево'),
              icon: Icons.chevron_left,
              color: scheme.onSurfaceVariant,
              onTap: col > 0 ? () => _moveColumn(col, -1) : null,
            ),
            _tinyButton(
              tooltip: tr('Вправо'),
              icon: Icons.chevron_right,
              color: scheme.onSurfaceVariant,
              onTap: col < _table.columns.length - 1
                  ? () => _moveColumn(col, 1)
                  : null,
            ),
            _tinyButton(
              tooltip: tr('Меню столбца'),
              icon: Icons.more_vert,
              color: scheme.onSurfaceVariant,
              onTap: () => _columnMenu(scheme, col),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _columnMenu(ColorScheme scheme, int col) async {
    if (col < 0 || col >= _table.columns.length) return;
    _selectCell(_selRow ?? 0, col, scrollIntoView: false);
    final action = await showAdaptiveSheet<String>(
      context: context,
      scrollable: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                trf('Столбец «{p0}»', {'p0': _table.columns[col]}),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              dense: true,
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(tr('Переименовать')),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.view_column_rounded),
              title: Text(tr('Вставить столбец справа')),
              onTap: () => Navigator.pop(ctx, 'insertRight'),
            ),
            ListTile(
              leading: const Icon(Icons.chevron_left),
              title: Text(tr('Переместить влево')),
              enabled: col > 0,
              onTap: () => Navigator.pop(ctx, 'left'),
            ),
            ListTile(
              leading: const Icon(Icons.chevron_right),
              title: Text(tr('Переместить вправо')),
              enabled: col < _table.columns.length - 1,
              onTap: () => Navigator.pop(ctx, 'right'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                tr('Удалить столбец'),
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _renameColumn(col);
      case 'insertRight':
        await _insertColumnRight();
      case 'left':
        _moveColumn(col, -1);
      case 'right':
        _moveColumn(col, 1);
      case 'delete':
        _deleteColumn(col);
    }
  }

  TableRow _dataRow(ColorScheme scheme, int r) {
    final rowIsSelected = _selRow == r;
    final cells = <Widget>[
      _rowNumberCell(scheme, r, rowIsSelected),
      for (var c = 0; c < _table.columns.length; c++)
        _dataCell(scheme, r, c, rowIsSelected),
    ];
    return TableRow(children: cells);
  }

  Widget _rowNumberCell(ColorScheme scheme, int r, bool isSelectedRow) {
    return Container(
      width: _rowNumWidth,
      height: _rowHeight,
      color: isSelectedRow
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${r + 1}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(width: 2),
          _tinyButton(
            tooltip: tr('Переместить выше'),
            icon: Icons.arrow_upward,
            color: scheme.onSurfaceVariant,
            onTap: r > 0 ? () => _moveRow(r, -1) : null,
          ),
          _tinyButton(
            tooltip: tr('Переместить ниже'),
            icon: Icons.arrow_downward,
            color: scheme.onSurfaceVariant,
            onTap: r < _table.rows.length - 1 ? () => _moveRow(r, 1) : null,
          ),
          _tinyButton(
            tooltip: tr('Удалить строку'),
            icon: Icons.close,
            color: scheme.error,
            onTap: () => _deleteRow(r),
          ),
        ],
      ),
    );
  }

  Widget _tinyButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Icon(
            icon,
            size: 13,
            color: onTap == null ? color.withValues(alpha: 0.3) : color,
          ),
        ),
      ),
    );
  }

  Widget _dataCell(ColorScheme scheme, int r, int c, bool isSelectedRow) {
    final col = _table.columns[c];
    final raw = _table.rows[r][col];
    final value = raw == null ? '' : raw.toString();
    final isSelected = _selRow == r && _selCol == c;
    final isImage = isImageResource(value);

    return GestureDetector(
      onTap: () {
        if (widget.cellPickerMode) {
          Navigator.pop(context, _cellRef(r, c));
          return;
        }
        _gridFocus.requestFocus();
        _selectCell(r, c, scrollIntoView: false);
      },
      onDoubleTap: widget.cellPickerMode
          ? null
          : () {
              // На ПК двойной клик по ячейке открывает редактор формулы — так
              // же, как долгий тап на телефоне; без этого мышью в формулу не
              // попасть, а двойной клик ничего и не делал.
              _selectCell(r, c, scrollIntoView: false);
              if (isDesktopWidth(context)) _openFormulaEditor();
            },
      onLongPress: widget.cellPickerMode
          ? null
          : () {
              _selectCell(r, c, scrollIntoView: false);
              _openFormulaEditor();
            },
      child: Container(
        height: _rowHeight,
        constraints: const BoxConstraints(minWidth: _colWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primaryContainer.withValues(alpha: 0.30)
              : (isSelectedRow ? scheme.surfaceContainerHigh : null),
          border: isSelected
              ? Border.all(color: scheme.primary, width: 2)
              : null,
        ),
        alignment: Alignment.centerLeft,
        child: isImage
            ? Row(
                children: [
                  SizedBox(width: 40, height: 28, child: _thumbnail(value)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.firaCode(
                  color: scheme.onSurface,
                  fontSize: 13,
                ),
              ),
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme scheme) {
    if (widget.cellPickerMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        child: Row(
          children: [
            Icon(Icons.touch_app, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Нажмите на ячейку, чтобы вставить ссылку на неё в текст'),
                style: TextStyle(color: scheme.onSurface, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final statusText = <String>[
      '${_table.rows.length} строк',
      '${_table.columns.length} столбцов',
    ];
    final extras = <String>[];
    final allKeys = _table.rows.fold<Set<String>>({}, (acc, r) {
      acc.addAll(r.keys);
      return acc;
    });
    final strayKeys = allKeys.difference(_table.columns.toSet());
    if (strayKeys.isNotEmpty) {
      extras.add('лишние ключи: ${strayKeys.join(', ')}');
    }
    // Отдельно говорим про хранилище скриптов: без этой строки автор думает,
    // что блок «Данные» читает сетку.
    final dataHint = _table.data.isEmpty
        ? tr('ключей скриптов нет')
        : trf('ключей скриптов: {p0}', {'p0': _table.data.length});

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: InkWell(
                onTap: _editDataKeys,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Text(
                    [statusText.join(' · '), dataHint, ...extras].join(' · '),
                    maxLines: 1,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_selRow != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                trf('Выбрано: {p0}', {'p0': _cellAddress(_selRow!, _selCol)}),
                maxLines: 1,
                style: TextStyle(color: scheme.primary, fontSize: 12),
              ),
            ),
          IconButton(
            tooltip: tr('Как устроена таблица'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.help_outline_rounded, size: 18),
            onPressed: () =>
                showTableGuide(context, exampleTable: _table.name),
          ),
        ],
      ),
    );
  }
}

/// Пункт меню экспорта: формат и одна строка о том, что в него попадает.
class _ExportOption extends StatelessWidget {
  final String title;
  final String note;

  const _ExportOption({required this.title, required this.note});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        Text(
          note,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
