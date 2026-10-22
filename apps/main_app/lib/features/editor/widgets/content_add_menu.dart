import 'package:canvas_app/features/editor/providers/content_clipboard_provider.dart';
import 'package:canvas_app/features/plugins/providers/plugin_content_types_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

class ContentAddMenuSheet extends ConsumerWidget {
  final List<String> excludeTypes;
  final Function(String type, {String? pluginTypeId}) onItemSelected;
  final VoidCallback onPaste;

  /// null — в этом экране вставка из шаблона не реализована: строки в меню
  /// тогда не показываем вовсе.
  final VoidCallback? onInsertFromTemplate;

  const ContentAddMenuSheet({
    super.key,
    this.excludeTypes = const [],
    required this.onItemSelected,
    required this.onPaste,
    this.onInsertFromTemplate,
  });

  static Future<void> show(
    BuildContext context, {
    List<String> excludeTypes = const [],
    required Function(String type, {String? pluginTypeId}) onItemSelected,
    required VoidCallback onPaste,
    VoidCallback? onInsertFromTemplate,
  }) {
    return showAdaptiveSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      builder: (ctx) => ContentAddMenuSheet(
        excludeTypes: excludeTypes,
        onItemSelected: onItemSelected,
        onPaste: onPaste,
        onInsertFromTemplate: onInsertFromTemplate,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemInClipboard = ref.watch(contentClipboardProvider);
    final pluginTypes =
        ref.watch(pluginContentTypesProvider).valueOrNull ?? const [];
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                if (itemInClipboard != null) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.paste_rounded,
                        color: Colors.blueAccent,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      trf('Вставить: {p0}', {'p0': _getItemTypeName(itemInClipboard.type, pluginTypeId: itemInClipboard.pluginTypeId)}),
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      tr('Добавить скопированный элемент'),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onPaste();
                    },
                  ),
                  Divider(color: scheme.outlineVariant.withOpacity(0.5)),
                ],

                if (onInsertFromTemplate != null) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bookmark_added_rounded,
                        color: Colors.cyanAccent,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      tr('Из шаблона'),
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      tr('Вставить готовый блок из репозитория шаблонов'),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onInsertFromTemplate!();
                    },
                  ),
                  Divider(color: scheme.outlineVariant.withOpacity(0.5)),
                ],

                if (!excludeTypes.contains('row'))
                  _buildAddOption(
                    context,
                    tr('Строка (Сетка)'),
                    'row',
                    Icons.table_rows_rounded,
                    Colors.orange,
                  ),
                if (!excludeTypes.contains('column'))
                  _buildAddOption(
                    context,
                    tr('Столбец'),
                    'column',
                    Icons.view_column_rounded,
                    Colors.purpleAccent,
                  ),
                if (!excludeTypes.contains('stack'))
                  _buildAddOption(
                    context,
                    tr('Стек'),
                    'stack',
                    Icons.dashboard_customize_rounded,
                    Colors.lightGreenAccent,
                  ),
                Divider(color: scheme.outlineVariant.withOpacity(0.5)),

                if (!excludeTypes.contains('text'))
                  _buildAddOption(
                    context,
                    tr('Текст'),
                    'text',
                    Icons.text_fields,
                    scheme.onSurface,
                  ),
                if (!excludeTypes.contains('image'))
                  _buildAddOption(
                    context,
                    tr('Изображение'),
                    'image',
                    Icons.image,
                    scheme.primary,
                  ),
                if (!excludeTypes.contains('button'))
                  _buildAddOption(
                    context,
                    tr('Кнопка'),
                    'button',
                    Icons.smart_button,
                    scheme.tertiary,
                  ),
                if (!excludeTypes.contains('button_jump'))
                  _buildAddOption(
                    context,
                    tr('Кнопка-переход'),
                    'button_jump',
                    Icons.forward_rounded,
                    Colors.tealAccent,
                  ),
                if (!excludeTypes.contains('input'))
                  _buildAddOption(
                    context,
                    tr('Поле ввода'),
                    'input',
                    Icons.edit,
                    Colors.purpleAccent,
                  ),
                if (!excludeTypes.contains('audio'))
                  _buildAddOption(
                    context,
                    tr('Аудио'),
                    'audio',
                    Icons.audiotrack,
                    Colors.greenAccent,
                  ),
                if (!excludeTypes.contains('video'))
                  _buildAddOption(
                    context,
                    tr('Видео'),
                    'video',
                    Icons.videocam,
                    Colors.redAccent,
                  ),
                if (!excludeTypes.contains('delay'))
                  _buildAddOption(
                    context,
                    tr('Задержка'),
                    'delay',
                    Icons.hourglass_empty,
                    scheme.onSurface,
                  ),
                if (!excludeTypes.contains('wait_input'))
                  _buildAddOption(
                    context,
                    tr('Пауза (Клик)'),
                    'wait_input',
                    Icons.touch_app,
                    Colors.amberAccent,
                  ),
                if (!excludeTypes.contains('modal'))
                  _buildAddOption(
                    context,
                    tr('Всплывающее окно'),
                    'modal',
                    Icons.chat_bubble_outline,
                    Colors.orangeAccent,
                  ),
                if (!excludeTypes.contains('script'))
                  _buildAddOption(
                    context,
                    tr('Скрипт'),
                    'script',
                    Icons.code,
                    scheme.onSurfaceVariant,
                  ),
                if (!excludeTypes.contains('chat'))
                  _buildAddOption(
                    context,
                    tr('Чат (сообщение)'),
                    'chat',
                    Icons.chat_bubble,
                    Colors.blueAccent,
                  ),
                if (!excludeTypes.contains('spacer'))
                  _buildAddOption(
                    context,
                    tr('Отступ'),
                    'spacer',
                    Icons.format_line_spacing,
                    Colors.grey,
                  ),
                if (pluginTypes.isNotEmpty &&
                    !excludeTypes.contains('plugin')) ...[
                  Divider(color: scheme.outlineVariant.withOpacity(0.5)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.extension,
                          color: scheme.onSurfaceVariant,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tr('Плагины'),
                          style: GoogleFonts.manrope(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...pluginTypes.map((pt) {
                    return _buildAddOption(
                      context,
                      pt.name,
                      'plugin',
                      pt.iconData ?? Icons.extension,
                      pt.accentColor,
                      subtitle: pt.description,
                      pluginTypeId: pt.id,
                    );
                  }),
                ],
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddOption(
    BuildContext context,
    String title,
    String type,
    IconData icon,
    Color color, {
    String? subtitle,
    String? pluginTypeId,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
      onTap: () {
        Navigator.pop(context);
        onItemSelected(type, pluginTypeId: pluginTypeId);
      },
    );
  }

  String _getItemTypeName(String type, {String? pluginTypeId}) {
    switch (type) {
      case 'text':
        return tr('Текст');
      case 'image':
        return tr('Изображение');
      case 'button':
      case 'button_jump':
        return tr('Кнопка');
      case 'input':
        return tr('Поле ввода');
      case 'audio':
        return tr('Аудио');
      case 'row':
        return tr('Строка');
      case 'column':
        return tr('Столбец');
      case 'stack':
        return tr('Стек');
      case 'delay':
        return tr('Задержка');
      case 'wait_input':
        return tr('Пауза (Клик)');
      case 'modal':
        return tr('Окно');
      case 'script':
        return tr('Скрипт');
      case 'plugin':
        return tr('Плагин');
      case 'chat':
        return tr('Чат');
      case 'spacer':
        return tr('Отступ');
      case 'video':
        return tr('Видео');
      default:
        return trf('Элемент ({p0})', {'p0': type});
    }
  }
}
