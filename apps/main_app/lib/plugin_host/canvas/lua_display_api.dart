import 'dart:ui';

import 'package:canvas_app/plugin_host/canvas/display_object.dart';
import 'package:lua_dardo/lua.dart';

typedef LuaRuntimeLog = void Function(String message);
typedef CanvasStateRef = dynamic;

class LuaDisplayAPI {
  final LuaRuntimeLog log;
  final DisplayScene scene;
  final CanvasStateRef? canvasState;
  int _objSeq = 0;
  final Map<int, DisplayObject> _objectRefs = {};
  int _refSeq = 0;

  LuaDisplayAPI({
    required this.log,
    required this.scene,
    this.canvasState,
  });

  void register(LuaState state) {
    _registerDisplayTable(state);
    _registerGraphicsTable(state);
    _registerTransitionTable(state);
    _registerTimerTable(state);
  }

  void _registerDisplayTable(LuaState state) {
    state.newTable();
    _registerDisplayFunctions(state);
    state.setGlobal('display');
  }

  void _registerDisplayFunctions(LuaState state) {
    state.pushString('newRect');
    state.pushDartFunction((ls) => _newRect(ls));
    state.setTable(-3);

    state.pushString('newCircle');
    state.pushDartFunction((ls) => _newCircle(ls));
    state.setTable(-3);

    state.pushString('newLine');
    state.pushDartFunction((ls) => _newLine(ls));
    state.setTable(-3);

    state.pushString('newPolygon');
    state.pushDartFunction((ls) => _newPolygon(ls));
    state.setTable(-3);

    state.pushString('newText');
    state.pushDartFunction((ls) => _newText(ls));
    state.setTable(-3);

    state.pushString('newImage');
    state.pushDartFunction((ls) => _newImage(ls));
    state.setTable(-3);

    state.pushString('newGroup');
    state.pushDartFunction((ls) => _newGroup(ls));
    state.setTable(-3);

    state.pushString('remove');
    state.pushDartFunction((ls) => _remove(ls));
    state.setTable(-3);

    state.pushString('getBounds');
    state.pushDartFunction((ls) => _getBounds(ls));
    state.setTable(-3);
  }

  int _newRect(LuaState ls) {
    final x = ls.optNumber(1, 0) ?? 0;
    final y = ls.optNumber(2, 0) ?? 0;
    final width = ls.optNumber(3, 100) ?? 100;
    final height = ls.optNumber(4, 100) ?? 100;

    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.rect)
      ..x = x
      ..y = y
      ..width = width
      ..height = height
      ..fillColor = const Color(0xFFFFFFFF);

