import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Части rect'а слоя: координаты левого верха и размер.
enum StackRectPart { x, y, w, h }

/// Поля геометрии выделенного слоя.
///
/// Точные координаты нужны при вёрстке на каждом шаге, а модалка свойств
/// закрывает холст: значение набираешь вслепую, потом закрываешь и смотришь,
/// куда слой встал. Здесь то же самое поле живёт в строке статуса — canvas
/// виден всё время набора.
class StackRectFields extends StatefulWidget {
  const StackRectFields({
    super.key,
    required this.childId,
    required this.rect,
    required this.scheme,
    required this.onChanged,
  });

  final String childId;

  /// Rect слоя на сейчас: во время драга — из предпросмотра жеста.
  final Rect rect;
  final ColorScheme scheme;
  final void Function(StackRectPart part, double value) onChanged;

  @override
  State<StackRectFields> createState() => _StackRectFieldsState();
}

class _StackRectFieldsState extends State<StackRectFields> {
  late final Map<StackRectPart, TextEditingController> _controllers;
  late final Map<StackRectPart, FocusNode> _nodes;

  static const Map<StackRectPart, String> _labels = {
    StackRectPart.x: 'X',
    StackRectPart.y: 'Y',
    StackRectPart.w: 'W',
    StackRectPart.h: 'H',
  };

  static double _valueOf(StackRectPart part, Rect rect) => switch (part) {
    StackRectPart.x => rect.left,
    StackRectPart.y => rect.top,
    StackRectPart.w => rect.width,
    StackRectPart.h => rect.height,
  };

  String _text(StackRectPart part) =>
      _valueOf(part, widget.rect).round().toString();

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final part in StackRectPart.values)
        part: TextEditingController(text: _text(part)),
    };
    _nodes = {
      for (final part in StackRectPart.values)
        part: FocusNode(debugLabel: 'stack_rect_${part.name}'),
    };
    // Потеря фокуса — тоже ввод: ушли в соседнее поле без Enter.
    for (final part in StackRectPart.values) {
      final node = _nodes[part]!;
      node.addListener(() {
        if (!node.hasFocus) _commit(part);
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StackRectFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final part in StackRectPart.values) {
      // Поле, в котором печатают, не перетираем: иначе движение мышью по
      // канвасу стёрло бы уже набранное. Смена слоя — перетираем, там своё.
      if (_nodes[part]!.hasFocus && widget.childId == oldWidget.childId) {
        continue;
      }
      final text = _text(part);
      if (_controllers[part]!.text != text) _controllers[part]!.text = text;
    }
  }

  /// Одно поле правит свою сторону rect'а; пустой ввод откатываем показом
  /// фактического значения, а не молча оставляем мусор в документе.
  void _commit(StackRectPart part) {
    final controller = _controllers[part]!;
    final raw = double.tryParse(controller.text.replaceAll(',', '.'));
    if (raw == null) {
      controller.text = _text(part);
      return;
    }
    widget.onChanged(part, raw);
    // После округления и clamp в поле должно остаться то, что попало в файл.
    // Родитель перерисует с новым rect'ом — если же правки не было (значение
    // уже стояло), чиним сами на следующем кадре.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _nodes[part]!.hasFocus) return;
      final text = _text(part);
      if (_controllers[part]!.text != text) _controllers[part]!.text = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final part in StackRectPart.values) _field(part)],
    );
  }

  Widget _field(StackRectPart part) {
    final scheme = widget.scheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: SizedBox(
        width: 62,
        child: TextField(
          key: ValueKey('rect_field_${part.name}'),
          controller: _controllers[part]!,
          focusNode: _nodes[part]!,
          textAlign: TextAlign.end,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
          ],
          style: TextStyle(color: scheme.onSurface, fontSize: 12),
          onSubmitted: (_) => _commit(part),
          decoration: InputDecoration(
            isDense: true,
            labelText: _labels[part],
            labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 7,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}
