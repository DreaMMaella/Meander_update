import 'package:flutter/material.dart';
import 'package:mnd_player/widgets/items/game_stack_widget.dart';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/models/content_item_model.dart';

/// Причина, по которой триггер-нажатие объекта внутри стека не дойдёт до
/// движка; null — всё в порядке. Правило взято из `GameStackWidget`: стек со
/// своим действием перехватывает тап, и дети его не получают.
String? stackChildPressWarning({
  required ContentItem stack,
  required ContentItem child,
}) {
  if (!GameStackWidget.suppressesChildInteraction(stack)) return null;
  final deadPress =
      TriggerSlotButtons.hasSlot(child, TriggerSlotButtons.pressSlotOf(child)) ||
      (child.targetNodeId ?? '').trim().isNotEmpty;
  if (!deadPress) return null;
  return tr('Стек перехватывает нажатие: у него самого есть действие, поэтому onPress этого объекта не сработает. Уберите действие у стека — тогда нажатию начнут доставаться дети.');
}

// ============================================================================
//  ИКОНКИ СЛОТОВ ТРИГГЕРОВ
//
//  Глазик onAppear, палец onPress/onSubmit и молния «все триггеры» — один вид
//  для карточки элемента в ноде и для дочерних объектов стека/канваса. Раньше
//  разметка и выбор слота ('onSubmit' у поля ввода) жили отдельно в
//  ContentItemCard, и редактор стека их просто не получал.
// ============================================================================

/// Узел, который рисует слоты триггеров одного элемента.
class TriggerSlotButtons extends StatelessWidget {
  final ContentItem item;

  /// Тап по конкретному слоту ('onAppear', 'onPress', 'onSubmit'): занятый
  /// слот открывает скрипт, пустой — меню источника.
  final ValueChanged<String>? onSlotTap;

  /// Тап по молнии — полное окно всех слотов.
  final VoidCallback? onSettings;

  /// Компактный вариант — для тесных строк (список детей стека, канвас).
  final bool compact;

  /// Если задан — слоты технически есть, но в рантайме не сработают: рисуем
  /// предупреждающий значок с этим текстом в подсказке.
  final String? warningTooltip;

  const TriggerSlotButtons({
    super.key,
    required this.item,
    this.onSlotTap,
    this.onSettings,
    this.compact = false,
    this.warningTooltip,
  });

  /// Слот «нажатие» у поля ввода называется onSubmit — как в плеере.
  static String pressSlotOf(ContentItem item) =>
      item.type == 'input' ? 'onSubmit' : 'onPress';

  /// Занятые слоты в том виде, в каком их читает плеер: `behaviours` нового
  /// формата и legacy `scriptTriggers` через одну точку модели.
  static Map<String, String> triggersOf(ContentItem item) =>
      item.resolvedTriggers;

  static bool hasSlot(ContentItem item, String slot) =>
      (triggersOf(item)[slot] ?? '').trim().isNotEmpty;

  static bool hasAny(ContentItem item) =>
      triggersOf(item).values.any((path) => path.trim().isNotEmpty);

  /// Скрипты не цепляются к самому элементу-скрипту — там триггера быть не
  /// может в принципе.
  static bool supportsTriggers(ContentItem item) => item.type != 'script';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = supportsTriggers(item);
    final pressSlot = pressSlotOf(item);
    final isSubmit = pressSlot == 'onSubmit';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          icon: Icons.visibility_outlined,
          color: hasSlot(item, 'onAppear')
              ? const Color(0xFFFFD54F)
              : scheme.onSurfaceVariant,
          tooltip: tr('Триггер onAppear'),
          onTap: enabled && onSlotTap != null
              ? () => onSlotTap!('onAppear')
              : null,
        ),
        _button(
          icon: isSubmit ? Icons.input_rounded : Icons.touch_app_outlined,
          color: hasSlot(item, pressSlot)
              ? const Color(0xFFE040FB)
              : scheme.onSurfaceVariant,
          tooltip: isSubmit
              ? tr('Скрипт при вводе (onSubmit)')
              : tr('Скрипт по нажатию (onPress)'),
          onTap: enabled && onSlotTap != null
              ? () => onSlotTap!(pressSlot)
              : null,
        ),
        if (onSettings != null)
          _button(
            icon: Icons.bolt,
            color: hasAny(item) ? Colors.amber : scheme.onSurfaceVariant,
            tooltip: tr('Все триггеры элемента'),
            onTap: enabled ? onSettings : null,
          ),
        if (warningTooltip != null)
          Tooltip(
            message: warningTooltip!,
            child: Icon(
              Icons.warning_amber_rounded,
              size: compact ? 16 : 18,
              color: Colors.orangeAccent,
            ),
          ),
      ],
    );
  }

  Widget _button({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final size = compact ? 18.0 : 20.0;
    final side = compact ? 26.0 : 30.0;
    return IconButton(
      icon: Icon(icon, size: size, color: color),
      onPressed: onTap,
      tooltip: tooltip,
      constraints: BoxConstraints(minWidth: side, minHeight: side),
      padding: EdgeInsets.all(compact ? 2 : 3),
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        hoverColor: color.withOpacity(0.1),
      ),
    );
  }
}
