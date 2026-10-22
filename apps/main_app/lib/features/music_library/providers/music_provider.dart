import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:canvas_app/core/services/api_service.dart';

final musicSearchProvider = StateProvider<String>((_) => '');
final musicGenreProvider = StateProvider<String?>((_) => null);

final musicTracksProvider = FutureProvider.autoDispose<List<MusicTrack>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final data = await api.get('music');
  final list = (data as List).map((e) => MusicTrack.fromJson(e as Map<String, dynamic>)).toList();
  return list;
});

final searchMusicTracksProvider = FutureProvider.autoDispose.family<List<MusicTrack>, String>((ref, query) async {
  final api = ref.watch(apiServiceProvider);
  final data = await api.get('music', queryParams: {'search': query});
  final list = (data as List).map((e) => MusicTrack.fromJson(e as Map<String, dynamic>)).toList();
  return list;
});

final filteredMusicTracksProvider = FutureProvider.autoDispose<List<MusicTrack>>((ref) async {
  final search = ref.watch(musicSearchProvider).trim();
  final genre = ref.watch(musicGenreProvider);
  // ВАЖНО: сразу подписываемся на musicTracksProvider, а не только на его .future.
  // Иначе после invalidate(musicTracksProvider) (удаление трека, pull-to-refresh)
  // этот провайдер отдавал закэшированный список со старыми данными, и удалённый
  // трек продолжал отображаться до перезапуска приложения.
  ref.watch(musicTracksProvider);
  List<MusicTrack> base;
  if (search.isNotEmpty) {
    base = await ref.watch(searchMusicTracksProvider(search).future);
  } else {
    base = await ref.watch(musicTracksProvider.future);
  }
  if (genre != null && genre.isNotEmpty) {
    base = base.where((t) => t.genres.contains(genre) || t.genre == genre).toList();
  }
  return base;
});

// upload helper - used directly via ApiService multipart in screen, kept here for invalidation
final musicUploadTriggerProvider = StateProvider<int>((_) => 0);
