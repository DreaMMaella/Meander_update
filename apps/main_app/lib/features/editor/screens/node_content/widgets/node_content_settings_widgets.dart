import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

class TimerSettingsWidget extends StatelessWidget {
  final bool isEnabled;
  final ValueChanged<bool> onToggle;
  final TextEditingController controller;
  final VoidCallback onSelectDefaultAction;
  final String defaultActionNodeName;
  final bool isHidden;
  final ValueChanged<bool> onToggleHidden;

  const TimerSettingsWidget({
    super.key,
    required this.isEnabled,
    required this.onToggle,
    required this.controller,
    required this.onSelectDefaultAction,
    required this.defaultActionNodeName,
    this.isHidden = false,
    this.onToggleHidden = _noopBool,
  });

  static void _noopBool(bool _) {}

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.timer_outlined,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('Таймер выбора'),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Switch(value: isEnabled, onChanged: onToggle),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: TextStyle(color: scheme.onSurface),
              cursorColor: scheme.primary,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Время (сек)'),
                labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(
                  Icons.access_time,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onSelectDefaultAction,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.call_missed_outgoing,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Действие по умолчанию:'),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              defaultActionNodeName,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: scheme.onSurfaceVariant,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: SwitchListTile(
                value: isHidden,
                onChanged: onToggleHidden,
                title: Text(
                  tr('Скрыть таймер'),
                  style: TextStyle(color: scheme.onSurface, fontSize: 14),
                ),
                subtitle: Text(
                  tr('Таймер сработает, но без отсчёта'),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                secondary: Icon(Icons.visibility_off_outlined, color: scheme.onSurfaceVariant),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ResourceSelectorWidget extends StatelessWidget {
  final String label;
  final String? selectedResourceName;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const ResourceSelectorWidget({
    super.key,
    required this.label,
    required this.selectedResourceName,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.image_outlined,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedResourceName ?? tr('Не выбрано'),
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (selectedResourceName != null)
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: onClear,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
