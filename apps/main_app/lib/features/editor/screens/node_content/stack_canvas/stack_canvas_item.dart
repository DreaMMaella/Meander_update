import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:canvas_app/shared/canvas/canvas_item.dart';
import 'package:mnd_core/models/content_item.dart';

/// Адаптер: ContentItem → CanvasItem для бесконечного канваса.
///
/// Стек имеет фиксированную ширину (720) и заданную высоту.
/// Дочерние ContentItem'ы позиционируются якорной моделью (Godot)
/// и отображаются на канвасе как элементы.
class StackCanvasItem extends CanvasItem {
  final ContentItem contentItem;

  /// Мировая позиция элемента на канвасе (центр).
  final Offset _position;

  /// Размер превью элемента на канвасе (не реальный размер контента).
  final Size _size;

  /// Порядковый индекс в стеке (для z-order).
  final int stackIndex;

  StackCanvasItem({
    required this.contentItem,
    required Offset position,
    required Size size,
    this.stackIndex = 0,
  })  : _position = position,
        _size = size;

  @override
  String get id => contentItem.id;

  @override
  Offset get position => _position;

  @override
  Size get size => _size;

  @override
  Color get color {
    // Цвет по типу элемента — для визуальной дифференциации.
    switch (contentItem.type) {
      case 'text':
        return const Color(0xFF7FCFB6); // teal
      case 'image':
        return const Color(0xFF8FB6E0); // blue
      case 'button':
      case 'button_jump':
        return const Color(0xFFB39DDB); // violet
      case 'audio':
        return const Color(0xFFD79BC0); // pink
      case 'row':
      case 'column':
        return const Color(0xFFE0C46C); // amber
      case 'modal':
        return const Color(0xFFE49592); // red
      case 'plugin':
        return const Color(0xFF7C9CD6); // blue
      default:
        return const Color(0xFF9AA0A6); // grey
    }
  }

  @override
  String get label => _typeLabel(contentItem.type);

  /// Конвертировать ContentItem (якорная модель) → StackCanvasItem
  /// с вычисленной позицией на канвасе.
  ///
  /// [stackWidth] — ширина стека (720).
  /// [stackHeight] — высота стека.
  /// [stackPosition] — мировая позиция левого верхнего угла стека на канвасе.
  static StackCanvasItem fromContentItem({
    required ContentItem item,
    required int index,
    required double stackWidth,
    required double stackHeight,
    required Offset stackPosition,
  }) {
    // Rect ребёнка внутри стека (якорная модель Godot).
    final childRect = item.stackChildRect(stackWidth, stackHeight);

    // Позиция на канвасе: stackPosition + center(childRect).
    final worldPos = stackPosition + childRect.center;

    // Размер на канвасе = реальный размер якорной области.
    // Это гарантирует, что текст/контент отображаются в правильных
    // пропорциях, как в GameStackWidget.
    final itemSize = Size(
      childRect.width.clamp(20.0, stackWidth),
      childRect.height.clamp(12.0, stackHeight),
    );

    return StackCanvasItem(
      contentItem: item,
      position: worldPos,
      size: itemSize,
      stackIndex: index,
    );
  }

  /// Обновить позицию (при drag на канвасе).
  StackCanvasItem copyWithPosition(Offset newPosition) {
    return StackCanvasItem(
      contentItem: contentItem,
      position: newPosition,
      size: _size,
      stackIndex: stackIndex,
    );
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'text':
        return tr('Текст');
      case 'image':
        return tr('Изображение');
      case 'button':
      case 'button_jump':
        return tr('Кнопка');
      case 'input':
        return tr('Поле ввода');
      case 'audio':
        return tr('Аудио');
      case 'row':
        return tr('Ряд');
      case 'column':
        return tr('Колонка');
      case 'modal':
        return tr('Окно');
      case 'plugin':
        return tr('Плагин');
      default:
        return type;
    }
  }
}
