/// Панель «Проверка квеста»: полный статический анализ квеста через
/// Rust-валидатор (`mnd_core::validation`, FFI `run_quest_validation`).
///
/// Показывает статистику (ноды/скрипты/айтемы, warnings/errors) и список
/// диагностик: битые ссылки, дубли id, недостижимые ноды, мёртвые переменные,
/// конфликты видимости onAppear-условий. Тап по диагностике с нодой —
/// переход к ней на холсте.
library;

import 'package:flutter/material.dart';
import 'package:mnd_core/engine/quest_validator.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

/// Показать панель валидации квеста (bottom sheet).
Future<void> showQuestValidationPanel(
  BuildContext context, {
  required String questId,
  required void Function(String nodeId) onJumpToNode,
}) {
  return showAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _QuestValidationPanel(
      questId: questId,
      onJumpToNode: onJumpToNode,
    ),
  );
}

/// Подписи типов диагностик. Геттер, а не const-таблица: значения строятся
/// под текущий язык. Ключи (`missing_config` и т. п.) — данные, их не трогаем.
Map<String, String> get _kindLabels => {
  'missing_config': tr('config.json не найден'),
  'broken_node_link': tr('Битая ссылка на ноду'),
  'broken_script_link': tr('Битая ссылка на скрипт'),
  'broken_resource_link': tr('Битая ссылка на ресурс'),
  'duplicate_node_id': tr('Дубликат id ноды'),
  'duplicate_template_id': tr('Дубликат id шаблона'),
  'duplicate_item_id': tr('Дубликат id айтема'),
  'unreachable_node': tr('Недостижимая нода'),
  'unwritten_variable': tr('Мёртвая переменная'),
  'unread_variable': tr('Переменная без инициализации'),
  'visibility_conflict': tr('Конфликт видимости'),
  'empty_script': tr('Пустой скрипт'),
  'bad_expression': tr('Некорректное выражение'),
};

class _QuestValidationPanel extends StatefulWidget {
  final String questId;
  final void Function(String nodeId) onJumpToNode;

  const _QuestValidationPanel({
    required this.questId,
    required this.onJumpToNode,
  });

  @override
  State<_QuestValidationPanel> createState() => _QuestValidationPanelState();
}

class _QuestValidationPanelState extends State<_QuestValidationPanel> {
  bool _loading = true;
  String? _error;
  QuestValidationReport? _report;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appDir = await FileStorage.getAppDirectory();
      final report = await validateQuest(
        questId: widget.questId,
        questRoot: appDir.path,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = trf('Не удалось выполнить проверку: {p0}', {'p0': friendlyError(e)});
        _loading = false;
      });
    }
  }

  void _jump(String? nodeId) {
    if (nodeId == null || nodeId.isEmpty) return;
    Navigator.of(context).pop();
    widget.onJumpToNode(nodeId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final report = _report;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Icon(Icons.fact_check_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Проверка квеста'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: tr('Запустить заново'),
                  onPressed: _loading ? null : _run,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          if (_loading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(tr('Анализ квеста…')),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              ),
            )
          else if (report != null)
            Expanded(
              child: Column(
                children: [
                  _StatsBar(report: report),
                  const Divider(height: 1),
                  Expanded(child: _DiagnosticsList(report: report, onTap: _jump)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final QuestValidationReport report;

  const _StatsBar({required this.report});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = report.stats;
    final items = <Widget>[
      _StatChip(label: trf('Нод: {p0}', {'p0': stats.nodes}), icon: Icons.account_tree_rounded),
      _StatChip(label: trf('Скриптов: {p0}', {'p0': stats.scripts}), icon: Icons.code_rounded),
      _StatChip(label: trf('Айтемов: {p0}', {'p0': stats.items}), icon: Icons.widgets_rounded),
      _StatChip(
        label: trf('Ошибок: {p0}', {'p0': stats.errors}),
        icon: Icons.error_rounded,
        color: scheme.error,
      ),
      _StatChip(
        label: trf('Предупреждений: {p0}', {'p0': stats.warnings}),
        icon: Icons.warning_amber_rounded,
        color: scheme.tertiary,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: items),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _StatChip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsList extends StatelessWidget {
  final QuestValidationReport report;
  final void Function(String? nodeId) onTap;

  const _DiagnosticsList({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final errors = report.diagnostics
        .where((d) => d.severity == QuestSeverity.error)
        .toList();
    final warnings = report.diagnostics
        .where((d) => d.severity == QuestSeverity.warning)
        .toList();

    if (errors.isEmpty && warnings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(tr('Проблем не найдено')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (errors.isNotEmpty) _SectionHeader(title: trf('Ошибки ({p0})', {'p0': errors.length})),
        ...errors.map((d) => _DiagnosticTile(diagnostic: d, onTap: onTap)),
        if (warnings.isNotEmpty)
          _SectionHeader(title: trf('Предупреждения ({p0})', {'p0': warnings.length})),
        ...warnings.map((d) => _DiagnosticTile(diagnostic: d, onTap: onTap)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  final QuestDiagnostic diagnostic;
  final void Function(String? nodeId) onTap;

  const _DiagnosticTile({required this.diagnostic, required this.onTap});

  String _buildSubtitleText(BuildContext context) {
    // Show message with context: node/item info if available
    final parts = <String>[];
    if (diagnostic.nodeId != null && diagnostic.nodeId!.isNotEmpty) {
      parts.add('нода ${diagnostic.nodeId}');
    }
    if (diagnostic.itemId != null && diagnostic.itemId!.isNotEmpty) {
      parts.add('элемент ${diagnostic.itemId}');
    }
    if (diagnostic.scriptPath != null && diagnostic.scriptPath!.isNotEmpty) {
      parts.add('скрипт: ${diagnostic.scriptPath}');
    }
    final messagePart = diagnostic.message.isNotEmpty
        ? diagnostic.message
        : (parts.isNotEmpty ? parts.join(' → ') : '');
    // Append fix_hint if available
    final hintPart = diagnostic.fixHint != null && diagnostic.fixHint!.isNotEmpty
        ? ' • ${diagnostic.fixHint}'
        : '';
    return '$messagePart$hintPart';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError = diagnostic.severity == QuestSeverity.error;
    final color = isError ? scheme.error : scheme.tertiary;
    final canJump = diagnostic.nodeId != null && diagnostic.nodeId!.isNotEmpty;

    return ListTile(
      onTap: canJump ? () => onTap(diagnostic.nodeId) : null,
      leading: Icon(
        isError ? Icons.error_rounded : Icons.warning_amber_rounded,
        color: color,
      ),
      title: Text(
        _kindLabels[diagnostic.kind] ?? diagnostic.kind,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isError ? scheme.error : null,
        ),
      ),
      subtitle: _buildSubtitleText(context).isNotEmpty
          ? Text(
              _buildSubtitleText(context),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: canJump
          ? Icon(Icons.arrow_forward_ios_rounded, size: 16, color: scheme.outline)
          : null,
    );
  }
}