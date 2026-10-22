/// Форма айтема плагина: поля, которые плагин объявил в `plugin.json`.
///
/// Редактор собирает только данные — код плагина сюда не заглядывает.
/// Результат ложится в `pluginData` айтема и приходит плагину целиком в
/// `item_reveal`, а на сцене его рисует сам плагин через `mnd.ui.render`.
library;

import 'package:canvas_app/features/plugins/models/plugin_content_type.dart';
import 'package:canvas_app/features/resources/screens/resource_selection_screen.dart';
import 'package:canvas_app/models/content_item_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Создаёт айтем плагина с формы. `null` — автор отменил форму, и айтем
/// добавлять не нужно: пустой плагин-айтем выглядит в плеере как «плагин
/// ничего не вывел», и понять, откуда он взялся, невозможно.
Future<ContentItem?> createPluginContentItem(
  BuildContext context, {
  required PluginContentType type,
  required String questId,
}) async {
  final data = await showPluginContentForm(context, type: type, questId: questId);
  if (data == null) return null;
  return ContentItem(
    id: const Uuid().v4(),
    type: 'plugin',
    pluginId: type.pluginId,
    pluginTypeId: type.id,
    pluginData: data,
  );
}

/// Диалог полей типа контента. [initial] — данные уже существующего айтема.
Future<Map<String, dynamic>?> showPluginContentForm(
  BuildContext context, {
  required PluginContentType type,
  required String questId,
  Map<String, dynamic>? initial,
}) {
  final form = _PluginForm(type, initial: initial);
  return showAppDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(type.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (type.description != null) ...[
                  Text(
                    type.description!,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final field in type.fields)
                  _PluginFieldEditor(
                    field: field,
                    form: form,
                    questId: questId,
                    onChanged: setDialogState,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Отмена')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, form.collect()),
              child: Text(tr('ОК')),
            ),
          ],
        );
      },
    ),
  );
}

/// Состояние формы: три вида контроллеров по именам полей манифеста.
class _PluginForm {
  final List<PluginContentField> fields;
  final Map<String, TextEditingController> texts = {};
  final Map<String, String> choices = {};
  final Map<String, bool> flags = {};

  _PluginForm(PluginContentType type, {Map<String, dynamic>? initial})
    : fields = type.fields {
    for (final field in fields) {
      final raw = initial?[field.name] ?? field.defaultValue;
      if (field.kind == PluginFieldKind.bool) {
        flags[field.name] = raw == true;
      } else if (field.isChoice) {
        final value = raw?.toString() ?? '';
        choices[field.name] = field.options.contains(value)
            ? value
            : field.options.first;
      } else {
        texts[field.name] = TextEditingController(text: raw?.toString() ?? '');
      }
    }
  }

  Map<String, dynamic> collect() => {
    for (final field in fields) field.name: _value(field),
  };

  Object? _value(PluginContentField field) {
    if (field.kind == PluginFieldKind.bool) return flags[field.name] ?? false;
    if (field.isChoice) return choices[field.name] ?? field.options.first;
    final raw = texts[field.name]?.text.trim() ?? '';
    if (field.kind != PluginFieldKind.number) return raw;
    // Число в границах из манифеста; нераспарсившееся остаётся строкой —
    // плагину уходит то, что реально ввёл автор квеста.
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed == null) return raw;
    final clamped = parsed
        .clamp(field.min ?? parsed, field.max ?? parsed)
        .toDouble();
    return clamped == clamped.roundToDouble() ? clamped.toInt() : clamped;
  }
}

class _PluginFieldEditor extends StatelessWidget {
  final PluginContentField field;
  final _PluginForm form;
  final String questId;
  final StateSetter onChanged;

  const _PluginFieldEditor({
    required this.field,
    required this.form,
    required this.questId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = InputDecoration(
      labelText: field.label,
      helperText: field.hint ?? field.rangeHint,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
    );

    if (field.kind == PluginFieldKind.bool) {
      return SwitchListTile(
        value: form.flags[field.name] ?? false,
        onChanged: (value) => onChanged(() => form.flags[field.name] = value),
        title: Text(field.label),
        subtitle: field.hint == null ? null : Text(field.hint!),
        contentPadding: EdgeInsets.zero,
      );
    }

    if (field.isChoice) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: form.choices[field.name],
          isExpanded: true,
          decoration: decoration,
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (value) => onChanged(
            () => form.choices[field.name] = value ?? field.options.first,
          ),
        ),
      );
    }

    final controller = form.texts[field.name];
    final isColor = field.kind == PluginFieldKind.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: field.kind == PluginFieldKind.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        // Превью цвета обязано обновляться на каждое нажатие, иначе кружок
        // расходится с тем, что написано в поле.
        onChanged: isColor ? (_) => onChanged(() {}) : null,
        decoration: decoration.copyWith(
          prefixIcon: isColor
              ? Icon(
                  Icons.circle,
                  size: 18,
                  color: tryParsePluginColor(controller?.text) ??
                      scheme.outlineVariant,
                )
              : null,
          suffixIcon: field.kind == PluginFieldKind.asset
              ? IconButton(
                  tooltip: tr('Выбрать из библиотеки квеста'),
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    if (controller == null) return;
                    final picked = await Navigator.push<SelectableResource>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ResourceSelectionScreen(
                          questId: questId,
                          allowedTypes: const ['image', 'audio', 'video'],
                        ),
                      ),
                    );
                    if (picked == null) return;
                    // Пишем прямо в контроллер (он вне SetState), перерисовку
                    // просим ради превью и состояния поля.
                    controller.text = picked.path;
                    onChanged(() {});
                  },
                )
              : null,
        ),
      ),
    );
  }
}
