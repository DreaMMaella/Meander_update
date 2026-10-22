import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/theme/theme_preset.dart';
import 'package:canvas_app/core/theme/theme_preset_provider.dart';
import 'package:canvas_app/core/theme/theme_provider.dart';
import 'package:canvas_app/features/settings/screens/theme_tuning_screen.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currentMode = ref.watch(themeModeProvider);
    final presetState = ref.watch(themePresetProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(tr('Тема оформления')),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (v) async {
              switch (v) {
                case 'import':
                  await _importDialog(context, ref);
                  break;
                case 'export':
                  await _exportActive(context, ref);
                  break;
                case 'docs':
                  await _showFormatDocs(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18),
                    SizedBox(width: 10),
                    Text(tr('Импорт темы')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_upload_outlined, size: 18),
                    SizedBox(width: 10),
                    Text(tr('Экспорт активной')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'docs',
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18),
                    SizedBox(width: 10),
                    Text(tr('Формат JSON')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: AdaptiveContent(
        maxWidth: 800,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _SectionTitle(text: tr('Режим')),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(tr('Светлая')),
                  icon: Icon(Icons.light_mode_rounded, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(tr('Системная')),
                  icon: Icon(Icons.settings_brightness_rounded, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(tr('Тёмная')),
                  icon: Icon(Icons.dark_mode_rounded, size: 18),
                ),
              ],
              selected: {currentMode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).setTheme(s.first),
            ),
            const SizedBox(height: 24),
            _SectionTitle(text: tr('Тема')),
            const SizedBox(height: 8),
            _PresetGrid(
              presets: presetState.all,
              activeId: presetState.active.id,
              onTap: (p) async {
                await ref.read(themePresetProvider.notifier).setActive(p.id);
              },
              onTune: (p) async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ThemeTuningScreen(preset: p),
                  ),
                );
              },
              onDelete: (p) async {
                if (p.isBuiltIn) return;
                await ref.read(themePresetProvider.notifier).removeCustom(p.id);
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ThemeTuningScreen(preset: presetState.active),
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
              label: Text(trf('Настроить «{p0}»', {'p0': presetState.active.name})),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _importDialog(context, ref),
              icon: const Icon(Icons.file_download_outlined),
              label: Text(tr('Импортировать тему')),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => _showFormatDocs(context),
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              label: Text(tr('Как создать свою тему — формат JSON')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    String? loadedFileName;

    final pasted = await showAppDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final scheme = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: Text(tr('Импорт темы')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Кнопки источника
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            final loaded = await _pickJsonFile();
                            if (loaded != null) {
                              setLocal(() {
                                controller.text = loaded.$2;
                                loadedFileName = loaded.$1;
                              });
                            }
                          },
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: Text(tr('Файл .json')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final clip = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            if (clip?.text != null) {
                              setLocal(() {
                                controller.text = clip!.text!;
                                loadedFileName = null;
                              });
                            }
                          },
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 18,
                          ),
                          label: Text(tr('Из буфера')),
                        ),
                      ),
                    ],
                  ),
                  if (loadedFileName != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.description_rounded,
                            size: 16,
                            color: scheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              loadedFileName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSecondaryContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 8,
                    minLines: 4,
                    onChanged: (_) {
                      // Если пользователь начал редактировать вручную —
                      // имя файла больше не показываем.
                      if (loadedFileName != null) {
                        setLocal(() => loadedFileName = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: tr('JSON темы или массив тем…'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Отмена')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: Text(tr('Импортировать')),
                ),
              ],
            );
          },
        );
      },
    );

    if (pasted != null && pasted.isNotEmpty) {
      try {
        final imported = await ref
            .read(themePresetProvider.notifier)
            .importFromJson(pasted);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(trf('Импортировано: {p0}', {'p0': imported.length}))),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(content: Text(trf('Ошибка импорта: {p0}', {'p0': friendlyError(e)}))),
          );
        }
      }
    }
  }

  /// Выбор JSON-файла через file_picker. Возвращает (имя файла, содержимое).
  Future<(String, String)?> _pickJsonFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return null;
      final file = files.first;

      String? content;
      try {
        final bytes = await file.readAsBytes();
        content = utf8.decode(bytes);
      } catch (_) {
        if (file.path != null) {
          content = await File(file.path!).readAsString();
        }
      }
      if (content == null || content.trim().isEmpty) return null;
      return (file.name, content);
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportActive(BuildContext context, WidgetRef ref) async {
    final json = ref.read(themePresetProvider.notifier).exportActive();
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('JSON темы скопирован в буфер'))),
      );
    }
  }

  Future<void> _showFormatDocs(BuildContext context) async {
    await showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ThemeFormatDocsSheet(),
    );
  }
}

