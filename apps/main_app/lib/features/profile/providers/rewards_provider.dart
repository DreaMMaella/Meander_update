import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';

// ============================================================================
//  НАГРАДЫ ЗА АКТИВНОСТЬ
//
//  Лестница живёт на сервере: он же и считает метрики, и выдаёт предметы.
//  От клиента нужно только показать прогресс и поздравить с тем, что
//  открылось прямо сейчас (`granted_now` приходит в том же ответе, потому что
//  сам запрос открытия списка и провоцирует выдачу).
// ============================================================================

/// На что копит награда. Подписи — только для группировки на экране.
enum RewardMetric {
  streak('streak'),
  gameDays('game_days'),
  reviews('reviews'),
  downloads('downloads');

  const RewardMetric(this.wire);
  final String wire;

  /// Подпись метрики человеку — в геттере, чтобы перевод снимался на витрине.
  String get label => switch (this) {
    RewardMetric.streak => tr('Дни подряд'),
    RewardMetric.gameDays => tr('Игровые дни'),
    RewardMetric.reviews => tr('Отзывы'),
    RewardMetric.downloads => tr('Скачивания'),
  };

  static RewardMetric fromWire(String value) => RewardMetric.values.firstWhere(
    (m) => m.wire == value,
    orElse: () => RewardMetric.streak,
  );
}

class RewardRule {
  const RewardRule({
    required this.id,
    required this.metric,
    required this.threshold,
    required this.title,
    required this.hint,
    required this.cosmeticIds,
    required this.current,
    required this.done,
    this.grantedAt,
  });

  final String id;
  final RewardMetric metric;
  final int threshold;
  final String title;
  final String hint;
  final List<String> cosmeticIds;

  /// Сколько уже набрано по этой метрике.
  final int current;

  /// Порог пройден сервером; `grantedAt` при этом всё равно может быть null —
  /// выдача случится в тот же запрос, просто поле читается независимо.
  final bool done;
  final DateTime? grantedAt;

  bool get claimed => grantedAt != null;

  double get ratio => threshold <= 0
      ? 1
      : (current / threshold).clamp(0.0, 1.0).toDouble();

  /// Осталось до порога; 0, когда всё уже набрано.
  int get remaining => (threshold - current) < 0 ? 0 : threshold - current;

  /// Предметы, которые реально знает каталог. Сервер может выдать id из
  /// более новой версии каталога, чем собран клиент.
  List<CosmeticDef> get cosmetics =>
      cosmeticIds.map(cosmeticById).whereType<CosmeticDef>().toList();

  factory RewardRule.fromJson(Map<String, dynamic> json) => RewardRule(
    id: json['id']?.toString() ?? '',
    metric: RewardMetric.fromWire(json['metric']?.toString() ?? ''),
    threshold: _asInt(json['threshold']),
    title: json['title']?.toString() ?? '',
    hint: json['hint']?.toString() ?? '',
    cosmeticIds: ((json['cosmetics'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    current: _asInt(json['current']),
    done: json['done'] == true,
    grantedAt: DateTime.tryParse(json['granted_at']?.toString() ?? ''),
  );
}

class RewardList {
  const RewardList({this.rules = const [], this.justGranted = const []});

  final List<RewardRule> rules;

  /// id правил, выданных этим же запросом.
  final List<String> justGranted;

  static const empty = RewardList();

  List<RewardRule> byMetric(RewardMetric metric) =>
      rules.where((r) => r.metric == metric).toList();

  int get claimedCount => rules.where((r) => r.claimed).length;

  RewardRule? byId(String id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }
}

/// BIGINT и COUNT из node-postgres приходят строкой.
int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

final rewardsProvider = FutureProvider.autoDispose<RewardList>((ref) async {
  final api = ref.watch(apiServiceProvider);
  try {
    final response = await api.get('profiles/me/rewards');
    if (response is! Map<String, dynamic>) return RewardList.empty;
    final rules = ((response['rules'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RewardRule.fromJson)
        .toList();
    final grantedNow = ((response['granted_now'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    return RewardList(rules: rules, justGranted: grantedNow);
  } catch (_) {
    // Экран открывается из профиля: без наград он обязан показывать каталог
    // прогресса, а не красную заглушку.
    return RewardList.empty;
  }
});
