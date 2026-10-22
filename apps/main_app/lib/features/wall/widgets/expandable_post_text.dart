import 'package:flutter/material.dart';
import 'package:canvas_app/shared/entity_links/entity_ref_card.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/app_markdown_config.dart';

class ExpandablePostText extends StatefulWidget {
  final String text;
  final int maxLines;

  const ExpandablePostText({
    super.key,
    required this.text,
    this.maxLines = 10,
  });

  @override
  State<ExpandablePostText> createState() => _ExpandablePostTextState();
}

class _ExpandablePostTextState extends State<ExpandablePostText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(
          text: widget.text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.45,
                fontSize: 14,
              ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final isOverflowing = textPainter.didExceedMaxLines;

        final markdownConfig = AppMarkdown.getConfig(context);

        if (!isOverflowing || _isExpanded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MeanderEntityMarkdown(data: widget.text, config: markdownConfig),
              if (_isExpanded)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _isExpanded = false),
                    child: Text(
                      tr('Свернуть'),
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: textPainter.size.height,
                  child: ClipRect(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: MeanderEntityMarkdown(
                        data: widget.text,
                        config: markdownConfig,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.surfaceContainerHigh.withOpacity(0.0),
                          scheme.surfaceContainerHigh.withOpacity(0.9),
                          scheme.surfaceContainerHigh,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () => setState(() => _isExpanded = true),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  tr('Читать далее...'),
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
