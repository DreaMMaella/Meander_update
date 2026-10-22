import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter/material.dart';

/// Пресеты якорей: name → (l, t, r, b) — те же девять точек Godot'а, что
/// понимает плеер. Живёт отдельно от канваса, потому что сетку показывают и
/// инспектор слоя, и контекстное меню.
const Map<String, List<double>> kStackAnchorPresets = {
  'topLeft': [0.0, 0.0, 0.0, 0.0],
  'topCenter': [0.5, 0.0, 0.5, 0.0],
  'topRight': [1.0, 0.0, 1.0, 0.0],
  'middleLeft': [0.0, 0.5, 0.0, 0.5],
  'center': [0.5, 0.5, 0.5, 0.5],
  'middleRight': [1.0, 0.5, 1.0, 0.5],
  'bottomLeft': [0.0, 1.0, 0.0, 1.0],
  'bottomCenter': [0.5, 1.0, 0.5, 1.0],
  'bottomRight': [1.0, 1.0, 1.0, 1.0],
  'stretchH': [0.0, 0.5, 1.0, 0.5],
  'stretchV': [0.5, 0.0, 0.5, 1.0],
  'stretch': [0.0, 0.0, 1.0, 1.0],
};

/// Девять точек — сеткой 3×3, три «растянуть» — отдельной строкой.
const List<String> kStackAnchorPresetOrder = [
  'topLeft',
  'topCenter',
  'topRight',
  'middleLeft',
  'center',
  'middleRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
];
const List<String> kStackAnchorStretchPresets = [
  'stretchH',
  'stretchV',
  'stretch',
];

/// Имя пресета, которому в точности соответствуют якоря слоя, или null —
/// якоря собраны вручную (драгом канвас их и оставляет).
String? stackAnchorPresetOf(ContentItem child) {
  for (final entry in kStackAnchorPresets.entries) {
    final a = entry.value;
    if ((child.anchorLeft - a[0]).abs() < 0.001 &&
        (child.anchorTop - a[1]).abs() < 0.001 &&
        (child.anchorRight - a[2]).abs() < 0.001 &&
        (child.anchorBottom - a[3]).abs() < 0.001) {
      return entry.key;
    }
  }
  return null;
}

String stackAnchorPresetLabel(String preset) => switch (preset) {
  'topLeft' => tr('Верх-лево'),
  'topCenter' => tr('Верх-центр'),
  'topRight' => tr('Верх-право'),
  'middleLeft' => tr('Середина-лево'),
  'center' => tr('Центр'),
  'middleRight' => tr('Середина-право'),
  'bottomLeft' => tr('Низ-лево'),
  'bottomCenter' => tr('Низ-центр'),
  'bottomRight' => tr('Низ-право'),
  'stretchH' => tr('Растянуть по ширине'),
  'stretchV' => tr('Растянуть по высоте'),
  'stretch' => tr('Растянуть целиком'),
  _ => preset,
};

/// Сетка якорей: тап по ячейке меняет якоря слоя, не сдвигая его.
class StackAnchorPresetGrid extends StatelessWidget {
  const StackAnchorPresetGrid({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// Имя активного пресета; null — якоря кастомные, ни одна клетка не подсвечена.
  final String? selected;
  final ValueChanged<List<double>> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final name in kStackAnchorPresetOrder)
              _cell(name, kStackAnchorPresets[name]!, scheme),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final name in kStackAnchorStretchPresets)
              _cell(name, kStackAnchorPresets[name]!, scheme, wide: true),
          ],
        ),
      ],
    );
  }

  Widget _cell(
    String name,
    List<double> anchors,
    ColorScheme scheme, {
    bool wide = false,
  }) {
    final isSelected = selected == name;
    return Tooltip(
      message: stackAnchorPresetLabel(name),
      child: InkWell(
        key: ValueKey('anchor_preset_$name'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelected(anchors),
        child: Container(
          width: wide ? 72 : 40,
          height: 34,
          padding: wide ? const EdgeInsets.symmetric(horizontal: 6) : null,
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary.withOpacity(0.25)
                : scheme.surface.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _PresetGlyph(
                  anchors: anchors,
                  color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              if (wide)
                Icon(
                  Icons.open_in_full_rounded,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Мини-глиф пресета: рисует прямоугольник области, который задают якоря.
class _PresetGlyph extends StatelessWidget {
  const _PresetGlyph({required this.anchors, required this.color});

  final List<double> anchors;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 34),
      painter: _PresetGlyphPainter(anchors: anchors, color: color),
    );
  }
}

class _PresetGlyphPainter extends CustomPainter {
  const _PresetGlyphPainter({required this.anchors, required this.color});

  final List<double> anchors;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 5.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withOpacity(0.4);
    // Внешняя рамка области.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, w, h),
        const Radius.circular(3),
      ),
      paint,
    );

    final rect = Rect.fromLTRB(
      pad + anchors[0] * w,
      pad + anchors[1] * h,
      pad + anchors[2] * w,
      pad + anchors[3] * h,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = color.withOpacity(0.25),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PresetGlyphPainter oldDelegate) =>
      oldDelegate.anchors != anchors || oldDelegate.color != color;
}
