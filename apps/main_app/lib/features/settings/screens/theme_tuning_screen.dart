import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/theme/app_theme.dart';
import 'package:canvas_app/core/theme/theme_engine.dart';
import 'package:canvas_app/core/theme/theme_preset.dart';
import 'package:canvas_app/core/theme/theme_preset_provider.dart';
import 'package:canvas_app/core/theme/theme_registry.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/settings/widgets/theme_color_editor.dart';

/// Ручная настройка темы.
///
/// Здесь собираются те же данные, что понимает JSON формата v2: вариант
/// палитры, hue/chroma/tone seed'а и пины отдельных ролей. Предпросмотр
/// строится тем же [AppTheme.fromPreset], что и настоящее приложение, —
/// «увиденное» и «после сохранения» идентичны.
class ThemeTuningScreen extends ConsumerStatefulWidget {
  const ThemeTuningScreen({super.key, required this.preset});

  final ThemePreset preset;

  @override
  ConsumerState<ThemeTuningScreen> createState() => _ThemeTuningScreenState();
}

class _ThemeTuningScreenState extends ConsumerState<ThemeTuningScreen> {
  late ThemePreset _draft = widget.preset;
  Brightness _brightness = Brightness.light;

  bool get _dirty {
    final original = widget.preset;
    return _draft.variant != original.variant ||
        _draft.hct != original.hct ||
        _draft.seed != original.seed ||
        _draft.deriveContainers != original.deriveContainers ||
        _draft.lightOverrides.length != original.lightOverrides.length ||
        _draft.darkOverrides.length != original.darkOverrides.length;
  }

  void _update(ThemePreset next) => setState(() => _draft = next);

  Future<void> _apply() async {
    final preset = await _makeSaveable(_draft);
    final notifier = ref.read(themePresetProvider.notifier);
    await notifier.addCustom(preset);
    await notifier.setActive(preset.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(trf('Тема «{p0}» применена', {'p0': preset.name}))));
    Navigator.pop(context, preset);
  }

  /// Встроенную тему сохранить как есть нельзя: `ThemeRegistry.byId` ищет
  /// встроенные первым, и копия с тем же id просто не вступила бы в силу.
  Future<ThemePreset> _makeSaveable(ThemePreset draft) async {
    if (!draft.isBuiltIn) return draft.copyWith(isBuiltIn: false);
    final taken = {
      ...ThemeRegistry.builtIn.map((p) => p.id),
      ...ref.read(themePresetProvider).custom.map((p) => p.id),
    };
    final base = '${draft.id}_custom';
    var id = base;
    for (var n = 2; taken.contains(id); n++) {
      id = '${base}_$n';
    }
    return draft.copyWith(
      id: id,
      name: trf('{p0} (моя)', {'p0': draft.name}),
      isBuiltIn: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final editor = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _VariantSection(
          variant: _draft.variant,
          onChanged: (v) => _update(_draft.copyWith(variant: v)),
        ),
        const SizedBox(height: 22),
        _SeedSection(
          preset: _draft,
          onSeedChanged: (color) =>
              _update(_draft.copyWith(seed: color, hct: SeedHct.none)),
          onHctChanged: (hct) => _update(_draft.copyWith(hct: hct)),
        ),
        const SizedBox(height: 22),
        _DerivedSwitch(
          value: _draft.deriveContainers,
          onChanged: (v) => _update(_draft.copyWith(deriveContainers: v)),
        ),
        const SizedBox(height: 22),
        _RolesSection(
          preset: _draft,
          brightness: _brightness,
          onOverride: (key, color) {
            final overrides = Map.of(_draft.overridesFor(_brightness));
            if (color == null) {
              overrides.remove(key);
            } else {
              overrides[key] = color;
            }
            _update(_draft.withOverrides(_brightness, overrides));
          },
        ),
      ],
    );

    final preview = _PreviewPanel(
      preset: _draft,
      brightness: _brightness,
      onBrightnessChanged: (b) => setState(() => _brightness = b),
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(trf('Настройка темы · {p0}', {'p0': _draft.name})),
        actions: [
          IconButton(
            tooltip: tr('JSON темы'),
            icon: const Icon(Icons.data_object_rounded),
            onPressed: () => _showJson(context),
          ),
          IconButton(
            tooltip: tr('Сбросить правки'),
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _dirty
                ? () => setState(() => _draft = widget.preset)
                : null,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(tr('Закрыть')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _dirty ? _apply : null,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _draft.isBuiltIn ? tr('Сохранить как свою') : tr('Применить'),
                ),
              ),
            ),
          ],
        ),
      ),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: editor),
                Container(
                  width: 380,
                  padding: const EdgeInsets.fromLTRB(0, 8, 16, 8),
                  child: preview,
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Узкий экран: превью с фиксированной высотой, иначе
                // Expanded внутри Column не знает, сколько ему дано.
                SizedBox(height: 520, child: preview),
                const SizedBox(height: 20),
                editor,
              ],
            ),
    );
  }

  Future<void> _showJson(BuildContext context) async {
    final raw = const JsonEncoder.withIndent('  ').convert(_draft.toJson());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('JSON темы')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: SelectableText(
              raw,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: raw));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(tr('Скопировать')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Закрыть')),
          ),
        ],
      ),
    );
  }
}

