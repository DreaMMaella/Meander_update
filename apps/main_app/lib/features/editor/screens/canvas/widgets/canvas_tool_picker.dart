import 'dart:ui';

import 'package:flutter/material.dart';

/// Описание одного инструмента в выезжающей панели-пикере.
class CanvasTool {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  /// Активное состояние (toggle-инструменты подсвечиваются акцентом).
  final bool isActive;

  /// Необязательный бейдж (например «3/5» для фильтра стрелок).
  final String? badge;

  /// Кастомный цвет иконки (по умолчанию из темы).
  final Color? color;

  const CanvasTool({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.isActive = false,
    this.badge,
    this.color,
  });
}

/// Группа инструментов с заголовком секции.
class CanvasToolGroup {
  final String title;
  final List<CanvasTool> tools;

  const CanvasToolGroup({required this.title, required this.tools});
}

/// Выезжающая над нижней панелью «капсула» с иконками инструментов.
///
/// Обычный тап по иконке = действие (панель закрывается).
/// Долгое нажатие (long-press) показывает поповер с названием
/// и кратким описанием инструмента — удобный пикер.
class CanvasToolPicker extends StatefulWidget {
  final List<CanvasToolGroup> groups;
  final VoidCallback onDismiss;

  const CanvasToolPicker({
    super.key,
    required this.groups,
    required this.onDismiss,
  });

  @override
  State<CanvasToolPicker> createState() => _CanvasToolPickerState();
}

class _CanvasToolPickerState extends State<CanvasToolPicker> {
  final GlobalKey _capsuleKey = GlobalKey();
  OverlayEntry? _tipEntry;

  @override
  void dispose() {
    _removeTip();
    super.dispose();
  }

  void _removeTip() {
    _tipEntry?.remove();
    _tipEntry = null;
  }

  void _showTip(BuildContext iconCtx, CanvasTool tool) {
    _removeTip();
    final renderBox = iconCtx.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;

    final iconPos = renderBox.localToGlobal(
      renderBox.size.center(Offset.zero),
      ancestor: overlay,
    );
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = overlay.size.width;

    _tipEntry = OverlayEntry(
      builder: (ctx) {
        const tipWidth = 240.0;
        double left = iconPos.dx - tipWidth / 2;
        left = left.clamp(12.0, screenWidth - tipWidth - 12.0);
        final bottom = overlay.size.height - iconPos.dy + 44;

        return Positioned(
          left: left,
          bottom: bottom,
          width: tipWidth,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: 1),
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 8),
                    child: child,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tool.label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tool.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onInverseSurface.withOpacity(0.8),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_tipEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          key: _capsuleKey,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withOpacity(0.92),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var g = 0; g < widget.groups.length; g++) ...[
                if (g > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: scheme.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Text(
                    widget.groups[g].title.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final tool in widget.groups[g].tools)
                      _ToolIcon(
                        tool: tool,
                        onTap: () {
                          _removeTip();
                          widget.onDismiss();
                          tool.onTap();
                        },
                        onLongPressStart: (iconCtx) => _showTip(iconCtx, tool),
                        onLongPressEnd: _removeTip,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  final CanvasTool tool;
  final VoidCallback onTap;
  final void Function(BuildContext iconCtx) onLongPressStart;
  final VoidCallback onLongPressEnd;

  const _ToolIcon({
    required this.tool,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor =
        tool.color ??
        (tool.isActive ? scheme.primary : scheme.onSurfaceVariant);

    return Builder(
      builder: (iconCtx) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => onLongPressStart(iconCtx),
          onLongPressUp: onLongPressEnd,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tool.isActive
                  ? iconColor.withOpacity(0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                Center(child: Icon(tool.icon, color: iconColor, size: 24)),
                if (tool.badge != null)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tool.badge!,
                        style: TextStyle(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
