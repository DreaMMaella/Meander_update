import 'package:canvas_app/plugin_host/plugin_slot_provider.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/plugin_host/plugin_ui_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class PluginSlotRenderer extends ConsumerWidget {
  final String slotId;
  final double? maxHeight;
  final Map<String, String>? slotContext;

  const PluginSlotRenderer({
    super.key,
    required this.slotId,
    this.maxHeight,
    this.slotContext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(pluginSlotWidgetsProvider(slotId));
    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: widgets
          .map((spec) => _buildWidget(spec, slotContext))
          .toList(),
    );

    if (maxHeight == null) {
      return content;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight!),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: content,
        ),
      ),
    );
  }

  Widget _buildWidget(PluginWidgetSpec spec, Map<String, String>? context) {
    final resolvedText = resolveText(spec.text, context);
    try {
      switch (spec.type) {
        case PluginWidgetType.text:
          if (resolvedText.trim().isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              resolvedText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          );
        case PluginWidgetType.button:
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
              ),
              child: Text(resolvedText.isEmpty ? 'OK' : resolvedText),
            ),
          );
        case PluginWidgetType.spacer:
          return SizedBox(height: spec.spacerHeight ?? 8);
      }
    } catch (_) {
      return _errorPlaceholder();
    }
  }

  String _resolveText(String? input, Map<String, String>? context) {
    return resolveText(input, context);
  }

  static String resolveText(String? input, Map<String, String>? context) {
    if (input == null || input.isEmpty) {
      return '';
    }
    if (context == null || context.isEmpty) {
      return input;
    }
    return input.replaceAllMapped(
      RegExp(r'\{([A-Za-z0-9_.-]+)\}'),
      (match) => context[match.group(1)] ?? '',
    );
  }

  static bool hasRenderableContent(
    List<PluginWidgetSpec> specs,
    Map<String, String>? context,
  ) {
    for (final spec in specs) {
      switch (spec.type) {
        case PluginWidgetType.text:
          if (resolveText(spec.text, context).trim().isNotEmpty) {
            return true;
          }
          break;
        case PluginWidgetType.button:
          return true;
        case PluginWidgetType.spacer:
          break;
      }
    }
    return false;
  }

  Widget _errorPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.extension_off, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Text(
            tr('Слот плагина с ошибкой'),
            style: GoogleFonts.manrope(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
