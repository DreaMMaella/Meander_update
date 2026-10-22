import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/services/api_service.dart';

const kAssetKinds = ['button_preset', 'background', 'sfx', 'font'];

/// Подписи типов ассетов. Геттер, а не const-таблица: значения строятся под
/// текущий язык. Ключи (`button_preset` и т. п.) — данные, их не трогаем.
Map<String, String> get kAssetKindLabels => {
  'button_preset': tr('Пресеты кнопок'),
  'background': tr('Фоны'),
  'sfx': tr('Звуки'),
  'font': tr('Шрифты'),
  'image': tr('Изображения'),
  'music': tr('Музыка'),
};

String assetKindLabel(String kind) => kAssetKindLabels[kind] ?? kind;

Map<String, String> get kLicenseLabels => {
  'cc0': tr('CC0 (общественное достояние)'),
  'cc-by': 'CC BY',
  'cc-by-sa': 'CC BY-SA',
  'cc-by-nc': 'CC BY-NC',
  'cc-by-nc-sa': 'CC BY-NC-SA',
  'cc-by-nd': 'CC BY-ND',
  'mit': 'MIT',
  'apache-2.0': 'Apache 2.0',
  'gpl-3.0': 'GPL 3.0',
};

/// Человекочитаемая лицензия; пустое значение = дефолт CC-BY
/// (как на бэкенде и в MarketAsset.fromJson).
String licenseLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return kLicenseLabels['cc-by']!;
  final key = raw.trim().toLowerCase();
  return kLicenseLabels[key] ?? raw.trim();
}

/// Жанр для отображения: если юзер не заполнил — показываем тип ассета.
String assetGenreDisplay(String? genre, String kind) {
  final g = genre?.trim();
  if (g == null || g.isEmpty) return assetKindLabel(kind);
  return g;
}

final assetSearchProvider = StateProvider<String>((_) => '');
final assetKindProvider = StateProvider<String?>((_) => null);
final assetGenreProvider = StateProvider<String?>((_) => null);

/// Потолок страницы у бэкенда (`GET /assets` режет LIMIT 200, дефолт — 50).
const String kAssetQueryLimit = '200';

final assetListProvider = FutureProvider.autoDispose<List<MarketAsset>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final data = await api.get('assets', queryParams: {'limit': kAssetQueryLimit});
  return (data as List).map((e) => MarketAsset.fromJson(e as Map<String, dynamic>)).toList();
});

final searchAssetProvider = FutureProvider.autoDispose.family<List<MarketAsset>, String>((ref, query) async {
  final api = ref.watch(apiServiceProvider);
  final data = await api.get('assets', queryParams: {'search': query, 'limit': kAssetQueryLimit});
  return (data as List).map((e) => MarketAsset.fromJson(e as Map<String, dynamic>)).toList();
});

/// Список маркета с учётом чипов «вид» и «жанр».
///
/// Раньше базой служил `assetListProvider`, а сервер по умолчанию отдаёт
/// последние 50 строк: фильтр по виду/жанру нарезался локально по этому
/// хвосту, и «Только шрифты» пустел, стоило шрифтам не попасть в свежие
/// пятьдесят загрузок. Теперь вид и жанр уезжают на сервер (`kind`,
/// `genre` он поддерживает), а клиент добирает только то, что сервер
/// смешать не умеет (синонимы звуковых видов).
final filteredAssetProvider = FutureProvider.autoDispose<List<MarketAsset>>((ref) async {
  final search = ref.watch(assetSearchProvider).trim();
  final kind = ref.watch(assetKindProvider);
  final genre = ref.watch(assetGenreProvider);
  // ВАЖНО: сразу подписываемся на assetListProvider, а не только на его .future.
  // Иначе после invalidate(assetListProvider) (удаление ресурса, pull-to-refresh)
  // этот провайдер отдавал закэшированный список со старыми данными, и удалённый
  // ресурс продолжал отображаться в маркете до полного перезапуска приложения.
  ref.watch(assetListProvider);

  final params = <String, String>{'limit': kAssetQueryLimit};
  if (search.isNotEmpty) params['search'] = search;
  // Один kind сервер умеет, а «звуки» в клиенте — это sfx + audio + music:
  // эту группу режем локально по полной выборке.
  final audioGroup = kind == 'sfx' || kind == 'audio' || kind == 'music';
  if (kind != null && kind.isNotEmpty && !audioGroup) params['kind'] = kind;
  if (genre != null && genre.isNotEmpty) params['genre'] = genre;

  final api = ref.watch(apiServiceProvider);
  final data = await api.get('assets', queryParams: params);
  var base =
      (data as List)
          .map((e) => MarketAsset.fromJson(e as Map<String, dynamic>))
          .toList();
  if (audioGroup) {
    base = base.where((a) => a.kind == 'sfx' || a.kind == 'audio' || a.kind == 'music').toList();
  }
  return base;
});

final authorAssetsProvider = FutureProvider.autoDispose.family<List<MarketAsset>, String>((ref, authorId) async {
  final api = ref.watch(apiServiceProvider);
  final data = await api.get('assets', queryParams: {'author_id': authorId, 'limit': '100'});
  return (data as List).map((e) => MarketAsset.fromJson(e as Map<String, dynamic>)).toList();
});

