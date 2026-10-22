import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/expression_editor_screen.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/reorderable_block_list.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/variable_selection_screen.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  WHILE BLOCK — цикл с прогрессивной сложностью (в духе Scratch).
//
//  Дефолт: одно поле «Повторить N раз». Остальные режимы (счётчик,
//  диапазон, условие) — необязательные параметры в «Ещё».
//
//  Все значения редактируются штатными экранами: формулы — через
//  ExpressionEditorScreen («раздел формул»), имя переменной — через
//  VariableSelectionScreen. Никаких самодельных текстовых полей.
//
//  Приоритет исполнения в ядре: expression → диапазон (to) → count.
// ============================================================================

typedef OnBlockDrop =
    void Function(
      VisualScriptBlock droppedBlock,
      List<VisualScriptBlock> targetList,
    );

class WhileBlockWidget extends StatefulWidget {
  final WhileBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;
  final OnBlockDrop onBlockDrop;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const WhileBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
    required this.onBlockDrop,
    this.onDragUpdate,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<WhileBlockWidget> createState() => _WhileBlockWidgetState();
}

class _WhileBlockWidgetState extends State<WhileBlockWidget> {
  bool _showAdvanced = false;

  WhileBlock get block => widget.block;

  bool get _hasCondition => block.hasExpression;

  String get _modeSummary {
    if (_hasCondition) return block.expression;
    if (block.hasRange) {
      final step = block.step.trim();
      final stepPart = (step.isEmpty || step == '1') ? '' : trf(' шаг {p0}', {'p0': step});
      return '${block.from} … ${block.to}$stepPart';
    }
    if (block.hasCount) return trf('{p0} раз', {'p0': block.count});
    return tr('сколько раз?');
  }

  /// Единый путь правки значений-формул: штатный «раздел формул».
  Future<void> _editExpression({
    required String title,
    required String initialValue,
    required ValueChanged<String> onChanged,
  }) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ExpressionEditorScreen(
          initialValue: initialValue,
          questId: widget.questId,
          title: title,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => onChanged(result));
    }
  }

  /// Имя переменной — через общий экран выбора/создания переменных.
  Future<void> _pickVariable({
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => VariableSelectionScreen(
          questId: widget.questId,
          selectedVariable: currentValue,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => onChanged(result));
    }
  }

  /// Числовые формулы (макс. итераций): формулы + защита от мусора.
  Future<void> _editMaxIterations() => _editExpression(
        title: tr('Макс. итераций (защита от бесконечного цикла)'),
        initialValue: block.maxIterations.toString(),
        onChanged: (v) {
          final parsed = int.tryParse(v.trim());
          if (parsed != null && parsed > 0) block.maxIterations = parsed;
        },
      );

  Future<void> _openExpressionEditor() => _editExpression(
        title: tr('Повторять, пока условие истинно'),
        initialValue: block.expression,
        onChanged: (v) => block.expression = v,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nothingConfigured =
        !block.hasCount && !block.hasRange && !_hasCondition;

    return ScriptBlockShell(
      category: BlockCategory.control,
      title: tr('Повторить'),
      icon: Icons.loop_rounded,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      menuScope: blockScope(widget.block).noun,
      collapsible: true,
      collapsed: block.collapsed,
      onToggleCollapse: () {
        setState(() => block.collapsed = !block.collapsed);
      },
      headerSuffix: ShellValueChip(
        value: nothingConfigured ? '' : _modeSummary,
        placeholder: tr('сколько раз?'),
        maxWidth: 160,
        onTap: () => setState(() => _showAdvanced = !_showAdvanced),
      ),
      // ── Тело цикла: плоские карточки под блоком, а не шахта внутри него ──
      body: ReorderableBlockList(
        blocks: block.children,
        questId: widget.questId,
        onBlockDrop: widget.onBlockDrop,
        allowEventBlocks: false,
        emptyPlaceholder: tr('Перетащите действия'),
        onDragUpdate: widget.onDragUpdate,
        onDragStart: widget.onDragStart,
        onDragEnd: widget.onDragEnd,
      ),
      endLabel: tr('Конец цикла'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Простое повторение: единственное обязательное поле ──
            ScriptFieldTile(
              label: tr('Сколько раз'),
              icon: Icons.repeat_rounded,
              value: block.hasCount ? block.count : '',
              placeholder: '3',
              onTap: () => _editExpression(
                title: tr('Сколько раз повторить?'),
                initialValue: block.count,
                onChanged: (v) => block.count = v.trim(),
              ),
            ),

            // ── Необязательные параметры ──
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _showAdvanced
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tr('Ещё параметры'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (_hasCondition || block.hasRange || block.loopVar.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_showAdvanced) ...[
              // Переменная-счётчик
              ScriptFieldTile(
                label: tr('Счётчик {имя}'),
                icon: Icons.tag_rounded,
                value: block.loopVar,
                placeholder: tr('не задан'),
                onTap: () => _pickVariable(
                  currentValue: block.loopVar,
                  onChanged: (v) => block.loopVar = v.trim(),
                ),
              ),
              const SizedBox(height: 6),
              // Диапазон: три независимых значения-формулы.
              ScriptFieldTile(
                label: tr('Диапазон: от'),
                icon: Icons.swap_vert_rounded,
                value: block.hasRange ? block.from : '',
                placeholder: '1',
                onTap: () => _editExpression(
                  title: tr('Диапазон: от'),
                  initialValue: block.from,
                  onChanged: (v) => block.from = v.trim(),
                ),
              ),
              ScriptFieldTile(
                label: tr('до'),
                icon: null,
                value: block.to,
                placeholder: '10',
                onTap: () => _editExpression(
                  title: tr('Диапазон: до'),
                  initialValue: block.to,
                  onChanged: (v) => block.to = v.trim(),
                ),
              ),
              ScriptFieldTile(
                label: tr('шаг'),
                icon: null,
                value: block.step,
                placeholder: '1',
                onTap: () => _editExpression(
                  title: tr('Диапазон: шаг'),
                  initialValue: block.step,
                  onChanged: (v) => block.step = v.trim(),
                ),
              ),
              const SizedBox(height: 6),
              // Экспертное условие
              ScriptFieldTile(
                label: tr('Условие пока'),
                icon: Icons.rule_rounded,
                value: _hasCondition ? block.expression : '',
                placeholder: tr('не задано'),
                onTap: _openExpressionEditor,
              ),
              const SizedBox(height: 6),
              ScriptFieldTile(
                label: tr('Макс. итераций'),
                icon: Icons.shield_outlined,
                value: block.maxIterations.toString(),
                placeholder: '10000',
                onTap: _editMaxIterations,
              ),
              if (_hasCondition) ...[
                const SizedBox(height: 6),
                Text(
                  tr('Задано условие — оно имеет приоритет над числом и диапазоном.'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],

            if (nothingConfigured) ...[
              const SizedBox(height: 8),
              Text(
                tr('Укажите, сколько раз повторить действия'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
