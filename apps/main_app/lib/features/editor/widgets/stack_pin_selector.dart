import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Выбор позиции стека на экране. Общий для листа контента и канваса:
/// значение живёт в `stackPin`, и редактор обязан показывать те же края, что
/// понимает плеер.
class StackPinSelector extends StatelessWidget {
  const StackPinSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  static List<(String, String, IconData)> get _options => [
    ('', tr('В потоке'), Icons.swap_vert),
    ('top', tr('Сверху'), Icons.vertical_align_top),
    ('bottom', tr('Снизу'), Icons.vertical_align_bottom),
    ('left', tr('Слева'), Icons.align_horizontal_left),
    ('right', tr('Справа'), Icons.align_horizontal_right),
    ('center', tr('Центр'), Icons.center_focus_strong),
    ('fill', tr('Экран'), Icons.fullscreen),
    ('custom', tr('Рамка'), Icons.grid_view),
  ];

  static String label(String? pin) => switch (pin) {
    'top' => tr('сверху'),
    'bottom' => tr('снизу'),
    'left' => tr('у левого края'),
    'right' => tr('у правого края'),
    'fill' => tr('на весь экран'),
    'custom' => tr('в своей рамке'),
    'center' => tr('по центру'),
    _ => tr('в потоке'),
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final (pin, label, icon) in _options)
            ButtonSegment(
              value: pin,
              label: Text(label),
              icon: Icon(icon, size: 18),
            ),
        ],
        selected: {value ?? ''},
        onSelectionChanged: (selection) {
          final next = selection.first;
          onChanged(next.isEmpty ? null : next);
        },
      ),
    );
  }
}
