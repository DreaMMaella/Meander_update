import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

// ============================================================================
//  ПОЛЕ РЕДАКТИРОВАНИЯ LUA на re_editor (Material 3) + Mobile Quick Toolbar
// ============================================================================

class LuaCodeField extends StatefulWidget {
  final String initialCode;
  final void Function(String code)? onChange;

  const LuaCodeField({
    super.key,
    this.initialCode = '',
    this.onChange,
  });

  @override
  State<LuaCodeField> createState() => _LuaCodeFieldState();
}

class _LuaCodeFieldState extends State<LuaCodeField> {
  late final CodeLineEditingController _controller;
  Timer? _debounce;
  List<CodeKeywordPrompt> _suggestions = const [];

  /// Прогрел подсказок до ответа ядра: список обязан совпадать с регистрацией
  /// `core.*` в Rust (`crates/mnd-core/src/lua/mod.rs`), за разъезд там
  /// отвечает тест, а здесь эти же имена ещё и чипы тулбара.
  static const Set<String> _kCoreWords = {
    'core.get_var',
    'core.set_var',
    'core.get_table',
    'core.set_table',
    'core.go_to',
    'core.play_sound',
    'core.stop_sound',
    'core.play_music',
    'core.stop_music',
    'core.pause_resume',
    'core.set_volume',
    'core.set_blur',
    'core.set_item_visible',
    'core.set_item_image',
    'core.open_link',
  };

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.initialCode);
    _scheduleCompletion();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get fullText => _controller.text;

  void _onTextChanged(String text) {
    widget.onChange?.call(text);
    _scheduleCompletion();
  }

  void _scheduleCompletion() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _fetchSuggestions);
  }

  Future<void> _fetchSuggestions() async {
    if (!mounted) return;
    final text = _controller.text;
    final selection = _controller.selection;
    if (selection.extentIndex < 0 || selection.extentIndex >= _controller.codeLines.length) {
      return;
    }

    final line = _controller.codeLines[selection.extentIndex];
    final cursor = selection.extentOffset.clamp(0, line.text.length);

    try {
      final suggestions = await fetchLuaCompletions(text, cursor);
      if (!mounted || _controller.text != text) return;

      final words = <String>{
        ..._kCoreWords,
        ...suggestions
            .map((s) => s.insertText.isNotEmpty ? s.insertText : s.label)
            .where((w) => w.isNotEmpty),
      };

      setState(() {
        _suggestions = words.map((w) => CodeKeywordPrompt(word: w)).toList();
      });
    } catch (_) {}
  }

  void _insertSnippet(String snippet, {int cursorOffset = 0}) {
    _controller.replaceSelection(snippet);
    if (cursorOffset != 0) {
      final newOffset = (_controller.selection.extentOffset + cursorOffset).clamp(0, _controller.text.length);
      _controller.selection = _controller.selection.copyWith(
        baseOffset: newOffset,
        extentOffset: newOffset,
      );
    }
    _onTextChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final codeBackground = isDark ? const Color(0xFF1E1E24) : scheme.surfaceContainerHigh;
    final textColor = isDark ? const Color(0xFFDCDFE4) : scheme.onSurface;

    final codeFont = GoogleFonts.jetBrainsMono().fontFamily ??
        GoogleFonts.firaCode().fontFamily;

    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: codeBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: CodeAutocomplete(
              promptsBuilder: _LuaPromptsBuilder(suggestions: _suggestions),
              viewBuilder: (context, notifier, onSelected) =>
                  _LuaAutocompleteView(
                notifier: notifier,
                onSelected: onSelected,
              ),
              child: CodeEditor(
                controller: _controller,
                style: CodeEditorStyle(
                  fontSize: 13.5,
                  fontFamily: codeFont,
                  fontHeight: 1.5,
                  backgroundColor: codeBackground,
                  textColor: textColor,
                  selectionColor: scheme.primary.withValues(alpha: 0.25),
                  highlightColor: Colors.transparent,
                  cursorColor: scheme.primary,
                  cursorLineColor: Colors.transparent,
                  codeTheme: CodeHighlightTheme(
                    languages: {
                      'lua': CodeHighlightThemeMode(mode: langLua),
                    },
                    theme: theme,
                  ),
                ),
                wordWrap: true,
                padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
                margin: EdgeInsets.zero,
                indicatorBuilder: (context, editingController, chunkController, notifier) {
                  return Row(
                    children: [
                      DefaultCodeLineNumber(
                        controller: editingController,
                        notifier: notifier,
                        textStyle: TextStyle(
                          color: isDark
                              ? const Color(0xFF5C6370)
                              : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 11.5,
                          fontFamily: codeFont,
                        ),
                        focusedTextStyle: TextStyle(
                          color: scheme.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: codeFont,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  );
                },
                onChanged: (value) => _onTextChanged(_controller.text),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _MobileLuaToolbar(
          scheme: scheme,
          isDark: isDark,
          onUndo: () {
            _controller.undo();
            _onTextChanged(_controller.text);
          },
          onRedo: () {
            _controller.redo();
            _onTextChanged(_controller.text);
          },
          onIndent: () {
            _controller.applyIndent();
            _onTextChanged(_controller.text);
          },
          onOutdent: () {
            _controller.applyOutdent();
            _onTextChanged(_controller.text);
          },
          onInsertSnippet: _insertSnippet,
        ),
      ],
    );
  }
}

/// Мобильная панель быстрого ввода символов и сниппетов Lua.
class _MobileLuaToolbar extends StatelessWidget {
  final ColorScheme scheme;
  final bool isDark;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onIndent;
  final VoidCallback onOutdent;
  final void Function(String snippet, {int cursorOffset}) onInsertSnippet;

  const _MobileLuaToolbar({
    required this.scheme,
    required this.isDark,
    required this.onUndo,
    required this.onRedo,
    required this.onIndent,
    required this.onOutdent,
    required this.onInsertSnippet,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        children: [
          _ToolIconButton(
            icon: Icons.undo_rounded,
            tooltip: tr('Отменить'),
            onTap: onUndo,
            scheme: scheme,
          ),
          _ToolIconButton(
            icon: Icons.redo_rounded,
            tooltip: tr('Повторить'),
            onTap: onRedo,
            scheme: scheme,
          ),
          const _ToolbarDivider(),
          _ToolIconButton(
            icon: Icons.format_indent_decrease_rounded,
            tooltip: tr('Уменьшить отступ'),
            onTap: onOutdent,
            scheme: scheme,
          ),
          _ToolIconButton(
            icon: Icons.format_indent_increase_rounded,
            tooltip: tr('Отступ Tab'),
            onTap: onIndent,
            scheme: scheme,
          ),
          const _ToolbarDivider(),
          _SymbolChip(label: '()', onTap: () => onInsertSnippet('()', cursorOffset: -1), scheme: scheme),
          _SymbolChip(label: '{}', onTap: () => onInsertSnippet('{}', cursorOffset: -1), scheme: scheme),
          _SymbolChip(label: '[]', onTap: () => onInsertSnippet('[]', cursorOffset: -1), scheme: scheme),
          _SymbolChip(label: r"['']", onTap: () => onInsertSnippet(r"['']", cursorOffset: -2), scheme: scheme),
          _SymbolChip(label: "''", onTap: () => onInsertSnippet("''", cursorOffset: -1), scheme: scheme),
          _SymbolChip(label: '""', onTap: () => onInsertSnippet('""', cursorOffset: -1), scheme: scheme),
          _SymbolChip(label: '=', onTap: () => onInsertSnippet(' = '), scheme: scheme),
          _SymbolChip(label: '==', onTap: () => onInsertSnippet(' == '), scheme: scheme),
          _SymbolChip(label: '~=', onTap: () => onInsertSnippet(' ~= '), scheme: scheme),
          _SymbolChip(label: '..', onTap: () => onInsertSnippet(' .. '), scheme: scheme),
          _SymbolChip(label: ':', onTap: () => onInsertSnippet(':'), scheme: scheme),
          _SymbolChip(label: ',', onTap: () => onInsertSnippet(', '), scheme: scheme),
          const _ToolbarDivider(),
          _SnippetChip(label: 'local', snippet: 'local ', scheme: scheme, onInsert: onInsertSnippet),
          _SnippetChip(label: 'function', snippet: 'function ()\n\nend', cursorOffset: -6, scheme: scheme, onInsert: onInsertSnippet),
          _SnippetChip(label: 'end', snippet: 'end', scheme: scheme, onInsert: onInsertSnippet),
          _SnippetChip(label: 'return', snippet: 'return ', scheme: scheme, onInsert: onInsertSnippet),
          _SnippetChip(label: 'if..then', snippet: 'if  then\n\nend', cursorOffset: -8, scheme: scheme, onInsert: onInsertSnippet),
          _SnippetChip(label: 'else', snippet: 'else\n    ', scheme: scheme, onInsert: onInsertSnippet),
          _SnippetChip(label: 'elseif', snippet: 'elseif  then', cursorOffset: -5, scheme: scheme, onInsert: onInsertSnippet),
          const _ToolbarDivider(),
          _SnippetChip(label: 'core.get_var', snippet: 'core.get_var('')', cursorOffset: -2, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.set_var', snippet: 'core.set_var('', )', cursorOffset: -4, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.get_table', snippet: 'core.get_table('')', cursorOffset: -2, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.set_table', snippet: 'core.set_table('', )', cursorOffset: -4, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          const _ToolbarDivider(),
          _SnippetChip(label: 'core.go_to', snippet: 'core.go_to('')', cursorOffset: -2, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.play_sound', snippet: 'core.play_sound('')', cursorOffset: -2, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.stop_sound', snippet: 'core.stop_sound('')', cursorOffset: -2, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.play_music', snippet: 'core.play_music('')', cursorOffset: -2, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.stop_music', snippet: 'core.stop_music()', scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.pause_resume', snippet: 'core.pause_resume('', )', cursorOffset: -4, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.set_volume', snippet: 'core.set_volume('', )', cursorOffset: -4, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.set_blur', snippet: 'core.set_blur(10)', scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.set_item_visible', snippet: 'core.set_item_visible('', '')', cursorOffset: -6, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.set_item_image', snippet: 'core.set_item_image('', '')', cursorOffset: -6, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
          _SnippetChip(label: 'core.open_link', snippet: 'core.open_link('')', cursorOffset: -2, scheme: scheme, onInsert: onInsertSnippet, isAccent: true),
        ],
      ),
    );
  }
}

class _ToolIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _ToolIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      iconSize: 18,
      tooltip: tooltip,
      icon: Icon(icon, color: scheme.onSurfaceVariant),
      onPressed: onTap,
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

class _SymbolChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _SymbolChip({
    required this.label,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SnippetChip extends StatelessWidget {
  final String label;
  final String snippet;
  final int cursorOffset;
  final ColorScheme scheme;
  final void Function(String snippet, {int cursorOffset}) onInsert;
  final bool isAccent;

  const _SnippetChip({
    required this.label,
    required this.snippet,
    this.cursorOffset = 0,
    required this.scheme,
    required this.onInsert,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: Material(
        color: isAccent
            ? scheme.primaryContainer.withValues(alpha: 0.8)
            : scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onInsert(snippet, cursorOffset: cursorOffset),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: isAccent
                    ? scheme.onPrimaryContainer
                    : scheme.onSecondaryContainer,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LuaPromptsBuilder implements CodeAutocompletePromptsBuilder {
  final List<CodeKeywordPrompt> suggestions;

  const _LuaPromptsBuilder({required this.suggestions});

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (!selection.isCollapsed || codeLine.text.isEmpty) {
      return null;
    }

    final text = codeLine.text;
    final offset = selection.extentOffset.clamp(0, text.length);
    final start =
        text.lastIndexOf(RegExp(r'[\s\(\)\[\]\{\},;]'), offset > 0 ? offset - 1 : 0) +
            1;
    final safeStart = start.clamp(0, offset);
    final input = text.substring(safeStart, offset);
    if (input.isEmpty) return null;

    final matches = suggestions.where((p) => p.match(input)).take(10).toList();
    if (matches.isEmpty) return null;

    return CodeAutocompleteEditingValue(
      input: input,
      prompts: matches,
      index: 0,
    );
  }
}

class _LuaAutocompleteView extends StatelessWidget
    implements PreferredSizeWidget {
  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  const _LuaAutocompleteView({
    required this.notifier,
    required this.onSelected,
  });

  @override
  Size get preferredSize => const Size(320, 220);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, _) {
        return Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          color: scheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: value.prompts.length,
              itemBuilder: (context, index) {
                final prompt = value.prompts[index];
                final isSelected = index == value.index;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: scheme.primaryContainer,
                  leading: Icon(
                    Icons.data_object_rounded,
                    size: 16,
                    color: isSelected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  title: Text(
                    prompt.word,
                    style: TextStyle(
                      color: isSelected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                      fontSize: 12.5,
                    ),
                  ),
                  onTap: () => onSelected(prompt.autocomplete),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
