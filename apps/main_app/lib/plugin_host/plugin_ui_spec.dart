enum PluginWidgetType { text, button, spacer }

enum PluginButtonAction { none, pop }

class PluginWidgetSpec {
  final PluginWidgetType type;
  final String? text;
  final bool appendQuestId;
  final PluginButtonAction action;
  final double? spacerHeight;
  final String? callbackId;

  const PluginWidgetSpec({
    required this.type,
    this.text,
    this.appendQuestId = false,
    this.action = PluginButtonAction.none,
    this.spacerHeight,
    this.callbackId,
  });

  String? resolveText(String? questId) {
    if (text == null) return null;
    if (!appendQuestId || questId == null) return text;
    return '${text!}$questId';
  }
}

class PluginScreenSpec {
  final String title;
  final List<PluginWidgetSpec> widgets;

  const PluginScreenSpec({required this.title, required this.widgets});
}