// ============================================================================
//  МИНИ-ДОКУМЕНТАЦИЯ ФОРМАТА ТЕМЫ
// ============================================================================

class _ThemeFormatDocsSheet extends StatelessWidget {
  const _ThemeFormatDocsSheet();

  static const String _exampleMinimal = '''{
  "version": 2,
  "id": "my_theme",
  "name": "Моя тема",
  "seed": "#6750A4"
}''';

  static const String _exampleFull = '''{
  "version": 2,
  "id": "my_theme",
  "name": "Моя тема",
  "author": "ник",
  "seed": "#101014",
  "variant": "fidelity",
  "hct": { "chroma": 26, "tone": 44 },
  "deriveContainers": true,
  "light": { "surface": "#FFFBF5", "primary": "#6A5B00" },
  "dark": { "primary": "#E7D06A" },
  "bannerGradient": ["#3A3A44", "#101014"]
}''';

  static const String _exampleArray = '''[
  {
    "version": 2,
    "id": "ocean_pro",
    "name": "Океан Pro",
    "seed": "#0288D1",
    "variant": "content",
    "bannerGradient": ["#0288D1", "#00ACC1"]
  },
  {
    "version": 2,
    "id": "fire",
    "name": "Огонь",
    "seed": "#FF5722",
    "dark": { "surface": "#140A06", "primary": "#FFB59A" }
  }
]''';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  tr('Формат JSON темы'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr('Тема — это JSON-объект (или массив объектов). Минимум — id, name и seed: из него Material 3 построит всю палитру. Дальше можно выбрать вариант палитры, поправить seed по HCT (оттенок/насыщенность/светлота) и заколоть любые отдельные роли в light/dark — что не заколото, дорассчитает алгоритм.'),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            _DocSection(
              title: tr('Поля'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DocField(
                    name: 'version',
                    required: true,
                    type: 'int',
                    description: tr('Версия формата. Всегда 1.'),
                  ),
                  _DocField(
                    name: 'id',
                    required: true,
                    type: 'string',
                    description:
                        tr('Уникальный идентификатор темы. Латиница, цифры, _.'),
                  ),
                  _DocField(
                    name: 'name',
                    required: true,
                    type: 'string',
                    description: tr('Отображаемое название темы.'),
                  ),
                  _DocField(
                    name: 'seed',
                    required: true,
                    type: tr('hex-цвет'),
                    description:
                        tr('Семя-цвет в формате "#RRGGBB" или "#AARRGGBB". Из него Material 3 построит всю палитру.'),
                  ),
                  _DocField(
                    name: 'author',
                    required: false,
                    type: 'string',
                    description: tr('Имя автора темы (для соавторских работ).'),
                  ),
                  _DocField(
                    name: 'bannerGradient',
                    required: false,
                    type: tr('массив hex-цветов'),
                    description:
                        tr('Градиент для шапки профиля. Обычно 2 цвета: ["#0088FF", "#00CCAA"]. Если не задан — берётся градиент из палитры темы.'),
                  ),
                  _DocField(
                    name: 'variant',
                    required: false,
                    type: 'string',
                    description:
                        tr('Вариант палитры M3: fidelity (цвет остаётся моим), vibrant (по умолчанию, усиленный), tonalSpot, expressive, content, neutral, monochrome (графит), rainbow, fruitSalad.'),
                  ),
                  _DocField(
                    name: 'hct',
                    required: false,
                    type: tr('объект {hue, chroma, tone}'),
                    description:
                        tr('Ручки опорного цвета. Тон (0..100) — светлота: у чёрного он 0, поэтому «чёрный seed» физически не может быть акцентом, пока тон не поднят. Chroma — насыщенность, hue — оттенок 0..360.'),
                  ),
                  _DocField(
                    name: 'deriveContainers',
                    required: false,
                    type: 'bool',
                    description:
                        tr('По умолчанию true: если заколоть primary, то primaryContainer пересчитается в тот же оттенок (тон 80 в светлой, 30 в тёмной). false — контейнеры остаются как их построил Material.'),
                  ),
                  _DocField(
                    name: 'light / dark',
                    required: false,
                    type: tr('объект роль → hex'),
                    description:
                        tr('Ручные цвета конкретных ролей: primary, secondary, tertiary, error, surface, background, *Container, surfaceContainer0..4, outline, inverseSurface, scrim, shadow и все on*. Незаколотые on* подбираются сами под контраст не ниже 4.5:1.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _DocSection(
              title: tr('Минимальный пример'),
              child: _CodeBlock(text: _exampleMinimal),
            ),
            const SizedBox(height: 14),
            _DocSection(
              title: tr('Полная тема: вариант + ручки HCT + пины ролей'),
              child: _CodeBlock(text: _exampleFull),
            ),
            const SizedBox(height: 14),
            _DocSection(
              title: tr('Несколько тем сразу (массив)'),
              child: _CodeBlock(text: _exampleArray),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tips_and_updates_rounded,
                    color: scheme.onTertiaryContainer,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('Совет: не обязательно писать JSON руками — «Настроить» у любой темы даёт те же поля визуально (вариант, ручки HCT, пины ролей), а кнопка «JSON темы» вверху показывает, что получилось. Меню → «Экспорт активной» — то же в буфер.'),
                      style: TextStyle(
                        color: scheme.onTertiaryContainer,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_rounded),
                label: Text(tr('Понятно')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _DocSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _DocField extends StatelessWidget {
  final String name;
  final String type;
  final String description;
  final bool required;

  const _DocField({
    required this.name,
    required this.type,
    required this.description,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(
                type,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: required
                      ? scheme.errorContainer
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  required ? tr('обязательно') : tr('необязательно'),
                  style: TextStyle(
                    color: required
                        ? scheme.onErrorContainer
                        : scheme.onSurfaceVariant,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 4),
            child: Text(
              description,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;
  const _CodeBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                color: scheme.onSurface,
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.copy_rounded,
              color: scheme.onSurfaceVariant,
              size: 18,
            ),
            tooltip: tr('Копировать'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(tr('Скопировано'))));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PresetGrid extends StatelessWidget {
  final List<ThemePreset> presets;
  final String activeId;
  final ValueChanged<ThemePreset> onTap;
  final ValueChanged<ThemePreset> onTune;
  final ValueChanged<ThemePreset> onDelete;

  const _PresetGrid({
    required this.presets,
    required this.activeId,
    required this.onTap,
    required this.onTune,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: presets.length,
      itemBuilder: (_, i) {
        final p = presets[i];
        return _PresetCard(
          preset: p,
          isActive: p.id == activeId,
          onTap: () => onTap(p),
          onTune: () => onTune(p),
          onDelete: p.isBuiltIn ? null : () => onDelete(p),
        );
      },
    );
  }
}

class _PresetCard extends StatelessWidget {
  final ThemePreset preset;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onTune;
  final VoidCallback? onDelete;

  const _PresetCard({
    required this.preset,
    required this.isActive,
    required this.onTap,
    required this.onTune,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lightPalette = preset.schemeFor(Brightness.light);
    final darkPalette = preset.schemeFor(Brightness.dark);
    final gradient =
        preset.bannerGradient ??
        [lightPalette.primaryContainer, lightPalette.tertiaryContainer];

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onTune,
        // ПК: тонкая настройка темы — по правой кнопке, как долгий тап.
        onSecondaryTap: onTune,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isActive ? scheme.primary : scheme.outlineVariant,
              width: isActive ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Row(
                          children: [
                            _ChipDot(color: lightPalette.primary),
                            const SizedBox(width: 4),
                            _ChipDot(color: darkPalette.primary),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: onTune,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.tune_rounded,
                                  size: 14,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isActive)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              color: scheme.onPrimary,
                              size: 14,
                            ),
                          ),
                        ),
                      if (onDelete != null)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: InkWell(
                            onTap: onDelete,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: scheme.surface.withOpacity(0.85),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: scheme.error,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (preset.author != null)
                Text(
                  preset.author!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipDot extends StatelessWidget {
  final Color color;
  const _ChipDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}
