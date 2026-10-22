import 'dart:ui';

// ================================================================
// Абстрактный элемент бесконечного канваса.
// Подклассы: Node (canvas нод), StackCanvasItem (стек), и т.д.
// ================================================================

/// Любой элемент, который можно разместить на бесконечном канвасе.
/// Определяет позицию, размер и rect — всё, что нужно
/// SpatialHash и рендеру.
abstract class CanvasItem {
  /// Уникальный идентификатор элемента.
  String get id;

  /// Центральная позиция элемента в мировых координатах.
  Offset get position;

  /// Размер элемента в мировых координатах.
  Size get size;

  /// Прямоугольник элемента (position ± size/2).
  Rect get rect => Rect.fromCenter(
        center: position,
        width: size.width,
        height: size.height,
      );

  /// Цвет элемента (для выделения, бордюров и т.д.).
  Color get color;

  /// Метка / название элемента.
  String get label;
}

// ================================================================
// Generic SpatialHash — пространственный хеш для быстрого
// hit-testing и видимости элементов на бесконечном канвасе.
// ================================================================

/// Пространственный хеш для элементов канваса.
/// Элементы распределяются по ячейкам фиксированного размера,
/// что даёт O(1) для point-запросов и видимости.
class CanvasSpatialHash<T extends CanvasItem> {
  final double cellSize;
  final Map<String, Set<T>> _grid = {};

  CanvasSpatialHash({this.cellSize = 200});

  String _getKey(int x, int y) => '$x,$y';

  void clear() => _grid.clear();

  void insert(T item) {
    final rect = item.rect;
    final minX = (rect.left / cellSize).floor();
    final minY = (rect.top / cellSize).floor();
    final maxX = (rect.right / cellSize).floor();
    final maxY = (rect.bottom / cellSize).floor();
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        final key = _getKey(x, y);
        _grid.putIfAbsent(key, () => {}).add(item);
      }
    }
  }

  /// Найти элемент, содержащий данную точку.
  T? queryPoint(Offset point) {
    final x = (point.dx / cellSize).floor();
    final y = (point.dy / cellSize).floor();
    final cells = _grid[_getKey(x, y)];
    if (cells != null) {
      for (final item in cells.toList().reversed) {
        if (item.rect.contains(point)) return item;
      }
    }
    return null;
  }

  /// Перестроить хеш из списка элементов.
  void rebuild(List<T> items) {
    clear();
    for (final item in items) {
      insert(item);
    }
  }

  /// Найти все элементы, пересекающиеся с rect.
  Set<T> query(Rect rect) {
    final result = <T>{};
    final minX = (rect.left / cellSize).floor();
    final minY = (rect.top / cellSize).floor();
    final maxX = (rect.right / cellSize).floor();
    final maxY = (rect.bottom / cellSize).floor();
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        final cells = _grid[_getKey(x, y)];
        if (cells != null) {
          result.addAll(cells);
        }
      }
    }
    return result;
  }

  /// Количество элементов в хеше.
  int get length => _grid.values.fold(0, (sum, s) => sum + s.length);
}