/// Живой кусок интерфейса в настраиваемой теме.
///
/// Специально не «палитра квадратиков», а типовой экран: шапка, карточка,
/// кнопки, чипы, прогресс и текст двух весов. По нему видно и красоту, и то,
/// что где-то текст перестал читаться.
class _PreviewPanel extends StatelessWidget {
  final ThemePreset preset;
  final Brightness brightness;
  final ValueChanged<Brightness> onBrightnessChanged;

  const _PreviewPanel({
    required this.preset,
    required this.brightness,
    required this.onBrightnessChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.fromPreset(preset, brightness);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<Brightness>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: Brightness.light,
                label: Text(tr('Светлая'), style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.light_mode_rounded, size: 16),
              ),
              ButtonSegment(
                value: Brightness.dark,
                label: Text(tr('Тёмная'), style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.dark_mode_rounded, size: 16),
              ),
            ],
            selected: {brightness},
            onSelectionChanged: (s) => onBrightnessChanged(s.first),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Theme(
                data: theme,
                child: Container(
                  color: scheme.surface,
                  padding: const EdgeInsets.all(14),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.palette_rounded,
                            color: scheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tr('Мейандр'),
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.search_rounded,
                            color: scheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.notifications_rounded,
                            color: scheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Карточка слоя'),
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr('Вторичный текст — по нему лучше всего видно, что вы выбрали для onSurfaceVariant.'),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: 0.65,
                                minHeight: 8,
                                backgroundColor: scheme.surfaceContainerHighest,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                Chip(
                                  label: Text(
                                    tr('обычный'),
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                ChoiceChip(
                                  selected: true,
                                  onSelected: (_) {},
                                  label: Text(
                                    tr('выбран'),
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                              color: scheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tr('Контейнер акцента'),
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {},
                              child: Text(
                                tr('Сохранить'),
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {},
                              child: Text(
                                tr('Отмена'),
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {},
                            child: Text(tr('Кнопка')),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.error_outline_rounded,
                            color: scheme.error,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: scheme.tertiary,
                            size: 18,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ColoredBox(
                              color: scheme.secondaryContainer,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Text(
                                  'onSecondaryContainer',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSecondaryContainer,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ColoredBox(
                              color: scheme.tertiaryContainer,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Text(
                                  'onTertiaryContainer',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onTertiaryContainer,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.inverseSurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr('Тост / инверсная поверхность'),
                                style: TextStyle(
                                  color: scheme.onInverseSurface,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: scheme.onInverseSurface,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final tone in const [
                            'surfaceContainerLowest',
                            'surfaceContainerLow',
                            'surfaceContainer',
                            'surfaceContainerHigh',
                            'surfaceContainerHighest',
                          ])
                            Expanded(
                              child: Container(
                                height: 26,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  color: readRole(scheme, tone),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('Слои поверхности 0 → 4'),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Вариант палитры
// ---------------------------------------------------------------------------

class _VariantSection extends StatelessWidget {
  final DynamicSchemeVariant variant;
  final ValueChanged<DynamicSchemeVariant> onChanged;

  const _VariantSection({required this.variant, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headline(text: tr('Вариант палитры')),
        const SizedBox(height: 4),
        Text(
          tr('Как из одного цвета расходятся все тона. «Точная» оставляет ваш цвет как есть, «Графит» игнорирует оттенок вовсе.'),
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in themeVariants)
              Tooltip(
                message: variantHints[v.name] ?? '',
                child: ChoiceChip(
                  key: Key('variant_${v.name}'),
                  label: Text(_variantLabel(v)),
                  selected: v == variant,
                  onSelected: (_) => onChanged(v),
                  showCheckmark: false,
                ),
              ),
          ],
        ),
        if (variantHints[variant.name] != null) ...[
          const SizedBox(height: 8),
          Text(
            variantHints[variant.name]!,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  static String _variantLabel(DynamicSchemeVariant v) => switch (v) {
    DynamicSchemeVariant.fidelity => tr('Точная'),
    DynamicSchemeVariant.vibrant => tr('Яркая'),
    DynamicSchemeVariant.tonalSpot => tr('M3 по умолчанию'),
    DynamicSchemeVariant.expressive => tr('Эмоциональная'),
    DynamicSchemeVariant.content => tr('Контентная'),
    DynamicSchemeVariant.neutral => tr('Почти серая'),
    DynamicSchemeVariant.monochrome => tr('Графит'),
    DynamicSchemeVariant.rainbow => tr('Радуга'),
    DynamicSchemeVariant.fruitSalad => tr('Фруктовая'),
  };
}

// ---------------------------------------------------------------------------
//  Seed и его HCT-ручки
// ---------------------------------------------------------------------------

class _SeedSection extends StatefulWidget {
  final ThemePreset preset;
  final ValueChanged<Color> onSeedChanged;
  final ValueChanged<SeedHct> onHctChanged;

  const _SeedSection({
    required this.preset,
    required this.onSeedChanged,
    required this.onHctChanged,
  });

  @override
  State<_SeedSection> createState() => _SeedSectionState();
}

class _SeedSectionState extends State<_SeedSection> {
  final TextEditingController _hex = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hex.text = hexOf(widget.preset.seed);
  }

  @override
  void didUpdateWidget(covariant _SeedSection old) {
    super.didUpdateWidget(old);
    // Seed мог поменять редактор цвета — поле всегда показывает актуальный.
    if (old.preset.seed != widget.preset.seed) _syncHex();
  }

  void _syncHex() {
    final text = hexOf(widget.preset.seed);
    _hex.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _applyHex(String raw) {
    final parsed = parseHexColor(raw);
    if (parsed == null) {
      _syncHex();
      return;
    }
    widget.onSeedChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = widget.preset.effectiveSeed;
    final hct = hctOf(effective);
    final neutral = hctOf(widget.preset.seed).chroma < 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headline(text: tr('Опорный цвет')),
        const SizedBox(height: 10),
        Row(
          children: [
            InkWell(
              onTap: () async {
                final edit = await showThemeColorEditor(
                  context,
                  title: tr('Опорный цвет'),
                  initial: widget.preset.seed,
                  hint:
                      tr('Это цвет-источник: палитра строится из него, а ручки ниже правят его же.'),
                );
                if (edit?.color != null) widget.onSeedChanged(edit!.color!);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: widget.preset.seed,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _hex,
                onSubmitted: _applyHex,
                onChanged: (v) {
                  final parsed = parseHexColor(v);
                  if (parsed != null) widget.onSeedChanged(parsed);
                },
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: InputDecoration(
                  labelText: 'Hex seed',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.colorize_rounded, size: 16),
                ),
              ),
            ),
          ],
        ),
        if (neutral) ...[
          const SizedBox(height: 10),
          _Notice(
            icon: Icons.science_rounded,
            text:
                tr('У этого цвета оттенка нет — это графит. Из него M3 не может взять «краску», поэтому либо вариант «Графит», либо поднимите насыщенность и светлоту ниже.'),
          ),
        ],
        const SizedBox(height: 8),
        _HctRow(
          label: tr('Оттенок'),
          value: hct.hue,
          max: 360,
          unit: '°',
          enabled:
              widget.preset.hct.hue != null || widget.preset.hct.chroma != null,
          onChanged: (v) =>
              widget.onHctChanged(widget.preset.hct.copyWith(hue: v)),
        ),
        _HctRow(
          label: tr('Насыщенность'),
          value: hct.chroma,
          max: 100,
          unit: '',
          onChanged: (v) =>
              widget.onHctChanged(widget.preset.hct.copyWith(chroma: v)),
        ),
        _HctRow(
          label: tr('Светлота (тон)'),
          value: hct.tone,
          max: 100,
          unit: '',
          onChanged: (v) =>
              widget.onHctChanged(widget.preset.hct.copyWith(tone: v)),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                trf('Итог: {p0}  ·  H{p1} C{p2} T{p3}', {'p0': hexOf(effective), 'p1': hct.hue.round(), 'p2': hct.chroma.round(), 'p3': hct.tone.round()}),
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!widget.preset.hct.isIdentity)
              TextButton(
                onPressed: () => widget.onHctChanged(SeedHct.none),
                child: Text(tr('Вернуть seed')),
              ),
          ],
        ),
      ],
    );
  }
}

class _HctRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String unit;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _HctRow({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0, max),
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '${value.round()}$unit',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DerivedSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DerivedSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(
        tr('Контейнеры — из моего акцента'),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        tr('Если заколоть primary вручную, светлые контейнеры пересчитаются в его же оттенок — тема остаётся цельной. Выключите, чтобы контейнеры остались как их построил Material.'),
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Редактор ролей
// ---------------------------------------------------------------------------

class _RolesSection extends StatelessWidget {
  final ThemePreset preset;
  final Brightness brightness;
  final void Function(String role, Color? color) onOverride;

  const _RolesSection({
    required this.preset,
    required this.brightness,
    required this.onOverride,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = preset.schemeFor(brightness);
    final overrides = preset.overridesFor(brightness);
    final issues = contrastIssues(scheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Headline(text: tr('Цвета ролей')),
            const Spacer(),
            Text(
              brightness == Brightness.light ? tr('светлая') : tr('тёмная'),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tr('Всё, что не трогать, считает Material. Нажатие — точный цвет, «Авто» — вернуть расчёт.'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        for (final row in themeRoleRows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.hint.isNotEmpty
                      ? '${row.label} · ${row.hint}'
                      : row.label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slot in row.slots)
                      _RoleTile(
                        key: Key('role_$slot'),
                        role: slot,
                        color: readRole(scheme, slot),
                        pinned: overrides.containsKey(slot),
                        contrastAgainst: themeOnBackground[slot] == null
                            ? null
                            : readRole(scheme, themeOnBackground[slot]!),
                        onTap: () async {
                          final edit = await showThemeColorEditor(
                            context,
                            title: themeRoleLabels[slot] ?? slot,
                            initial: readRole(scheme, slot),
                            contrastAgainst: themeOnBackground[slot] == null
                                ? null
                                : readRole(scheme, themeOnBackground[slot]!),
                            hint: slot,
                            allowClear: true,
                          );
                          if (edit == null) return;
                          onOverride(slot, edit.cleared ? null : edit.color);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (issues.isNotEmpty)
          _Notice(
            icon: Icons.visibility_off_rounded,
            text: trf('Нечитаемые пары: {p0}', {'p0': issues.join(', ')}),
            error: true,
          ),
      ],
    );
  }
}

class _RoleTile extends StatelessWidget {
  final String role;
  final Color color;
  final bool pinned;
  final Color? contrastAgainst;
  final VoidCallback onTap;

  const _RoleTile({
    super.key,
    required this.role,
    required this.color,
    required this.pinned,
    required this.onTap,
    this.contrastAgainst,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: scheme.surfaceContainerHigh,
          border: Border.all(
            color: pinned ? scheme.primary : scheme.outlineVariant,
            width: pinned ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: contrastAgainst == null
                      ? null
                      : Center(
                          child: Text(
                            tr('А'),
                            style: TextStyle(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                ),
                const Spacer(),
                if (pinned)
                  Icon(Icons.push_pin_rounded, size: 14, color: scheme.primary),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              themeRoleLabels[role] ?? role,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              hexOf(color),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10.5,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Мелочи
// ---------------------------------------------------------------------------

class _Headline extends StatelessWidget {
  final String text;
  const _Headline({required this.text});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      fontSize: 13,
      letterSpacing: 0.4,
    ),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool error;

  const _Notice({required this.icon, required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = error
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = error
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foreground, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
