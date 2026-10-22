import 'dart:ui';

enum DisplayObjectType {
  rect,
  circle,
  line,
  polygon,
  text,
  image,
  group,
  custom,
}

class DisplayObject {
  final String id;
  final DisplayObjectType type;
  String? _parentId;
  String? get parentId => _parentId;
  set parentId(String? value) => _parentId = value;

  double x = 0;
  double y = 0;
  double rotation = 0;
  double scaleX = 1;
  double scaleY = 1;
  double alpha = 1;
  bool isVisible = true;
  bool isTouchEnabled = true;

  Color? fillColor;
  Color? strokeColor;
  double strokeWidth = 0;

  double width = 0;
  double height = 0;
  double radius = 0;

  String? text;
  double fontSize = 16;
  Color? textColor;
  String fontFamily = 'sans-serif';
  TextAlign textAlign = TextAlign.left;

  String? imagePath;
  String? imageDataBase64;

  List<Offset> points = [];
  List<Offset> polygonPoints = [];

  final List<String> children = [];

  Map<String, dynamic> userData = {};
  Map<String, Function> eventListeners = {};

  DisplayObject({
    required this.id,
    required this.type,
    String? parentId,
  }) : _parentId = parentId;

  bool containsPoint(double px, double py) {
    final dx = px - x;
    final dy = py - y;

    switch (type) {
      case DisplayObjectType.rect:
        return dx >= -width / 2 &&
            dx <= width / 2 &&
            dy >= -height / 2 &&
            dy <= height / 2;
      case DisplayObjectType.circle:
        return (dx * dx + dy * dy) <= (radius * radius);
      case DisplayObjectType.text:
        final textWidth = (text?.length ?? 0) * fontSize * 0.6;
        final textHeight = fontSize * 1.2;
        return dx >= -textWidth / 2 &&
            dx <= textWidth / 2 &&
            dy >= -textHeight / 2 &&
            dy <= textHeight / 2;
      case DisplayObjectType.image:
        return dx >= -width / 2 &&
            dx <= width / 2 &&
            dy >= -height / 2 &&
            dy <= height / 2;
      case DisplayObjectType.line:
        return _lineContainsPoint(px, py);
      case DisplayObjectType.polygon:
        return _polygonContainsPoint(px, py);
      default:
        return false;
    }
  }

  bool _lineContainsPoint(double px, double py) {
    if (points.length < 2) return false;
    final p1 = points[0];
    final p2 = points[1];
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final lengthSq = dx * dx + dy * dy;
    if (lengthSq == 0) return false;
    final t = ((px - p1.dx) * dx + (py - p1.dy) * dy) / lengthSq;
    if (t < -0.1 || t > 1.1) return false;
    final dist = ((px - (p1.dx + t * dx)).abs() + (py - (p1.dy + t * dy)).abs());
    return dist < (strokeWidth / 2 + 5);
  }

  bool _polygonContainsPoint(double px, double py) {
    if (polygonPoints.length < 3) return false;
    var inside = false;
    for (int i = 0, j = polygonPoints.length - 1; i < polygonPoints.length; j = i++) {
      final xi = polygonPoints[i].dx;
      final yi = polygonPoints[i].dy;
      final xj = polygonPoints[j].dx;
      final yj = polygonPoints[j].dy;
      final intersect = ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  DisplayObject copy() {
    final copy = DisplayObject(id: id, type: type, parentId: parentId);
    copy.x = x;
    copy.y = y;
    copy.rotation = rotation;
    copy.scaleX = scaleX;
    copy.scaleY = scaleY;
    copy.alpha = alpha;
    copy.isVisible = isVisible;
    copy.isTouchEnabled = isTouchEnabled;
    copy.fillColor = fillColor;
    copy.strokeColor = strokeColor;
    copy.strokeWidth = strokeWidth;
    copy.width = width;
    copy.height = height;
    copy.radius = radius;
    copy.text = text;
    copy.fontSize = fontSize;
    copy.textColor = textColor;
    copy.fontFamily = fontFamily;
    copy.textAlign = textAlign;
    copy.imagePath = imagePath;
    copy.imageDataBase64 = imageDataBase64;
    copy.points = List.from(points);
    copy.polygonPoints = List.from(polygonPoints);
    copy.children.addAll(children);
    copy.userData = Map.from(userData);
    copy.eventListeners = Map.from(eventListeners);
    return copy;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'x': x,
      'y': y,
      'rotation': rotation,
      'scaleX': scaleX,
      'scaleY': scaleY,
      'alpha': alpha,
      'isVisible': isVisible,
      'width': width,
      'height': height,
      'radius': radius,
      'text': text,
      'fontSize': fontSize,
      'fillColor': fillColor?.value.toRadixString(16),
      'strokeColor': strokeColor?.value.toRadixString(16),
      'strokeWidth': strokeWidth,
    };
  }
}

class DisplayScene {
  final String id;
  final String pluginId;
  final List<DisplayObject> objects = [];
  final Map<String, DisplayObject> objectMap = {};
  double width = 0;
  double height = 0;
  Color? backgroundColor;
  bool isPaused = false;

  DisplayScene({required this.id, required this.pluginId});

  DisplayObject? getById(String id) => objectMap[id];

  void addObject(DisplayObject obj) {
    objects.add(obj);
    objectMap[obj.id] = obj;
  }

  void removeObject(String id) {
    final obj = objectMap.remove(id);
    if (obj != null) {
      objects.remove(obj);
      if (obj.parentId != null) {
        final parent = objectMap[obj.parentId];
        parent?.children.remove(id);
      }
    }
  }

  void clear() {
    objects.clear();
    objectMap.clear();
  }

  DisplayObject? hitTest(double x, double y) {
    for (int i = objects.length - 1; i >= 0; i--) {
      final obj = objects[i];
      if (!obj.isVisible || !obj.isTouchEnabled) continue;
      if (obj.containsPoint(x, y)) return obj;
    }
    return null;
  }
}
