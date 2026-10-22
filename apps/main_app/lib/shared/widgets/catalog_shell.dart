import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

// ============================================================================
//  ОБЩИЕ M3-ВИДЖЕТЫ «КАТАЛОЖНЫХ» ЭКРАНОВ
//
//  Используются и маркетом квестов, и хабом ресурсов, чтобы оба экрана
//  выглядели и вели себя одинаково: левый рельс, поиск в SliverAppBar,
//  заголовки секций, сетка карточек и shimmer-заглушки загрузки.
// ============================================================================

const double kCatalogCompactBreakpoint = 600;
const double kCatalogMediumBreakpoint = 900;
const double kCatalogExpandedBreakpoint = 1240;
const double kCatalogRailWidth = 260;
const double kCatalogAsideWidth = 320;

int catalogCrossAxisCount(double width) {
  if (width >= kCatalogExpandedBreakpoint) return 5;
  if (width >= kCatalogMediumBreakpoint) return 4;
  if (width >= kCatalogCompactBreakpoint) return 3;
  return 2;
}

double catalogCardAspect(double width) {
  if (width >= kCatalogMediumBreakpoint) return 0.72;
  return 0.78;
}

/// Горизонтальные отступы сетки карточек.
double catalogGridPadding(double width) =>
    width >= kCatalogMediumBreakpoint ? 24 : 16;

// ============================================================================
//  ПОИСКОВАЯ СТРОКА
// ============================================================================

class CatalogSearchField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilterTap;
  final String? hintText;

  const CatalogSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onFilterTap,
    this.hintText,
  });

  @override
  State<CatalogSearchField> createState() => _CatalogSearchFieldState();
}

class _CatalogSearchFieldState extends State<CatalogSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = widget.controller.text.isNotEmpty;
    return SizedBox(
      height: 52,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(
              Icons.search_rounded,
              size: 22,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                style: TextStyle(color: scheme.onSurface, fontSize: 15),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hintText ?? tr('Поиск…'),
                  hintStyle: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: widget.onChanged,
              ),
            ),
            if (hasText)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: tr('Очистить'),
                onPressed: widget.onClear,
              )
            else
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: tr('Фильтры'),
                onPressed: widget.onFilterTap,
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  ЛЕВАЯ НАВИГАЦИОННАЯ ПАНЕЛЬ
// ============================================================================

/// Шапка левого рельса: иконка раздела + название.
class CatalogRailHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const CatalogRailHeader({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Подпись группы в левом рельсе («Жанры», «Типы ресурсов»…).
class CatalogRailGroupLabel extends StatelessWidget {
  final String label;

  const CatalogRailGroupLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class CatalogRailTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const CatalogRailTile({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 14,
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

// ============================================================================
//  ЗАГОЛОВКИ СЕКЦИЙ
// ============================================================================

class CatalogSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onSeeAll;

  const CatalogSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.onSeeAll,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: Text(tr('Все'))),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 2),
              child: Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
//  SHIMMER-ЗАГЛУШКИ ЗАГРУЗКИ
// ============================================================================

class CatalogShimmerCard extends StatelessWidget {
  final double? width;
  const CatalogShimmerCard({super.key, this.width});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHigh,
      highlightColor: scheme.surfaceContainerHighest,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

class CatalogGridShimmer extends StatelessWidget {
  final double width;
  const CatalogGridShimmer({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final crossAxisCount = catalogCrossAxisCount(width);
    final aspect = catalogCardAspect(width);

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: catalogGridPadding(width)),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: aspect,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, __) => Shimmer.fromColors(
            baseColor: scheme.surfaceContainerHigh,
            highlightColor: scheme.surfaceContainerHighest,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          childCount: crossAxisCount * 3,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
        ),
      ),
    );
  }
}

/// Сетка карточек с параметрами маркета (используется и хабом).
class CatalogSliverGrid extends StatelessWidget {
  final int itemCount;
  final double width;
  final NullableIndexedWidgetBuilder itemBuilder;
  final double spacing;

  const CatalogSliverGrid({
    super.key,
    required this.itemCount,
    required this.width,
    required this.itemBuilder,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: catalogGridPadding(width)),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: catalogCrossAxisCount(width),
          childAspectRatio: catalogCardAspect(width),
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
        ),
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: itemCount,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
        ),
      ),
    );
  }
}

// ============================================================================
//  ЧИПЫ КАТЕГОРИЙ (компактный режим)
// ============================================================================

class CatalogCategoryChipsRow extends StatelessWidget {
  final List<CatalogChipEntry> entries;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const CatalogCategoryChipsRow({
    super.key,
    required this.entries,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = entries[i];
          final isSelected = selected == e.value;
          return FilterChip(
            label: Text(e.label),
            avatar: Icon(e.icon, size: 18),
            selected: isSelected,
            onSelected: (_) => onSelected(isSelected ? null : e.value),
          );
        },
      ),
    );
  }
}

class CatalogChipEntry {
  final String label;
  final String? value;
  final IconData icon;

  const CatalogChipEntry(this.label, this.value, this.icon);
}

// ============================================================================
//  СТРАНИЦА ДЕТАЛЕЙ — HERO-ШАПКА И ПЛИТКИ
//
//  Общий язык для страниц квеста и пресета: кнопка поверх обложки,
//  подпись секции капсом, чип и плитка характеристики.
// ============================================================================

/// Круглая полупрозрачная кнопка поверх hero-шапки.
class CatalogGlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final bool loading;

  const CatalogGlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: color ?? Colors.white,
                ),
              )
            : Icon(icon, color: color ?? Colors.white),
      ),
    );
  }
}

/// Акцентный чип (жанр, категория, тип).
class CatalogGenreChip extends StatelessWidget {
  final String label;

  const CatalogGenreChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Подпись секции капсом с разрядкой.
class CatalogSectionLabel extends StatelessWidget {
  final String text;

  const CatalogSectionLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
      ),
    );
  }
}

/// Плитка характеристики: значение, подпись и иконка.
class CatalogStatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color container;
  final Color onContainer;
  final Color accent;

  const CatalogStatTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.container,
    required this.onContainer,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: textTheme.titleMedium?.copyWith(
                color: onContainer,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: onContainer.withOpacity(0.78),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