    scene.addObject(obj);
    log('[display] newRect($x, $y, $width, $height) -> $id');
    _pushDisplayObject(ls, obj);
    return 1;
  }

  int _newCircle(LuaState ls) {
    final x = ls.optNumber(1, 0) ?? 0;
    final y = ls.optNumber(2, 0) ?? 0;
    final radius = ls.optNumber(3, 50) ?? 50;

    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.circle)
      ..x = x
      ..y = y
      ..radius = radius
      ..fillColor = const Color(0xFFFFFFFF);

    scene.addObject(obj);
    log('[display] newCircle($x, $y, $radius) -> $id');
    _pushDisplayObject(ls, obj);
    return 1;
  }

  int _newLine(LuaState ls) {
    final x1 = ls.optNumber(1, 0) ?? 0;
    final y1 = ls.optNumber(2, 0) ?? 0;
    final x2 = ls.optNumber(3, 100) ?? 100;
    final y2 = ls.optNumber(4, 100) ?? 100;

    final centerX = (x1 + x2) / 2;
    final centerY = (y1 + y2) / 2;

    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.line)
      ..x = centerX
      ..y = centerY
      ..points = [Offset(x1 - centerX, y1 - centerY), Offset(x2 - centerX, y2 - centerY)]
      ..strokeColor = const Color(0xFFFFFFFF)
      ..strokeWidth = 2;

    scene.addObject(obj);
    log('[display] newLine($x1, $y1, $x2, $y2) -> $id');
    _pushDisplayObject(ls, obj);
    return 1;
  }

  int _newPolygon(LuaState ls) {
    final points = <Offset>[];
    var i = 1;
    while (ls.type(i) == LuaType.luaNumber) {
      final x = ls.toNumber(i) ?? 0;
      final y = ls.toNumber(i + 1) ?? 0;
      points.add(Offset(x, y));
      i += 2;
    }

    if (points.isEmpty) {
      ls.pushNil();
      return 1;
    }

    final centerX = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
    final centerY = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;

    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.polygon)
      ..x = centerX
      ..y = centerY
      ..polygonPoints = points.map((p) => Offset(p.dx - centerX, p.dy - centerY)).toList()
      ..fillColor = const Color(0xFFFFFFFF);

    scene.addObject(obj);
    log('[display] newPolygon(${points.length} points) -> $id');
    _pushDisplayObject(ls, obj);
    return 1;
  }

  int _newText(LuaState ls) {
    final text = ls.optString(1, '') ?? '';
    final x = ls.optNumber(2, 0) ?? 0;
    final y = ls.optNumber(3, 0) ?? 0;
    final fontSize = ls.optNumber(4, 16) ?? 16;

    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.text)
      ..x = x
      ..y = y
      ..text = text
      ..fontSize = fontSize
      ..textColor = const Color(0xFFFFFFFF);

    scene.addObject(obj);
    log('[display] newText("$text", $x, $y) -> $id');
    _pushDisplayObject(ls, obj);
    return 1;
  }

  int _newImage(LuaState ls) {
    final path = ls.optString(1, '') ?? '';
    final x = ls.optNumber(2, 0) ?? 0;
    final y = ls.optNumber(3, 0) ?? 0;
    final width = ls.optNumber(4, 100) ?? 100;
    final height = ls.optNumber(5, 100) ?? 100;

    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.image)
      ..x = x
      ..y = y
      ..width = width
      ..height = height
      ..imagePath = path;

    scene.addObject(obj);
    log('[display] newImage("$path", $x, $y) -> $id');
    _pushDisplayObject(ls, obj);
    return 1;
  }

  int _newGroup(LuaState ls) {
    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.group);

    scene.addObject(obj);
    log('[display] newGroup() -> $id');
    _pushDisplayObject(ls, obj);
    return 1;
  }

  int _remove(LuaState ls) {
    final obj = _getDisplayObject(ls, 1);
    if (obj != null) {
      scene.removeObject(obj.id);
      log('[display] remove(${obj.id})');
    }
    return 0;
  }

  int _getBounds(LuaState ls) {
    final obj = _getDisplayObject(ls, 1);
    if (obj == null) {
      ls.pushNil();
      return 1;
    }

    ls.newTable();
    ls.pushString('x');
    ls.pushNumber(obj.x - obj.width / 2);
    ls.setTable(-3);
    ls.pushString('y');
    ls.pushNumber(obj.y - obj.height / 2);
    ls.setTable(-3);
    ls.pushString('width');
    ls.pushNumber(obj.width);
    ls.setTable(-3);
    ls.pushString('height');
    ls.pushNumber(obj.height);
    ls.setTable(-3);
    return 1;
  }

  void _pushDisplayObject(LuaState ls, DisplayObject obj) {
    ls.newTable();

    ls.pushString('id');
    ls.pushString(obj.id);
    ls.setTable(-3);

    ls.pushString('x');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'x'));
    ls.setTable(-3);

    ls.pushString('y');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'y'));
    ls.setTable(-3);

    ls.pushString('rotation');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'rotation'));
    ls.setTable(-3);

    ls.pushString('alpha');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'alpha'));
    ls.setTable(-3);

    ls.pushString('scaleX');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'scaleX'));
    ls.setTable(-3);

    ls.pushString('scaleY');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'scaleY'));
    ls.setTable(-3);

    ls.pushString('isVisible');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'isVisible'));
    ls.setTable(-3);

    ls.pushString('width');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'width'));
    ls.setTable(-3);

    ls.pushString('height');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'height'));
    ls.setTable(-3);

    ls.pushString('radius');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'radius'));
    ls.setTable(-3);

    ls.pushString('text');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'text'));
    ls.setTable(-3);

    ls.pushString('fontSize');
    ls.pushDartFunction((inner) => _propGet(inner, obj, 'fontSize'));
    ls.setTable(-3);

    ls.pushString('removeSelf');
    ls.pushDartFunction((inner) => _removeSelf(inner, obj));
    ls.setTable(-3);

    ls.pushString('setFillColor');
    ls.pushDartFunction((inner) => _setFillColor(inner, obj));
    ls.setTable(-3);

    ls.pushString('setStrokeColor');
    ls.pushDartFunction((inner) => _setStrokeColor(inner, obj));
    ls.setTable(-3);

    ls.pushString('addEventListener');
    ls.pushDartFunction((inner) => _addEventListener(inner, obj));
    ls.setTable(-3);

    ls.pushString('insert');
    ls.pushDartFunction((inner) => _insertChild(inner, obj));
    ls.setTable(-3);

    ls.pushString('toFront');
    ls.pushDartFunction((inner) => _toFront(inner, obj));
    ls.setTable(-3);

    ls.pushString('toBack');
    ls.pushDartFunction((inner) => _toBack(inner, obj));
    ls.setTable(-3);

    final ref = _storeObject(obj);
    ls.pushString('__ref');
    ls.pushNumber(ref.toDouble());
    ls.setTable(-3);
  }

  int _storeObject(DisplayObject obj) {
    final ref = ++_refSeq;
    _objectRefs[ref] = obj;
    return ref;
  }

  DisplayObject? _getDisplayObject(LuaState ls, int index) {
    if (ls.type(index) == LuaType.luaTable) {
      ls.getField(index, '__ref');
      final ref = (ls.toNumber(-1) ?? 0).toInt();
      ls.pop(1);
      return _objectRefs[ref];
    }
    return null;
  }

  int _propGet(LuaState ls, DisplayObject obj, String prop) {
    if (ls.getTop() >= 2) {
      final value = ls.toNumber(2) ?? 0;
      switch (prop) {
        case 'x':
          obj.x = value;
          break;
        case 'y':
          obj.y = value;
          break;
        case 'rotation':
          obj.rotation = value;
          break;
        case 'alpha':
          obj.alpha = value.clamp(0.0, 1.0);
          break;
        case 'scaleX':
          obj.scaleX = value;
          break;
        case 'scaleY':
          obj.scaleY = value;
          break;
        case 'isVisible':
          obj.isVisible = value > 0;
          break;
        case 'width':
          obj.width = value;
          break;
        case 'height':
          obj.height = value;
          break;
        case 'radius':
          obj.radius = value;
          break;
        case 'text':
          obj.text = ls.toStr(2) ?? '';
          break;
        case 'fontSize':
          obj.fontSize = value;
          break;
      }
      return 0;
    }

    dynamic value;
    switch (prop) {
      case 'x':
        value = obj.x;
        break;
      case 'y':
        value = obj.y;
        break;
      case 'rotation':
        value = obj.rotation;
        break;
      case 'alpha':
        value = obj.alpha;
        break;
      case 'scaleX':
        value = obj.scaleX;
        break;
      case 'scaleY':
        value = obj.scaleY;
        break;
      case 'isVisible':
        value = obj.isVisible ? 1 : 0;
        break;
      case 'width':
        value = obj.width;
        break;
      case 'height':
        value = obj.height;
        break;
      case 'radius':
        value = obj.radius;
        break;
      case 'text':
        value = obj.text ?? '';
        break;
      case 'fontSize':
        value = obj.fontSize;
        break;
    }

    if (value is double) {
      ls.pushNumber(value);
    } else if (value is int) {
      ls.pushNumber(value.toDouble());
    } else if (value is String) {
      ls.pushString(value);
    } else if (value is bool) {
      ls.pushBoolean(value);
    } else {
      ls.pushNumber(0);
    }
    return 1;
  }

  int _removeSelf(LuaState ls, DisplayObject obj) {
    scene.removeObject(obj.id);
    log('[display] ${obj.id}:removeSelf()');
    return 0;
  }

  int _setFillColor(LuaState ls, DisplayObject obj) {
    final r = ((ls.optNumber(1, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final g = ((ls.optNumber(2, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final b = ((ls.optNumber(3, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final a = ls.getTop() >= 4
        ? ((ls.optNumber(4, 1) ?? 1) * 255).toInt().clamp(0, 255)
        : 255;
    obj.fillColor = Color.fromARGB(a, r, g, b);
    log('[display] ${obj.id}:setFillColor($r, $g, $b, $a)');
    return 0;
  }

  int _setStrokeColor(LuaState ls, DisplayObject obj) {
    final r = ((ls.optNumber(1, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final g = ((ls.optNumber(2, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final b = ((ls.optNumber(3, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final a = ls.getTop() >= 4
        ? ((ls.optNumber(4, 1) ?? 1) * 255).toInt().clamp(0, 255)
        : 255;
    obj.strokeColor = Color.fromARGB(a, r, g, b);
    if (obj.strokeWidth == 0) obj.strokeWidth = 2;
    log('[display] ${obj.id}:setStrokeColor($r, $g, $b, $a)');
    return 0;
  }

  int _addEventListener(LuaState ls, DisplayObject obj) {
    final eventType = ls.optString(1, '') ?? '';
    if (ls.type(2) == LuaType.luaFunction) {
      obj.eventListeners[eventType] = (event) {
        log('[display] ${obj.id} event: $eventType');
      };
      log('[display] ${obj.id}:addEventListener("$eventType")');
    }
    return 0;
  }

  int _insertChild(LuaState ls, DisplayObject obj) {
    final child = _getDisplayObject(ls, 1);
    final index = (ls.optNumber(2, -1) ?? -1).toInt();
    if (child != null) {
      if (index >= 0 && index < obj.children.length) {
        obj.children.insert(index, child.id);
      } else {
        obj.children.add(child.id);
      }
      child.parentId = obj.id;
      log('[display] ${obj.id}:insert(${child.id})');
    }
    return 0;
  }

  int _toFront(LuaState ls, DisplayObject obj) {
    scene.objects.remove(obj);
    scene.objects.add(obj);
    log('[display] ${obj.id}:toFront()');
    return 0;
  }

  int _toBack(LuaState ls, DisplayObject obj) {
    scene.objects.remove(obj);
    scene.objects.insert(0, obj);
    log('[display] ${obj.id}:toBack()');
    return 0;
  }

  void _registerGraphicsTable(LuaState state) {
    state.newTable();

    state.pushString('drawLine');
    state.pushDartFunction((ls) => _newLine(ls));
    state.setTable(-3);

    state.pushString('setColor');
    state.pushDartFunction((ls) => _graphicsSetColor(ls));
    state.setTable(-3);

    state.pushString('newImageRect');
    state.pushDartFunction((ls) => _newImage(ls));
    state.setTable(-3);

    state.setGlobal('graphics');
  }

  int _graphicsSetColor(LuaState ls) {
    final r = ((ls.optNumber(1, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final g = ((ls.optNumber(2, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final b = ((ls.optNumber(3, 1) ?? 1) * 255).toInt().clamp(0, 255);
    log('[graphics] setColor($r, $g, $b)');
    return 0;
  }

  void _registerTransitionTable(LuaState state) {
    state.newTable();

    state.pushString('to');
    state.pushDartFunction((ls) => _transitionTo(ls));
    state.setTable(-3);

    state.pushString('dissolve');
    state.pushDartFunction((ls) => _transitionDissolve(ls));
    state.setTable(-3);

    state.pushString('cancel');
    state.pushDartFunction((ls) => _transitionCancel(ls));
    state.setTable(-3);

    state.pushString('pause');
    state.pushDartFunction((ls) => _transitionPause(ls));
    state.setTable(-3);

    state.pushString('resume');
    state.pushDartFunction((ls) => _transitionResume(ls));
    state.setTable(-3);

    state.setGlobal('transition');
  }

  int _transitionTo(LuaState ls) {
    final obj = _getDisplayObject(ls, 1);
    if (obj == null) {
      log('[transition] to: object not found');
      return 0;
    }

    final duration = ((ls.optNumber(2, 1000) ?? 1000)).toInt();
    final targetX = ls.optNumber(3, obj.x) ?? obj.x;
    final targetY = ls.optNumber(4, obj.y) ?? obj.y;
    final easing = ls.optString(5, 'linear') ?? 'linear';
    final onComplete = ls.type(6) == LuaType.luaFunction;

    log('[transition] to(${obj.id}, $duration ms, x=$targetX, y=$targetY, $easing)');
    return 0;
  }

  int _transitionDissolve(LuaState ls) {
    final obj = _getDisplayObject(ls, 1);
    if (obj == null) return 0;

    final duration = ((ls.optNumber(2, 500) ?? 500)).toInt();
    final targetAlpha = ls.optNumber(3, 0) ?? 0;

    log('[transition] dissolve(${obj.id}, $duration ms, alpha=$targetAlpha)');
    return 0;
  }

  int _transitionCancel(LuaState ls) {
    final obj = _getDisplayObject(ls, 1);
    if (obj != null) {
      log('[transition] cancel(${obj.id})');
    }
    return 0;
  }

  int _transitionPause(LuaState ls) {
    final obj = _getDisplayObject(ls, 1);
    if (obj != null) {
      log('[transition] pause(${obj.id})');
    }
    return 0;
  }

  int _transitionResume(LuaState ls) {
    final obj = _getDisplayObject(ls, 1);
    if (obj != null) {
      log('[transition] resume(${obj.id})');
    }
    return 0;
  }

  void _registerTimerTable(LuaState state) {
    state.newTable();

    state.pushString('performWithDelay');
    state.pushDartFunction((ls) => _timerPerformWithDelay(ls));
    state.setTable(-3);

    state.pushString('cancel');
    state.pushDartFunction((ls) => _timerCancel(ls));
    state.setTable(-3);

    state.pushString('pause');
    state.pushDartFunction((ls) => _timerPause(ls));
    state.setTable(-3);

    state.pushString('resume');
    state.pushDartFunction((ls) => _timerResume(ls));
    state.setTable(-3);

    state.setGlobal('timer');
  }

  int _timerPerformWithDelay(LuaState ls) {
    final delay = ((ls.optNumber(1, 1000) ?? 1000)).toInt();
    final hasCallback = ls.type(2) == LuaType.luaFunction;
    final iterations = ((ls.optNumber(3, 1) ?? 1)).toInt();

    if (hasCallback) {
      final timerId = 'timer_${DateTime.now().millisecondsSinceEpoch}';
      log('[timer] performWithDelay($delay ms, iterations=$iterations) -> $timerId');
      ls.pushString(timerId);
      return 1;
    }

    ls.pushNil();
    return 1;
  }

  int _timerCancel(LuaState ls) {
    final timerId = ls.optString(1, '') ?? '';
    log('[timer] cancel($timerId)');
    return 0;
  }

  int _timerPause(LuaState ls) {
    final timerId = ls.optString(1, '') ?? '';
    log('[timer] pause($timerId)');
    return 0;
  }

  int _timerResume(LuaState ls) {
    final timerId = ls.optString(1, '') ?? '';
    log('[timer] resume($timerId)');
    return 0;
  }
}
