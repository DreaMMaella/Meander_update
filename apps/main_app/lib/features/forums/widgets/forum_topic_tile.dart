import 'package:canvas_app/core/utils/date_format.dart';
import 'package:canvas_app/core/utils/markdown_preview.dart';
import 'package:canvas_app/features/forums/models/forum_models.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Строка обсуждения — та же единица и в лобби сообщества, и в общей ленте,
/// куда топики подмешиваются. Поэтому виджет один и знает про чужое сообщество:
/// вне лобби человек должен видеть, ОТКУДА это обсуждение, а не гадать.
class ForumTopicTile extends StatefulWidget {
  const ForumTopicTile({
    super.key,
    required this.topic,
    required this.onOpen,
    this.onLike,
    this.communityName,
    this.onOpenCommunity,
    this.menu,
  });

  final ForumTopic topic;
  final VoidCallback onOpen;

  /// Лайк тодика — это лайк обычного поста сообщества: пустой обработчик
  /// означает, что пилюля показывает счётчик, но не нажимается (так было бы в
  /// чужом списке, где состоянием строк никто не владеет).
  final Future<String?> Function()? onLike;

  final String? communityName;
  final VoidCallback? onOpenCommunity;

  /// Кнопка модератора — справа от заголовка, чтобы не спорить за место с
  /// пилюлями внизу строки.
  final Widget? menu;

  @override
  State<ForumTopicTile> createState() => _ForumTopicTileState();
}

class _ForumTopicTileState extends State<ForumTopicTile> {
  bool _animLike = false;

  Future<void> _like() async {
    final onLike = widget.onLike;
    if (onLike == null) {
      widget.onOpen();
      return;
    }
    setState(() => _animLike = true);
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _animLike = false);
    });
    final error = await onLike();
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final topic = widget.topic;
    // Строка рисуется обычным Text, поэтому тело сюда приходит уже очищенным:
    // иначе человек читает `![Фото](https://…)` вместо сообщения.
    final preview = markdownPlainText(topic.body);
    // Картинка может лежать и в колонке media_urls, и прямо в тексте — из
    // текста её никто в колонку не переносил.
    final stripUrls = [
      ...{...topic.mediaUrls, ...markdownImageUrls(topic.body)},
    ];
    final heading = topic.title.isNotEmpty ? topic.title : preview;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Meta(
                          topic: topic,
                          communityName: widget.communityName,
                          onOpenCommunity: widget.onOpenCommunity,
                        ),
                      ),
                      if (widget.menu != null) widget.menu!,
                    ],
                  ),
                  const SizedBox(height: 7),
                  if (heading.isNotEmpty)
                    Text(
                      heading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  if (topic.title.isNotEmpty && preview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (topic.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in topic.tags.take(3))
                          _TopicTag(label: tag),
                      ],
                    ),
                  ],
                  if (stripUrls.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    _MediaStrip(urls: stripUrls),
                  ],
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      _ActionPill(
                        icon: topic.isLikedByViewer
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: formatCompactCount(topic.likesCount),
                        color: topic.isLikedByViewer
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        background: topic.isLikedByViewer
                            ? scheme.primaryContainer
                            : Colors.transparent,
                        animateIcon: _animLike,
                        onTap: _like,
                      ),
                      const SizedBox(width: 4),
                      _ActionPill(
                        icon: Icons.mode_comment_outlined,
                        label: formatCompactCount(topic.commentsCount),
                        color: scheme.onSurfaceVariant,
                        background: Colors.transparent,
                        onTap: widget.onOpen,
                      ),
                      const Spacer(),
                      Text(
                        formatRelativeTime(
                          topic.createdAt ?? DateTime.now(),
                        ),
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Кто и откуда»: автор и, если строка стоит вне своего лобби, название
/// сообщества — тап по нему уводит туда, где обсуждение живёт.
class _Meta extends StatelessWidget {
  const _Meta({
    required this.topic,
    this.communityName,
    this.onOpenCommunity,
  });

  final ForumTopic topic;
  final String? communityName;
  final VoidCallback? onOpenCommunity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final author = topic.author;
    final community = communityName;

    return Row(
      children: [
        CosmeticAvatar(
          frame: cosmeticById(author.equipped.avatarFrame),
          radius: 10,
          avatarUrl: author.avatarUrl,
          placeholderColor: scheme.surfaceContainerHighest,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: CosmeticNameText(
              name: author.name,
              def: cosmeticById(author.equipped.nameStyle),
              maxLines: 1,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (author.isVerified) ...[
          const SizedBox(width: 3),
          Icon(Icons.verified_rounded, size: 12, color: scheme.primary),
        ],
        if (community != null) ...[
          Text(
            '  ·  ',
            style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onOpenCommunity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.group_work_rounded,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        community,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TopicTag extends StatelessWidget {
  const _TopicTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$label',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Превью вложений: три плитки и «+N» вместо бесконечной ленты картинок.
class _MediaStrip extends StatelessWidget {
  const _MediaStrip({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = urls.take(3).toList();
    final rest = urls.length - shown.length;

    return Row(
      children: [
        for (final (index, url) in shown.indexed) ...[
          if (index > 0) const SizedBox(width: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 62,
              height: 62,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 62,
                height: 62,
                color: scheme.surfaceContainerHighest,
              ),
              errorWidget: (_, _, _) => Container(
                width: 62,
                height: 62,
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              trf('и ещё {rest}', {'rest': rest}),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
    this.animateIcon = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;
  final bool animateIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: animateIcon ? 1.35 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
