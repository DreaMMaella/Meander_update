import 'package:flutter/material.dart';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/theme/theme_engine.dart';

/// Результат ручной правки одного цвета.
class ThemeColorEdit {
  /// Новый цвет, если задан.
  final Color? color;

  /// true — пинование снять, роль снова считается из seed.
  final bool cleared;

  const ThemeColorEdit(this.color) : cleared = false;
  const ThemeColorEdit.clear() : color = null, cleared = true;
}

/// Диалог правки одного цвета темы.
///
/// Три ручки (hue/chroma/tone) вместо «полоски RGB» — потому что тема устроена
/// по тонам: тон и есть то, чем M3 различает `primary`, `primaryContainer` и
/// `onPrimary`. Палитра-полоска снизу — тот же цвет во всех тонах, чтобы
/// «чуть светлее» было одним тапом, а не драгом.
Future<ThemeColorEdit?> showThemeColorEditor(
  BuildContext context, {
  required String title,
  required Color initial,

  /// Фон, по которому этот цвет читается: нужен, чтобы показать контраст
  /// прямо в редакторе, а не после применения.
  Color? contrastAgainst,
  String? hint,
  bool allowClear = false,
}) async {
  final result = await showDialog<ThemeColorEdit>(
    context: context,
    builder: (ctx) => _ThemeColorEditorDialog(
      title: title,
      initial: initial,
      contrastAgainst: contrastAgainst,
      hint: hint,
      allowClear: allowClear,
    ),
  );
  return result;
}

class _ThemeColorEditorDialog extends StatefulWidget {
  final String title;
  final Color initial;
  final Color? contrastAgainst;
  final String? hint;
  final bool allowClear;

  const _ThemeColorEditorDialog({
    required this.title,
    required this.initial,
    this.contrastAgainst,
    this.hint,
    this.allowClear = false,
  });

  @override
  State<_ThemeColorEditorDialog> createState() =>
      _ThemeColorEditorDialogState();
}

class _ThemeColorEditorDialogState extends State<_ThemeColorEditorDialog> {
  late Color _color = widget.initial;
  late final TextEditingController _hex = TextEditingController(
    text: hexOf(widget.initial),
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(Color next) {
    setState(() {
      _color = next;
      _hex.text = hexOf(next);
    });
  }

  void _applyHex() {
    final parsed = parseHexColor(_hex.text);
    if (parsed == null) {
      _set(_color); // вернули как было — поле честное
      return;
    }
    _set(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hct = hctOf(_color);
    final ratio = widget.contrastAgainst == null
        ? null
        : contrast(_color, widget.contrastAgainst!);

    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hex,
                      onSubmitted: (_) => _applyHex(),
                      onChanged: (v) {
                        // Пока ввод выглядит как цвет — применяем сразу,
                        // но поле не перезаписываем: пусть человек допишет.
                        final parsed = parseHexColor(v);
                        if (parsed != null) setState(() => _color = parsed);
                      },
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Hex',
                        helperText: tr('#RRGGBB или #AARRGGBB'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (ratio != null) ...[
                const SizedBox(height: 10),
                _ContrastChip(
                  ratio: ratio,
                  background: widget.contrastAgainst!,
                ),
              ],
              if (widget.hint != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.hint!,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              _HctSlider(
                label: tr('Оттенок'),
                value: hct.hue,
                max: 360,
                unit: '°',
                onChanged: (v) =>
                    _set(hctColor(v, hctOf(_color).chroma, hctOf(_color).tone)),
              ),
              _HctSlider(
                label: tr('Насыщенность'),
                value: hct.chroma,
                max: 100,
                unit: '',
                onChanged: (v) =>
                    _set(hctColor(hctOf(_color).hue, v, hctOf(_color).tone)),
              ),
              _HctSlider(
                label: tr('Светлота (тон)'),
                value: hct.tone,
                max: 100,
                unit: '',
                onChanged: (v) =>
                    _set(hctColor(hctOf(_color).hue, hctOf(_color).chroma, v)),
              ),
              const SizedBox(height: 4),
              Text(
                tr('Тон этого же цвета'),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              _ToneStrip(
                base: _color,
                onSelected: (tone) => _set(toneOf(_color, tone)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.allowClear)
          TextButton.icon(
            onPressed: () =>
                Navigator.pop(context, const ThemeColorEdit.clear()),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: Text(tr('Авто')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Отмена')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ThemeColorEdit(_color)),
          child: Text(tr('Ок')),
        ),
      ],
    );
  }
}

class _ToneStrip extends StatelessWidget {
  final Color base;
  final ValueChanged<double> onSelected;

  const _ToneStrip({required this.base, required this.onSelected});

  static const List<double> _tones = [
    4,
    10,
    20,
    30,
    40,
    50,
    60,
    70,
    80,
    90,
    95,
    99,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentTone = hctOf(base).tone;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tone in _tones)
          Tooltip(
            message: trf('тон {p0}', {'p0': tone.round()}),
            child: InkWell(
              onTap: () => onSelected(tone),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: toneOf(base, tone),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (currentTone - tone).abs() < 2.5
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: (currentTone - tone).abs() < 2.5 ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HctSlider extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  const _HctSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${value.round()}$unit',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0, max),
          max: max,
          onChanged: (v) => onChanged(v),
        ),
      ],
    );
  }
}

class _ContrastChip extends StatelessWidget {
  final double ratio;
  final Color background;

  const _ContrastChip({required this.ratio, required this.background});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = ratio >= kMinContrast;
    final large = ratio >= 3.0;
    final color = ok ? scheme.primary : scheme.error;
    final on = ok ? scheme.onPrimary : scheme.onError;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_rounded
                : (large ? Icons.warning_amber_rounded : Icons.block_rounded),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              trf('Контраст {p0}:1 · {p1}', {'p0': ratio.toStringAsFixed(1), 'p1': ok ? 'AA' : (large ? tr('крупный текст AA14') : tr('нечитаемо'))}),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: on.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }
}
