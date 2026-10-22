import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/theme/context_extensions.dart';
import 'package:canvas_app/features/wall/providers/wall_paginated_provider.dart';
import 'package:canvas_app/features/wall/widgets/post_card.dart';
import 'package:canvas_app/features/wall/widgets/post_composer.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/load_more_error_tile.dart';

class WallSection extends ConsumerStatefulWidget {
  final String authorId;
  final String? authorAvatarUrl;
  final ScrollController? scrollController;

  const WallSection({
    super.key,
    required this.authorId,
    this.authorAvatarUrl,
    this.scrollController,
  });

  @override
  ConsumerState<WallSection> createState() => _WallSectionState();
}

class _WallSectionState extends ConsumerState<WallSection> {
  bool _isCurrentUser = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
    _initLoad();
    _setupScrollListener();
  }

  Future<void> _checkCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (mounted) {
      setState(() => _isCurrentUser = userId == widget.authorId);
    }
  }

  void _initLoad() {
    final provider = wallPaginatedProvider(widget.authorId);
    final notifier = ref.read(provider.notifier);
    final state = ref.read(provider);
    if (state.posts.isEmpty && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.loadPosts();
      });
    }
  }

  void _setupScrollListener() {
    final controller = widget.scrollController;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.addListener(_onScroll);
    });
  }

  void _onScroll() {
    final controller = widget.scrollController;
    if (controller == null) return;
    final state = ref.read(wallPaginatedProvider(widget.authorId));
    if (!controller.hasClients) return;
    if (controller.position.pixels >=
            controller.position.maxScrollExtent - 300 &&
        !state.isLoadingMore &&
        state.hasMore &&
        !state.isLoading) {
      ref.read(wallPaginatedProvider(widget.authorId).notifier).loadMore();
    }
  }

  @override
  void dispose() {
    final controller = widget.scrollController;
    if (controller != null) {
      controller.removeListener(_onScroll);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallState = ref.watch(wallPaginatedProvider(widget.authorId));

    if (wallState.isLoading) {
      return SliverFillRemaining(
        hasScrollBody: true,
        child: _WallShimmer(),
      );
    }

    if (wallState.error != null && wallState.posts.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: true,
        child: _buildError(wallState.error!),
      );
    }

    if (wallState.posts.isEmpty) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0 && _isCurrentUser) {
              return Column(
                children: [
                  PostComposer(
                    authorId: widget.authorId,
                    authorAvatarUrl: widget.authorAvatarUrl,
                  ),
                  const SizedBox(height: 16),
                  _buildEmpty(),
                ],
              );
            }
            if (index == 0) {
              return _buildEmpty();
            }
            return const SizedBox.shrink();
          },
          childCount: 1,
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0 && _isCurrentUser) {
            return PostComposer(
              authorId: widget.authorId,
              authorAvatarUrl: widget.authorAvatarUrl,
            );
          }
          final postIndex = index - (_isCurrentUser ? 1 : 0);
          if (postIndex < wallState.posts.length) {
            return PostCard(
              key: ValueKey(wallState.posts[postIndex].id),
              post: wallState.posts[postIndex],
            );
          }
          if (wallState.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (wallState.error != null) {
            return LoadMoreErrorTile(
              onRetry: () => ref
                  .read(wallPaginatedProvider(widget.authorId).notifier)
                  .loadMore(),
            );
          }
          return const SizedBox.shrink();
        },
        childCount:
            (_isCurrentUser ? 1 : 0) +
            wallState.posts.length +
            ((wallState.isLoadingMore || wallState.error != null) ? 1 : 0),
      ),
    );
  }

  Widget _buildError(String error) {
    final colors = context.themeColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: colors.textPlaceholder),
            const SizedBox(height: 12),
            Text(
              tr('Ошибка загрузки'),
              style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: GoogleFonts.inter(color: colors.textPlaceholder, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: () =>
                    ref.read(wallPaginatedProvider(widget.authorId).notifier).loadPosts(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.fabForeground,
                  shape: StadiumBorder(),
                  elevation: 0,
                ),
                child: Text(tr('Повторить')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final colors = context.themeColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 64, color: colors.textPlaceholder.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(
              tr('Нет постов'),
              style: GoogleFonts.inter(color: colors.textPlaceholder, fontSize: 15),
            ),
            if (_isCurrentUser) ...[
              const SizedBox(height: 4),
              Text(
                tr('Напишите что-нибудь!'),
                style: GoogleFonts.inter(color: colors.textPlaceholder.withOpacity(0.6), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WallShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) {
        return Shimmer.fromColors(
          baseColor: colors.shimmerBase,
          highlightColor: colors.shimmerHighlight,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 18, backgroundColor: colors.surfaceLight),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 10,
                          width: 80,
                          decoration: BoxDecoration(
                            color: colors.surfaceLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 8,
                          width: 50,
                          decoration: BoxDecoration(
                            color: colors.surfaceLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 10,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colors.surfaceLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 180,
                  decoration: BoxDecoration(
                    color: colors.surfaceLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
