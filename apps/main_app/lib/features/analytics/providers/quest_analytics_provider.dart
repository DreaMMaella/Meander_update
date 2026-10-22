import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/analytics/models/quest_analytics_model.dart';

/// Ключ семейства: квест и длина окна. Запись-ключ, а не класс, — сравнение
/// у записей структурное, и переключение фильтра не плодит второй провайдер
/// на те же самые данные.
typedef QuestAnalyticsKey = ({String questId, int days});

final questAnalyticsProvider = FutureProvider.autoDispose
    .family<QuestAnalytics, QuestAnalyticsKey>((ref, key) async {
      final api = ref.watch(apiServiceProvider);
      final response = await api.get(
        'quests/${key.questId}/analytics',
        queryParams: {'days': '${key.days}'},
      );
      if (response is! Map<String, dynamic>) {
        throw Exception(tr('Сервер вернул не список статистики'));
      }
      return QuestAnalytics.fromJson(response);
    });

/// Сводка автора: длина окна — единственный параметр, квестов много сразу.
final authorAnalyticsProvider = FutureProvider.autoDispose
    .family<AuthorAnalytics, int>((ref, days) async {
      final api = ref.watch(apiServiceProvider);
      final response = await api.get(
        'quests/analytics/author',
        queryParams: {'days': '$days'},
      );
      if (response is! Map<String, dynamic>) {
        throw Exception(tr('Сервер вернул не список статистики'));
      }
      return AuthorAnalytics.fromJson(response);
    });
