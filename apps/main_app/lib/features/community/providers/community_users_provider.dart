import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/features/community/models/community_user_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final communityOnlineProvider = FutureProvider.autoDispose<List<CommunityUser>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final response = await api.get('api/community/online?limit=20');
  final List list = response as List;
  return list.map((e) => CommunityUser.fromJson(e)).toList();
});

// filter can be 'followers', 'likes', 'quests'
final communityTopProvider = FutureProvider.autoDispose.family<List<CommunityUser>, String>((ref, filter) async {
  final api = ref.read(apiServiceProvider);
  final response = await api.get('api/community/top?limit=10&type=$filter');
  final List list = response as List;
  return list.map((e) => CommunityUser.fromJson(e)).toList();
});
