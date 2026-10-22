import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/content_item_picker_model.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/content_item_selection_screen.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/script_block_shell.dart';
import 'package:flutter/material.dart';

// ============================================================================
//  SET VISIBLE BLOCK — спрятать или показать элемент контента
// ============================================================================

/// «Не видно» — два разных поведения, и автору нужно и то, и другое:
/// «скрыть» оставляет айтему его место (ряд не схлопывается, соседи не
/// уезжают), «убрать» выводит айтем из раскладки.
///
/// Движок пишет переопределение в служебную переменную, клиент подхватывает
/// его при сборке айтема — модель квеста при этом не меняется.
///
/// Выбор типа намеренно не ограничен картинкой: прятать нужно текст, кнопки и
/// целые ряды, а особенно слои внутри стека — до них триггеры видимости не
/// доходят, и без императивного блока сцена была бы глуха.
class SetVisibleBlockWidget extends StatefulWidget {
  final SetVisibleBlock block;
  final String questId;
  final ValueChanged<ScriptBlockMenuAction>? onMenuAction;
  final VoidCallback? onDelete;

  const SetVisibleBlockWidget({
    super.key,
    required this.block,
    required this.questId,
    this.onMenuAction,
    this.onDelete,
  });

  @override
  State<SetVisibleBlockWidget> createState() => _SetVisibleBlockWidgetState();
}

class _SetVisibleBlockWidgetState extends State<SetVisibleBlockWidget> {
  /// «Скрыть» и «убрать» — про разную раскладку, поэтому идут рядом: автор
  /// выбирает поведение, а не угадывает его по названию.
  ///
  /// Сегменты без иконок: четыре подписи с иконкой не влезают даже в 360dp, и
  /// режутся именно «Показать» с «Переключить» — те слова, между которыми и
  /// нужно выбирать. Иконка остаётся одна, в подписи поля и в заголовке.
  ///
  /// Геттер, а не `static final`: список строится под текущий язык, иначе
  /// смена языка оставляла бы старые подписи до перезапуска.
  static List<({String value, String label, IconData? icon})> get _modes => [
    (value: 'hide', label: tr('Скрыть'), icon: null),
    (value: 'remove', label: tr('Убрать'), icon: null),
    (value: 'show', label: tr('Показать'), icon: null),
    (value: 'toggle', label: tr('Переключить'), icon: null),
  ];

  IconData get _modeIcon => switch (widget.block.mode) {
    'show' => Icons.visibility_rounded,
    'remove' => Icons.remove_rounded,
    'toggle' => Icons.swap_horiz_rounded,
    _ => Icons.visibility_off_rounded,
  };

  Future<void> _selectItem() async {
    final result = await Navigator.push<ContentItemChoice>(
      context,
      MaterialPageRoute(
        builder: (context) => ContentItemSelectionScreen(
          questId: widget.questId,
          selectedItemId: widget.block.itemId,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        widget.block.itemId = result.item.id;
        widget.block.itemName = _labelOf(result);
      });
    }
  }

  /// Подпись в блоке: имя из библиотеки и где лежит айтем. `itemId` — ссылка,
  /// по которой блок работает; имя нужно автору, чтобы через неделю понять,
  /// какой именно из сорока слоёв он имел в виду.
  static String _labelOf(ContentItemChoice choice) {
    final location = choice.location;
    if (location.isEmpty || location == choice.label) return choice.label;
    return '${choice.label} · $location';
  }

  @override
  Widget build(BuildContext context) {
    return ScriptBlockShell(
      category: BlockCategory.action,
      title: tr('Скрыть / убрать'),
      icon: _modeIcon,
      onDelete: widget.onDelete,
      onMenuAction: widget.onMenuAction,
      child: ScriptFieldsGroup(
        children: [
          ScriptFieldTile(
            label: tr('объект'),
            icon: Icons.layers_rounded,
            value: widget.block.itemId == null ? '' : widget.block.itemName,
            placeholder: tr('выберите элемент контента'),
            onTap: _selectItem,
          ),
          ScriptFieldSegmented<String>(
            label: tr('Действие'),
            icon: _modeIcon,
            value: widget.block.mode,
            options: _modes,
            onChanged: (v) => setState(() => widget.block.mode = v),
          ),
        ],
      ),
    );
  }
}
