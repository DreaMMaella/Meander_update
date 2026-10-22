import 'package:canvas_app/core/services/quest_pdf_options.dart';
import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

/// Bottom-sheet с настройками PDF перед экспортом.
/// Возвращает [PdfExportOptions] при подтверждении или `null` при отмене.
Future<PdfExportOptions?> showPdfExportOptionsSheet(
  BuildContext context, {
  PdfExportOptions initial = const PdfExportOptions(),
}) {
  return showAdaptiveSheet<PdfExportOptions>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => _PdfOptionsSheet(initial: initial),
  );
}

class _PdfOptionsSheet extends StatefulWidget {
  final PdfExportOptions initial;
  const _PdfOptionsSheet({required this.initial});

  @override
  State<_PdfOptionsSheet> createState() => _PdfOptionsSheetState();
}

class _PdfOptionsSheetState extends State<_PdfOptionsSheet> {
  late PdfExportOptions _opts;

  @override
  void initState() {
    super.initState();
    _opts = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.picture_as_pdf_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  tr('Настройки PDF'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr('Настройте оформление перед экспортом'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),

            // === Тема ===
            const SizedBox(height: 20),
            _SectionLabel(label: tr('Тема'), icon: Icons.palette_outlined),
            const SizedBox(height: 10),
            _ThemeGrid(
              selected: _opts.theme,
              onChange: (t) => setState(() => _opts = _opts.copyWith(theme: t)),
            ),

            // === Размер шрифта ===
            const SizedBox(height: 22),
            _SectionLabel(
              label: tr('Размер шрифта'),
              icon: Icons.format_size_rounded,
            ),
            const SizedBox(height: 10),
            _TextSizeSelector(
              selected: _opts.textSize,
              onChange: (s) =>
                  setState(() => _opts = _opts.copyWith(textSize: s)),
            ),

            // === Тоглы ===
            const SizedBox(height: 18),
            _SectionLabel(label: tr('Содержимое'), icon: Icons.tune_rounded),
            const SizedBox(height: 4),
            _OptionTile(
              icon: Icons.image_outlined,
              title: tr('Включать картинки'),
              subtitle: tr('Если выключить — экспорт будет меньше'),
              value: _opts.includeImages,
              onChanged: (v) =>
                  setState(() => _opts = _opts.copyWith(includeImages: v)),
            ),
            _OptionTile(
              icon: Icons.auto_stories_outlined,
              title: tr('Титульная страница'),
              subtitle: tr('Обложка с описанием в начале'),
              value: _opts.includeCover,
              onChanged: (v) =>
                  setState(() => _opts = _opts.copyWith(includeCover: v)),
            ),
            _OptionTile(
              icon: Icons.format_align_justify_rounded,
              title: tr('Выравнивать по ширине'),
              subtitle: tr('Текст с ровным правым краем'),
              value: _opts.justifyText,
              onChanged: (v) =>
                  setState(() => _opts = _opts.copyWith(justifyText: v)),
            ),
            _OptionTile(
              icon: Icons.link_rounded,
              title: tr('Кнопки выбора как ссылки'),
              subtitle: tr('Кликабельные переходы между нодами'),
              value: _opts.linkChoices,
              onChanged: (v) =>
                  setState(() => _opts = _opts.copyWith(linkChoices: v)),
            ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(tr('Отмена')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _opts),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: Text(
                      tr('Экспортировать PDF'),
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
            fontSize: 13.5,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _ThemeGrid extends StatelessWidget {
  final PdfTheme selected;
  final ValueChanged<PdfTheme> onChange;
  const _ThemeGrid({required this.selected, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: PdfTheme.values
          .map(
            (t) => _ThemeCard(
              theme: t,
              selected: t == selected,
              onTap: () => onChange(t),
            ),
          )
          .toList(),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final PdfTheme theme;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = theme.colors;
    // Pdf-цвета: нужно конвертировать.
    final bg = Color.fromARGB(
      (c.background.alpha * 255).round(),
      (c.background.red * 255).round(),
      (c.background.green * 255).round(),
      (c.background.blue * 255).round(),
    );
    final ink = Color.fromARGB(
      (c.ink.alpha * 255).round(),
      (c.ink.red * 255).round(),
      (c.ink.green * 255).round(),
      (c.ink.blue * 255).round(),
    );
    final accent = Color.fromARGB(
      (c.accent.alpha * 255).round(),
      (c.accent.red * 255).round(),
      (c.accent.green * 255).round(),
      (c.accent.blue * 255).round(),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: (MediaQuery.of(context).size.width - 50) / 2,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Превью страницы темы
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ink.withOpacity(0.08), width: 0.5),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 4, width: 38, color: ink),
                    const SizedBox(height: 4),
                    Container(height: 2, width: 18, color: accent),
                    const SizedBox(height: 6),
                    Container(
                      height: 2,
                      width: double.infinity,
                      color: ink.withOpacity(0.55),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 2,
                      width: 80,
                      color: ink.withOpacity(0.55),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 2,
                      width: 60,
                      color: ink.withOpacity(0.55),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      theme.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: scheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                theme.description,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextSizeSelector extends StatelessWidget {
  final PdfTextSize selected;
  final ValueChanged<PdfTextSize> onChange;
  const _TextSizeSelector({required this.selected, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<PdfTextSize>(
        segments: PdfTextSize.values
            .map(
              (s) => ButtonSegment<PdfTextSize>(
                value: s,
                label: Text(s.label, style: const TextStyle(fontSize: 12)),
              ),
            )
            .toList(),
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChange(s.first),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      secondary: Icon(icon, color: scheme.onSurfaceVariant),
    );
  }
}
