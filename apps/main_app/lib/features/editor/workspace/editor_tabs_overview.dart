import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'editor_document.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Полноэкранный браузерный обзор вкладок рабочего пространства.
class EditorTabsOverview extends StatefulWidget {
  final List<EditorDocumentDescriptor> documents;
  final EditorDocumentId? activeId;
  final Map<EditorDocumentId, ui.Image> previews;
  final ValueChanged<EditorDocumentId> onFocus;
  final Future<void> Function(EditorDocumentId) onClose;
  final Future<void> Function()? onCloseAll;

  const EditorTabsOverview({
    super.key,
    required this.documents,
    required this.activeId,
    required this.previews,
    required this.onFocus,
    required this.onClose,
    this.onCloseAll,
  });

  @override
  State<EditorTabsOverview> createState() => _EditorTabsOverviewState();
}

class _EditorTabsOverviewState extends State<EditorTabsOverview> {
  String _query = '';

  /// Вкладки, закрытые прямо из обзора: шелл под виджетом уже обновился,
  /// но сюда прилетел снепшот списка — прячем их локально.
  final Set<EditorDocumentId> _dismissed = {};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = _query.trim().toLowerCase();
    final documents = widget.documents.where((document) {
      if (_dismissed.contains(document.id)) return false;
      if (normalized.isEmpty) return true;
      return document.title.toLowerCase().contains(normalized) ||
          (document.displaySubtitle?.toLowerCase().contains(normalized) ??
              false) ||
          document.id.kind.label.toLowerCase().contains(normalized);
    }).toList();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(tr('Вкладки')),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '${widget.documents.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (widget.onCloseAll != null)
            IconButton(
              tooltip: tr('Закрыть все вкладки'),
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('Закрыть все вкладки?')),
                    content: Text(trf('Будет закрыто {p0} вкладок', {'p0': widget.documents.length})),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отмена'))),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Закрыть все'))),
                    ],
                  ),
                );
                if (confirm != true) return;
                await widget.onCloseAll!.call();
                if (!context.mounted) return;
                setState(() => _dismissed.addAll(widget.documents.map((d) => d.id)));
                Navigator.of(context).pop();
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: tr('Найти вкладку'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: documents.isEmpty
                ? Center(
                    child: Text(
                      tr('Вкладки не найдены'),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      // Гарантируем минимум 2 колонки, до 4 на широких экранах.
                      final crossAxisCount = w < 520 ? 2 : w < 860 ? 3 : 4;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 1.12,
                        ),
                    itemCount: documents.length,
                    itemBuilder: (context, index) {
                      final document = documents[index];
                      return _OverviewCard(
                        document: document,
                        active: document.id == widget.activeId,
                        preview: widget.previews[document.id],
                        onFocus: () {
                          widget.onFocus(document.id);
                          Navigator.of(context).pop();
                        },
                        onClose: () async {
                          await widget.onClose(document.id);
                          if (!context.mounted) return;
                          setState(() => _dismissed.add(document.id));
                          // Все вкладки закрыты из обзора — шелл под ним уже
                          // вышел (_exitWhenEmpty), обзору тут делать нечего.
                          if (_dismissed.length >= widget.documents.length) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    },
                  );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final EditorDocumentDescriptor document;
  final bool active;
  final ui.Image? preview;
  final VoidCallback onFocus;
  final VoidCallback onClose;

  const _OverviewCard({
    required this.document,
    required this.active,
    required this.preview,
    required this.onFocus,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onFocus,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  preview != null
                      ? RawImage(
                          image: preview,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        )
                      : ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Center(
                            child: Icon(
                              document.icon,
                              size: 46,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filledTonal(
                      onPressed: onClose,
                      tooltip: tr('Закрыть вкладку'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                  if (active)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tr('Активна'),
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          document.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (document.isDirty)
                        Icon(Icons.circle, size: 8, color: scheme.tertiary),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    document.id.kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
