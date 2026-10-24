import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/services/display_refresh_rate.dart';
import 'package:flutter/material.dart';

/// Переключатель высокой частоты обновления экрана. Скрывается целиком,
/// если экран умеет только 60 Гц или платформа не Android.
class RefreshRateCard extends StatefulWidget {
  const RefreshRateCard({super.key});

  @override
  State<RefreshRateCard> createState() => _RefreshRateCardState();
}

class _RefreshRateCardState extends State<RefreshRateCard> {
  late final Future<DisplayRefreshInfo?> _initial = DisplayRefreshRate.info();
  bool? _enabled;

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await DisplayRefreshRate.setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DisplayRefreshInfo?>(
      future: _initial,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null || !info.supportsHighRate) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final enabled = _enabled ?? info.enabled;
        final hz = info.max.round();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: const Icon(Icons.speed_rounded),
              title: Text(trf('Плавность {p0} Гц', {'p0': hz})),
              subtitle: Text(
                enabled
                    ? tr('Максимальная частота экрана для анимаций и прокрутки')
                    : tr('Стандартная частота — экономит заряд батареи'),
              ),
              value: enabled,
              onChanged: _toggle,
            ),
          ),
        );
      },
    );
  }
}
