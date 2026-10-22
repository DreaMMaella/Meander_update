import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/plugin_host/plugin_ui_spec.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PluginScreen extends StatelessWidget {
  final PluginScreenSpec spec;
  final String? questId;
  final String pluginId;
  final void Function(String callbackId)? onCallback;

  const PluginScreen({
    super.key,
    required this.spec,
    required this.pluginId,
    this.questId,
    this.onCallback,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        title: Text(
          spec.title,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final widget = spec.widgets[index];
          return _buildWidget(context, widget);
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: spec.widgets.length,
      ),
    );
  }

  Widget _buildWidget(BuildContext context, PluginWidgetSpec widget) {
    switch (widget.type) {
      case PluginWidgetType.text:
        return Text(
          widget.resolveText(questId) ?? '',
          style: GoogleFonts.manrope(fontSize: 16, color: Colors.white),
        );
      case PluginWidgetType.button:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _handleButton(context, widget),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C853),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(widget.resolveText(questId) ?? 'OK'),
          ),
        );
      case PluginWidgetType.spacer:
        return SizedBox(height: widget.spacerHeight ?? 12);
    }
  }

  void _handleButton(BuildContext context, PluginWidgetSpec widget) {
    if (widget.callbackId != null) {
      onCallback?.call(widget.callbackId!);
    }
    if (widget.action == PluginButtonAction.pop) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Действие кнопки ещё не реализовано')),
        backgroundColor: Color(0xFF2A2A2A),
      ),
    );
  }
}
