import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/core/utils/error_text.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  ДЕЙСТВИЯ НАД РЕСУРСОМ В МАРКЕТЕ
//
//  Тот же набор, что у квестов в маркете (quest_market_details_screen):
//  автор может удалить свой ресурс, админ — модерировать.
//  [endpoint] — 'assets' (пресеты, шрифты, фоны, звуки) либо 'music'.
// ============================================================================

class MarketResourceActions {
  const MarketResourceActions._();

  /// В базе статусы английские, но показывать их автору как есть — сырой enum.
  static String statusLabel(String value) => switch (value) {
    'published' => tr('опубликован'),
    'in_review' => tr('на модерации'),
    'rejected' => tr('отклонён'),
    _ => value,
  };

  static Future<bool> _confirmDestructive(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Отмена')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static Future<bool> confirmDelete(
    BuildContext context,
    WidgetRef ref, {
    required String endpoint,
    required String id,
    required String title,
    bool doubleConfirm = false,
  }) async {
    final ok = await _confirmDestructive(
      context,
      title: tr('Удалить?'),
      message: trf('«{title}» исчезнет из маркета навсегда.', {'title': title}),
      confirmLabel: tr('Удалить'),
    );
    if (!ok) return false;

    if (doubleConfirm) {
      if (!context.mounted) return false;
      final again = await _confirmDestructive(
        context,
        title: tr('Точно удалить?'),
        message:
            trf('Это действие необратимо. «{title}» и связанные данные будут удалены.', {'title': title}),
        confirmLabel: tr('Удалить навсегда'),
      );
      if (!again) return false;
    }

    try {
      await ref.read(apiServiceProvider).delete('$endpoint/$id');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trf('«{title}» удалено из маркета', {'title': title})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trf('Ошибка: {p0}', {'p0': friendlyError(e)})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// Шит админ-действий — та же структура, что у квеста в маркете
  /// (`quest_market_details_screen`): иконка + подпись у каждого пункта,
  /// удаление только с двойным подтверждением.
  /// Бэкенд ассетов и музыки понимает лишь `set_status`, поэтому пунктов
  /// меньше, чем у квестов (нет демо / 18+ / рекомендаций).
  /// [id] — id публикации в маркете: без него действовать не на что, и экран
  /// не должен предлагать админу этот шит.
  static Future<void> showAdminSheet(
    BuildContext context,
    WidgetRef ref, {
    required String endpoint,
    required String id,
    String? title,
    String? currentStatus,
    VoidCallback? onChanged,
    ValueChanged<String>? onDeleted,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final action = await showAdaptiveSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        Widget statusTile(
          String value,
          IconData icon,
          Color color,
          String subtitle,
        ) => ListTile(
          leading: Icon(icon, color: color),
          title: Text(trf('Статус: {p0}', {'p0': statusLabel(value)})),
          subtitle: Text(subtitle),
          trailing: currentStatus == value
              ? Icon(Icons.check_rounded, size: 20, color: scheme.primary)
              : null,
          onTap: () => Navigator.pop(ctx, 'status_$value'),
        );

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_rounded,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr('Админ-действия'),
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_rounded,
                    color: scheme.error,
                  ),
                  title: Text(tr('Удалить из маркета')),
                  subtitle: Text(tr('Навсегда, с двойным подтверждением')),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
                const Divider(height: 1),
                statusTile(
                  'published',
                  Icons.publish_rounded,
                  scheme.primary,
                  tr('Показывать в маркете'),
                ),
                statusTile(
                  'in_review',
                  Icons.hourglass_top_rounded,
                  scheme.secondary,
                  tr('Вернуть в очередь на модерацию'),
                ),
                statusTile(
                  'rejected',
                  Icons.block_rounded,
                  scheme.error,
                  tr('Отклонить, в маркете не показывается'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;

    try {
      if (action == 'delete') {
        final removed = await confirmDelete(
          context,
          ref,
          endpoint: endpoint,
          id: id,
          title: title ?? tr('Публикация'),
          doubleConfirm: true,
        );
        if (!removed) return;
        if (onDeleted != null) {
          onDeleted(id);
        } else {
          onChanged?.call();
        }
        return;
      }
      if (action.startsWith('status_')) {
        final value = action.substring('status_'.length);
        await ref.read(apiServiceProvider).post(
          '$endpoint/$id/admin/action',
          body: {
            'action': 'set_status',
            'value': value,
          },
        );
        onChanged?.call();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(trf('Статус изменён: {p0}', {'p0': statusLabel(value)})),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trf('Админ-действие не выполнено: {p0}', {'p0': friendlyError(e)})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
