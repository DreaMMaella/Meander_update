import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/wall/screens/create_post_screen.dart';

/// M3-кнопка создания поста (перекидывает на отдельный экран)
class PostComposer extends ConsumerWidget {
  final String authorId;
  final String? authorAvatarUrl;
  final String? authorName;

  /// Экипировка автора: в собственном блоке ввода видна та же рамка аватара,
  /// что и в шапке профиля.
  final EquippedCosmetics authorCosmetics;

  const PostComposer({
    super.key,
    required this.authorId,
    this.authorAvatarUrl,
    this.authorName,
    this.authorCosmetics = EquippedCosmetics.none,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CreatePostScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                CosmeticAvatar(
                  frame: cosmeticById(authorCosmetics.avatarFrame),
                  radius: 18,
                  avatarUrl: authorAvatarUrl,
                  placeholderColor: scheme.primaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tr('Что у вас нового?'),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.image_outlined, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
