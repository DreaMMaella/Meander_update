import 'package:flutter/material.dart';

import '../../models/canvas_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';

/// Предустановленные цвета для нод.
///
/// ВАЖНО: ноды на канвасе рисуются М3-тонально: их цвет (node.color)
/// прогоняется через [CanvasTheme.tonalContainerFor] (ColorScheme.fromSeed),
/// что даёт ГАРМОНИЧНЫЙ, но РАЗНООБРАЗНЫЙ tonal-контейнер, адаптивный к теме.
/// Пикер показывает ровно те же тональные превью, что и сама нода.
class NodeColors {
  NodeColors._();

  /// Палитра seed-цветов (нейтральный + различимые hue). Это «опорные»
  /// цвета: визуально нода красится их тональным контейнером, поэтому
  /// они выглядят согласованно с темой, но при этом отличимы друг от друга.
  static List<NodeColorOption> get palette => [
    NodeColorOption(Color(0xFF232323), tr('Нейтральный')),
    NodeColorOption(Color(0xFF1976D2), tr('Синий')),
    NodeColorOption(Color(0xFF0097A7), tr('Бирюзовый')),
    NodeColorOption(Color(0xFF388E3C), tr('Зелёный')),
    NodeColorOption(Color(0xFFF9A825), tr('Янтарный')),
    NodeColorOption(Color(0xFFF57C00), tr('Оранжевый')),
    NodeColorOption(Color(0xFFD32F2F), tr('Красный')),
    NodeColorOption(Color(0xFFC2185B), tr('Розовый')),
    NodeColorOption(Color(0xFF7B1FA2), tr('Фиолетовый')),
    NodeColorOption(Color(0xFF455A64), tr('Грифельный')),
  ];
}

class NodeColorOption {
  final Color seed;
  final String name;
  const NodeColorOption(this.seed, this.name);
}

/// Возвращает тональное превью контейнера и контрастный «on»-цвет для seed.
/// Для нейтральных цветов используется surface-роль темы.
({Color container, Color onContainer}) _previewFor(Color seed) {
  final hsl = HSLColor.fromColor(seed);
  final isNeutral = hsl.saturation < 0.15 || hsl.lightness < 0.18;
  if (isNeutral) {
    return (
      container: CanvasTheme.containerForRole(NodeColorRole.surface),
      onContainer: CanvasTheme.onContainerForRole(NodeColorRole.surface),
    );
  }
  return (
    container: CanvasTheme.tonalContainerFor(seed),
    onContainer: CanvasTheme.onTonalContainerFor(seed),
  );
}

/// Виджет палитры цветов нод (M3 tonal).
class ColorPalettePicker extends StatelessWidget {
  final ValueChanged<Color> onColorSelected;
  final Color? currentColor;

  const ColorPalettePicker({
    super.key,
    required this.onColorSelected,
    this.currentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Гарантируем, что токены CanvasTheme соответствуют активной схеме.
    CanvasTheme.update(scheme);

    return Container(
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Цвет ноды'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: NodeColors.palette.length,
            itemBuilder: (context, index) {
              final option = NodeColors.palette[index];
              final preview = _previewFor(option.seed);
              final isSelected =
                  currentColor != null &&
                  currentColor!.value == option.seed.value;
              return _ColorSwatch(
                container: preview.container,
                onContainer: preview.onContainer,
                isSelected: isSelected,
                name: option.name,
                outline: scheme.outlineVariant,
                selectionColor: scheme.primary,
                onTap: () => onColorSelected(option.seed),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            tr('Выберите цвет для выбранных нод'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color container;
  final Color onContainer;
  final Color outline;
  final Color selectionColor;
  final bool isSelected;
  final VoidCallback onTap;
  final String name;

  const _ColorSwatch({
    required this.container,
    required this.onContainer,
    required this.outline,
    required this.selectionColor,
    required this.isSelected,
    required this.onTap,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: container,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? selectionColor : outline,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: isSelected
                ? Icon(Icons.check_rounded, color: onContainer, size: 20)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Диалог выбора цвета.
Future<Color?> showColorPickerDialog({
  required BuildContext context,
  Color? initialColor,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showAppDialog<Color>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ColorPalettePicker(
        currentColor: initialColor,
        onColorSelected: (color) => Navigator.pop(context, color),
      ),
    ),
  );
}
