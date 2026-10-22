import 'package:canvas_app/models/template_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:flutter/material.dart';

/// Результат диалога «Сохранить как шаблон».
class TemplateSaveDialogResult {
  final String name;
  final String? description;
  final String? category;
  final TemplateScope scope;

  const TemplateSaveDialogResult({
    required this.name,
    required this.scope,
    this.description,
    this.category,
  });
}

/// Универсальный диалог сохранения шаблона (нода / контент / строка / столбец).
///
/// [allowQuestScope] — если false, опция «только в этом квесте» скрывается
/// (используется, когда квест ещё не загружен).
class TemplateSaveDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final TemplateKind kind;
  final bool allowQuestScope;
  final TemplateScope initialScope;

  const TemplateSaveDialog({
    super.key,
    required this.title,
    required this.kind,
    this.initialName,
    this.allowQuestScope = true,
    this.initialScope = TemplateScope.quest,
  });

  static Future<TemplateSaveDialogResult?> show(
    BuildContext context, {
    required String title,
    required TemplateKind kind,
    String? initialName,
    bool allowQuestScope = true,
    TemplateScope initialScope = TemplateScope.quest,
  }) {
    return showAppDialog<TemplateSaveDialogResult>(
      context: context,
      builder: (_) => TemplateSaveDialog(
        title: title,
        kind: kind,
        initialName: initialName,
        allowQuestScope: allowQuestScope,
        initialScope: initialScope,
      ),
    );
  }

  @override
  State<TemplateSaveDialog> createState() => _TemplateSaveDialogState();
}

class _TemplateSaveDialogState extends State<TemplateSaveDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _categoryCtrl;
  late TemplateScope _scope;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _descCtrl = TextEditingController();
    _categoryCtrl = TextEditingController();
    _scope = widget.allowQuestScope
        ? widget.initialScope
        : TemplateScope.global;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _kindBadge(widget.kind),
                const SizedBox(width: 8),
                Text(
                  widget.kind.displayName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(tr('Название шаблона *')),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(tr('Описание (необязательно)')),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(tr('Категория (например, UI)')),
            ),
            const SizedBox(height: 16),
            if (widget.allowQuestScope) ...[
              Text(
                tr('Где сохранить'),
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 6),
              SegmentedButton<TemplateScope>(
                segments: [
                  ButtonSegment(
                    value: TemplateScope.quest,
                    label: Text(tr('Только этот квест')),
                    icon: Icon(Icons.folder_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: TemplateScope.global,
                    label: Text(tr('Глобально')),
                    icon: Icon(Icons.public_rounded, size: 16),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (s) => setState(() => _scope = s.first),
              ),
            ] else
              Text(
                tr('Сохраняется в глобальные шаблоны.'),
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Отмена')),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.bookmark_add_rounded, size: 18),
          label: Text(tr('Сохранить')),
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(tr('Введите название шаблона')),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              TemplateSaveDialogResult(
                name: name,
                description: _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
                category: _categoryCtrl.text.trim().isEmpty
                    ? null
                    : _categoryCtrl.text.trim(),
                scope: _scope,
              ),
            );
          },
        ),
      ],
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white60),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.cyanAccent),
    ),
  );

  Widget _kindBadge(TemplateKind kind) {
    final IconData icon;
    final Color color;
    switch (kind) {
      case TemplateKind.node:
        icon = Icons.account_tree_rounded;
        color = Colors.cyanAccent;
        break;
      case TemplateKind.row:
        icon = Icons.table_rows_rounded;
        color = Colors.orangeAccent;
        break;
      case TemplateKind.column:
        icon = Icons.view_column_rounded;
        color = Colors.purpleAccent;
        break;
      case TemplateKind.modal:
        icon = Icons.web_asset_rounded;
        color = Colors.tealAccent;
        break;
      case TemplateKind.content:
        icon = Icons.widgets_rounded;
        color = Colors.lightBlueAccent;
        break;
      case TemplateKind.chapter:
        icon = Icons.book_rounded;
        color = Colors.greenAccent;
        break;
      case TemplateKind.multi:
        icon = Icons.dynamic_feed_rounded;
        color = Colors.amberAccent;
        break;
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}
