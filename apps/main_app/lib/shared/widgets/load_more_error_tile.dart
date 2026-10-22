import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Хвост списка, когда следующая страница не дошла.
///
/// Пагинация, которая молча перестаёт подгружать, неотличима от «контент
/// закончился»: человек уходит, решив, что лента короткая. Ошибку первой
/// страницы показывают отдельным экраном, а здесь список уже на экране — его
/// перекрывать нельзя, поэтому повтор прячем в конце.
class LoadMoreErrorTile extends StatelessWidget {
  final VoidCallback onRetry;

  const LoadMoreErrorTile({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Не удалось загрузить дальше'),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(tr('Повторить'))),
        ],
      ),
    );
  }
}
