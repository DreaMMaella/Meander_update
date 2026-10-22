import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/models/wall_comment_model.dart';
import 'package:canvas_app/models/wall_post_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final wallPostsProvider = FutureProvider.family<List<WallPost>, String>((
  ref,
  authorId,
) async {
  final api = ref.watch(apiServiceProvider);
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id') ?? '';

  final response = await api.get(
    'api/author-walls/$authorId/posts',
    queryParams: {'limit': '20', 'viewer_id': userId},
  );

  if (response is! List) return [];

  return response.map((json) => WallPost.fromJson(json)).toList();
});

final wallPostCommentsProvider =
    FutureProvider.family<List<WallComment>, String>((ref, postId) async {
      final api = ref.watch(apiServiceProvider);
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';

      final response = await api.get(
        'api/author-walls/posts/$postId/comments',
        queryParams: {'viewer_id': userId},
      );

      if (response is! List) return [];

      return response.map((json) => WallComment.fromJson(json)).toList();
    });

class WallNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref ref;

  WallNotifier(this.ref) : super(const AsyncData(null));

  Future<WallPost> getPost(String postId, {String? viewerId}) async {
    try {
      final query = viewerId != null ? '?viewer_id=$viewerId' : '';
      final api = ref.read(apiServiceProvider);
      final response = await api.get('api/author-walls/posts/$postId$query');
      return WallPost.fromJson(response);
    } catch (e) {
      throw Exception('Failed to load post: $e');
    }
  }

  Future<void> createPost(String authorId, String content) async {
    state = const AsyncLoading();
    try {
      final api = ref.read(apiServiceProvider);
      await api.post(
        'api/author-walls/$authorId/posts',
        body: {'content': content},
      );
      ref.invalidate(wallPostsProvider(authorId));
      state = const AsyncData(null);
    } catch (e, st) {
      debugPrint('[WallNotifier] createPost error: $e\n$st');
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> editPost(String authorId, String postId, String content, List<String> mediaUrls) async {
    state = const AsyncLoading();
    try {
      final api = ref.read(apiServiceProvider);
      await api.put(
        'api/author-walls/posts/$postId',
        body: {'content': content, 'media_urls': mediaUrls},
      );
      ref.invalidate(wallPostsProvider(authorId));
      state = const AsyncData(null);
    } catch (e, st) {
      debugPrint('[WallNotifier] editPost error: $e\n$st');
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> deletePost(String authorId, String postId) async {
    state = const AsyncLoading();
    try {
      final api = ref.read(apiServiceProvider);
      await api.delete('api/author-walls/posts/$postId');
      ref.invalidate(wallPostsProvider(authorId));
      state = const AsyncData(null);
    } catch (e, st) {
      debugPrint('[WallNotifier] deletePost error: $e\n$st');
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<bool> toggleLike(
    String authorId,
    String postId,
    bool currentlyLiked,
  ) async {
    state = const AsyncLoading();
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.post('api/author-walls/posts/$postId/like');
      final liked = response['liked'] as bool;
      ref.invalidate(wallPostsProvider(authorId));
      state = const AsyncData(null);
      return liked;
    } catch (e, st) {
      debugPrint('[WallNotifier] toggleLike error: $e\n$st');
      state = AsyncError(e, st);
      return currentlyLiked;
    }
  }

  Future<void> addComment(String postId, String content, {String? parentId}) async {
    state = const AsyncLoading();
    try {
      final api = ref.read(apiServiceProvider);
      final body = <String, dynamic>{'content': content};
      if (parentId != null) {
        body['parentId'] = parentId;
      }
      await api.post(
        'api/author-walls/posts/$postId/comments',
        body: body,
      );
      ref.invalidate(wallPostCommentsProvider(postId));
      state = const AsyncData(null);
    } catch (e, st) {
      debugPrint('[WallNotifier] addComment error: $e\n$st');
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> editComment(String postId, String commentId, String content) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.put(
        'api/author-walls/comments/$commentId',
        body: {'content': content},
      );
      ref.invalidate(wallPostCommentsProvider(postId));
    } catch (e, st) {
      debugPrint('[WallNotifier] editComment error: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteComment(String postId, String commentId) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.delete('api/author-walls/comments/$commentId');
      ref.invalidate(wallPostCommentsProvider(postId));
    } catch (e, st) {
      debugPrint('[WallNotifier] deleteComment error: $e\n$st');
      rethrow;
    }
  }

  Future<bool> toggleCommentLike(
    String postId,
    String commentId,
    bool currentlyLiked,
  ) async {
    state = const AsyncLoading();
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.post(
        'api/author-walls/comments/$commentId/like',
      );
      final liked = response['liked'] as bool;
      ref.invalidate(wallPostCommentsProvider(postId));
      state = const AsyncData(null);
      return liked;
    } catch (e, st) {
      debugPrint('[WallNotifier] toggleCommentLike error: $e\n$st');
      state = AsyncError(e, st);
      return currentlyLiked;
    }
  }

  Future<void> reportPost(String postId, String reason) async {
    state = const AsyncLoading();
    try {
      final api = ref.read(apiServiceProvider);
      await api.post(
        'api/author-walls/posts/$postId/report',
        body: {'reason': reason},
      );
      state = const AsyncData(null);
    } catch (e, st) {
      debugPrint('[WallNotifier] reportPost error: $e\n$st');
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> reportComment(String commentId, String reason) async {
    state = const AsyncLoading();
    try {
      final api = ref.read(apiServiceProvider);
      await api.post(
        'api/author-walls/comments/$commentId/report',
        body: {'reason': reason},
      );
      state = const AsyncData(null);
    } catch (e, st) {
      debugPrint('[WallNotifier] reportComment error: $e\n$st');
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final wallNotifierProvider =
    StateNotifierProvider<WallNotifier, AsyncValue<void>>((ref) {
      return WallNotifier(ref);
    });
