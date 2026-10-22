class PluginPolicy {
  static const Set<String> allowedPermissions = {
    'ui',
    'quest',
    'storage',
    'audio',
    'network',
    'events',
  };

  static final Map<String, PluginSlotRule> _slotRules = {
    'market.header': const PluginSlotRule(maxWidgets: 2, maxTextLength: 140),
    'market.quest_card.footer':
        const PluginSlotRule(maxWidgets: 1, maxTextLength: 60),
    'profile.header': const PluginSlotRule(maxWidgets: 2, maxTextLength: 140),
    'quest.header': const PluginSlotRule(maxWidgets: 2, maxTextLength: 120),
    'quest.footer': const PluginSlotRule(maxWidgets: 1, maxTextLength: 80),
    'game.inventory': const PluginSlotRule(maxWidgets: 3, maxTextLength: 100),
  };

  static Map<String, PluginSlotRule> get slotRules =>
      Map.unmodifiable(_slotRules);

  static PluginSlotRule? slotRule(String slotId) {
    return _slotRules[slotId];
  }

  static bool registerSlot(
    String slotId, {
    int maxWidgets = 2,
    int maxTextLength = 140,
  }) {
    if (_slotRules.containsKey(slotId)) {
      return false;
    }
    _slotRules[slotId] = PluginSlotRule(
      maxWidgets: maxWidgets,
      maxTextLength: maxTextLength,
    );
    return true;
  }

  static bool unregisterSlot(String slotId) {
    return _slotRules.remove(slotId) != null;
  }

  static PermissionValidation validatePermissions(List<String> permissions) {
    final normalized =
        permissions.map((p) => p.trim()).where((p) => p.isNotEmpty);
    final valid = <String>[];
    final invalid = <String>[];
    for (final permission in normalized) {
      if (allowedPermissions.contains(permission)) {
        valid.add(permission);
      } else {
        invalid.add(permission);
      }
    }
    return PermissionValidation(valid: valid, invalid: invalid);
  }
}

class PermissionValidation {
  final List<String> valid;
  final List<String> invalid;

  const PermissionValidation({required this.valid, required this.invalid});

  bool get hasInvalid => invalid.isNotEmpty;
}

class PluginSlotRule {
  final int maxWidgets;
  final int maxTextLength;

  const PluginSlotRule({
    required this.maxWidgets,
    required this.maxTextLength,
  });
}
