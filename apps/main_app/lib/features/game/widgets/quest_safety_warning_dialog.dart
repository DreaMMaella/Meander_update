import 'package:canvas_app/core/services/quest_safety_service.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:mnd_core/models/quest_descriptor.dart';
import 'package:flutter/material.dart';

Future<void> showQuestSafetyWarning(
  BuildContext context, {
  required Quest quest,
  required QuestSafetyReport report,
}) async {
  if (!report.shouldShowWarning) return;

  await showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.shield_outlined, color: scheme.error),
        title: Text(tr('Внимание перед игрой')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (report.shouldWarnAboutInternet) ...[
                Text(
                  trf('Квест «{p0}» использует интернет-блоки ({p1}).', {'p0': quest.title, 'p1': report.internetBlockCount}),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Не вводите в квест свои пароли, коды из SMS, данные карт и другую чувствительную информацию. Обычные сетевые запросы разрешаются после этого предупреждения, а локальные адреса и известные IP-логгеры блокируются автоматически.'),
                ),
                if (report.authorIsVerified) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr('Автор подтверждён, но это предупреждение показывается всем квестам с интернет-доступом.'),
                  ),
                ],
                if (report.blockedUrlCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    trf('Заблокировано подозрительных адресов: {p0}.', {'p0': report.blockedUrlCount}),
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
              if (report.shouldWarnAboutInternet && report.isStale)
                const SizedBox(height: 16),
              if (report.isStale) ...[
                Text(
                  tr('Квест давно не обновлялся.'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  trf('Последняя версия{p0} редактировалась {p1}. Возможно, автор перестал её поддерживать.', {'p0': report.questVersion == null ? '' : ' ${report.questVersion}', 'p1': _formatDate(report.lastEditedAt!)}),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr('Понятно, продолжить')),
          ),
        ],
      );
    },
  );
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
}
