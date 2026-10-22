import 'package:canvas_app/core/services/deep_link_service.dart';
import 'package:canvas_app/shared/entity_links/meander_entity.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

class AppMarkdown {
  /// Тап по ссылке внутри текста. Без этого markdown-виджет любой адрес отдаёт
  /// системному viewer — и человек уезжает в браузер за квестом, который уже
  /// открыт в этом же приложении.
  static void openLink(String url) {
    if (pointsToMeander(url)) {
      DeepLinkService().openUrl(url);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static MarkdownConfig getConfig(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MarkdownConfig(
      configs: [
        PConfig(
          textStyle:
              textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                height: 1.45,
                fontSize: 14.5,
              ) ??
              TextStyle(color: scheme.onSurface, fontSize: 14.5, height: 1.45),
        ),
        CodeConfig(
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: scheme.onSecondaryContainer,
            backgroundColor: scheme.secondaryContainer.withOpacity(0.5),
          ),
        ),
        PreConfig(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: scheme.onSurface,
          ),
        ),
        BlockquoteConfig(
          textColor: scheme.onSurfaceVariant,
          sideColor: scheme.primary,
          sideWith: 3.0,
          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          margin: const EdgeInsets.symmetric(vertical: 8),
        ),
        LinkConfig(
          style: TextStyle(
            color: scheme.primary,
            decoration: TextDecoration.underline,
          ),
          onTap: openLink,
        ),
        ListConfig(
          marker: (isOrdered, depth, index) {
            if (isOrdered) {
              return Text(
                '${index + 1}. ',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: Icon(
                Icons.circle,
                size: 6,
                color: scheme.onSurfaceVariant,
              ),
            );
          },
          marginBottom: 4,
          marginLeft: 16,
        ),
        CheckBoxConfig(
          builder: (checked) => Padding(
            padding: const EdgeInsets.only(top: 2, right: 4),
            child: Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: scheme.onSurface,
            ),
          ),
        ),
        ImgConfig(
          builder: (url, attributes) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (_, __) => Container(
                    height: 200,
                    color: scheme.surfaceContainerHighest,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 100,
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
