import 'dart:math' as math;

import 'package:canvas_app/core/services/quest_cleaner_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

class QuestCleanerScreen extends StatefulWidget {
  final String questId;
  final String questTitle;

  const QuestCleanerScreen({
    super.key,
    required this.questId,
    required this.questTitle,
  });

  @override
  State<QuestCleanerScreen> createState() => _QuestCleanerScreenState();
}

class _QuestCleanerScreenState extends State<QuestCleanerScreen> {
  final QuestCleanerService _service = QuestCleanerService();

  bool _isLoading = true;
  bool _isApplying = false;
  bool _createBackup = true;
  String? _error;
  double _scanProgress = 0.0;
  String _scanStage = tr('Подготовка');
  double _applyProgress = 0.0;
  String _applyStage = tr('Подготовка');

  QuestCleanerReport? _report;
  final Map<String, bool> _selectedByIssue = <String, bool>{};
  final Set<String> _expandedCategories = <String>{};

  static const _categoryPalette = <Color>[
    Color(0xFFCDB4DB),
    Color(0xFFBDE0FE),
    Color(0xFFA2D2FF),
    Color(0xFFFFC8DD),
    Color(0xFFD9D9F3),
    Color(0xFFB8C0FF),
  ];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _scanProgress = 0.0;
      _scanStage = tr('Подготовка');
    });

    try {
      final report = await _service.scanQuest(
        widget.questId,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _scanProgress = progress.progress;
            _scanStage = progress.stage;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _selectedByIssue
          ..clear()
          ..addEntries(
            report.issues.map(
              (issue) => MapEntry(issue.id, issue.type != 'noop'),
            ),
          );
        _expandedCategories
          ..clear()
          ..addAll(report.grouped().keys.take(2));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _selectedCount =>
      _selectedByIssue.entries.where((entry) => entry.value).length;

  Future<void> _apply() async {
    final report = _report;
    if (report == null || _isApplying) return;

    final selected = report.issues
        .where((i) => _selectedByIssue[i.id] == true)
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Ничего не выбрано'))));
      return;
    }

    setState(() => _isApplying = true);
    try {
      setState(() {
        _applyProgress = 0.0;
        _applyStage = tr('Подготовка');
      });
      final result = await _service.applyIssues(
        widget.questId,
        selected,
        createBackup: _createBackup,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _applyProgress = progress.progress;
            _applyStage = progress.stage;
          });
        },
      );
      if (!mounted) return;

      final hasErrors = result.failed > 0 || result.errors.isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            trf('Очистка завершена: применено {p0}, ошибок {p1}', {'p0': result.applied, 'p1': result.failed}),
          ),
          backgroundColor: hasErrors ? Colors.orange : const Color(0xFF00C853),
        ),
      );

      if (result.errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errors.take(3).join('\n')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }

      await _scan();
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  bool _isCategoryChecked(String category, List<QuestCleanerIssue> issues) {
    final actionable = issues.where((i) => i.type != 'noop').toList();
    if (actionable.isEmpty) return false;
    return actionable.every((i) => _selectedByIssue[i.id] == true);
  }

  void _toggleCategory(
    String category,
    List<QuestCleanerIssue> issues,
    bool v,
  ) {
    for (final issue in issues) {
      if (issue.type == 'noop') continue;
      _selectedByIssue[issue.id] = v;
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D12),
        elevation: 0,
        title: Text(
          tr('Клинер квеста'),
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _isLoading || _isApplying ? null : _scan,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF00C853)),
                    const SizedBox(height: 16),
                    Text(
                      _scanStage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _scanProgress > 0 ? _scanProgress : null,
                      color: const Color(0xFF00C853),
                      backgroundColor: Colors.white12,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(_scanProgress * 100).round()}%',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            )
          : _error != null
          ? Center(
              child: Text(
                trf('Ошибка: {_error}', {'_error': _error}),
                style: const TextStyle(color: Colors.redAccent),
              ),
            )
          : report == null || report.issues.isEmpty
          ? Center(
              child: Text(
                tr('Проблем не найдено'),
                style: GoogleFonts.manrope(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : AdaptiveContent(maxWidth: 900, child: _buildBody(report)),
      bottomNavigationBar: report == null || report.issues.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isApplying ? null : _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA2B7ED),
                    foregroundColor: const Color(0xFF233767),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isApplying
                      ? Text(
                          '${(_applyProgress * 100).round()}% · $_applyStage',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        )
                      : Text(
                          trf('Очистить выбранное ({_selectedCount})', {'_selectedCount': _selectedCount}),
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(QuestCleanerReport report) {
    final grouped = report.grouped();
    final entries = grouped.entries.toList();

    final categoryStats = <_CategoryStat>[];
    for (int i = 0; i < entries.length; i++) {
      final category = entries[i].key;
      final issues = entries[i].value;
      final total = issues.length;
      final selected = issues
          .where((i) => _selectedByIssue[i.id] == true)
          .length;
      categoryStats.add(
        _CategoryStat(
          category: category,
          total: total,
          selected: selected,
          color: _categoryPalette[i % _categoryPalette.length],
        ),
      );
    }

    final totalIssues = report.issues.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Material(
          color: const Color(0xFF13131A),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(220, 220),
                        painter: _RingChartPainter(
                          stats: categoryStats,
                          total: totalIssues,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${report.issues.length}',
                            style: GoogleFonts.manrope(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 52,
                            ),
                          ),
                          Text(
                            tr('проблем'),
                            style: GoogleFonts.manrope(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  widget.questTitle,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  trf('Выбрано к очистке: {_selectedCount}', {'_selectedCount': _selectedCount}),
                  style: GoogleFonts.manrope(
                    color: const Color(0xFFA2B7ED),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 300,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _createBackup,
                    onChanged: _isApplying
                        ? null
                        : (v) => setState(() => _createBackup = v ?? true),
                    title: Text(
                      tr('Создать авто-бэкап перед очисткой'),
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    activeColor: const Color(0xFFBBD0FF),
                    checkColor: const Color(0xFF233767),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...entries.asMap().entries.map((entry) {
          final categoryIndex = entry.key;
          final category = entry.value.key;
          final issues = entry.value.value;
          final color =
              _categoryPalette[categoryIndex % _categoryPalette.length];
          final expanded = _expandedCategories.contains(category);
          final selected = issues
              .where((i) => _selectedByIssue[i.id] == true)
              .length;

          return Material(
            color: const Color(0xFF13131A),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        if (expanded) {
                          _expandedCategories.remove(category);
                        } else {
                          _expandedCategories.add(category);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _isCategoryChecked(category, issues),
                            onChanged: _isApplying
                                ? null
                                : (v) => setState(() {
                                    _toggleCategory(
                                      category,
                                      issues,
                                      v ?? false,
                                    );
                                  }),
                            activeColor: color,
                            checkColor: const Color(0xFF233767),
                          ),
                          Expanded(
                            child: Text(
                              '$category · $selected/${issues.length}',
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          Text(
                            '${((issues.length / report.issues.length) * 100).round()}%',
                            style: GoogleFonts.manrope(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (expanded)
                    ...issues.map(
                      (issue) => Material(
                        color: const Color(0xFF1B1B23),
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                          child: CheckboxListTile(
                            value: _selectedByIssue[issue.id] ?? false,
                            onChanged: (issue.type == 'noop' || _isApplying)
                                ? null
                                : (v) => setState(
                                    () =>
                                        _selectedByIssue[issue.id] = v ?? false,
                                  ),
                            activeColor: color,
                            checkColor: const Color(0xFF233767),
                            title: Text(
                              issue.title,
                              style: GoogleFonts.manrope(
                                color: issue.type == 'noop'
                                    ? Colors.white54
                                    : Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              issue.description,
                              style: GoogleFonts.manrope(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _CategoryStat {
  final String category;
  final int total;
  final int selected;
  final Color color;

  const _CategoryStat({
    required this.category,
    required this.total,
    required this.selected,
    required this.color,
  });
}

class _RingChartPainter extends CustomPainter {
  final List<_CategoryStat> stats;
  final int total;

  _RingChartPainter({required this.stats, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || stats.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final stroke = radius * 0.38;

    final bg = Paint()
      ..color = const Color(0xFF1A1A22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    canvas.drawCircle(center, radius - stroke / 2, bg);

    double start = -math.pi / 2;
    for (final stat in stats) {
      final sweep = (stat.total / total) * (math.pi * 2);
      final paint = Paint()
        ..color = stat.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - stroke / 2),
        start,
        sweep,
        false,
        paint,
      );

      start += sweep + 0.03;
    }
  }

  @override
  bool shouldRepaint(covariant _RingChartPainter oldDelegate) {
    return oldDelegate.stats != stats || oldDelegate.total != total;
  }
}
