import 'dart:ui';

import 'package:canvas_app/plugin_host/canvas/display_object.dart';
import 'package:canvas_app/plugin_host/canvas/transition_engine.dart';
import 'package:canvas_app/plugin_host/canvas/timer_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lua_dardo/lua.dart';

typedef LuaLog = void Function(String message);
typedef CanvasCloseCallback = void Function();

class MainThreadCanvasEngine {
  final DisplayScene scene;
  final LuaLog log;
  final VoidCallback? onMarkNeedsBuild;
  CanvasCloseCallback? onClose;

  late LuaState _luaState;
  late TransitionManager _transitions;
  late TimerManager _timers;
  late Ticker _ticker;
  DateTime? _lastFrame;
  bool _isRunning = false;
  int _objSeq = 0;
  int _refSeq = 0;
  final Map<int, DisplayObject> _objectRefs = {};
  final Map<String, Function(Map<String, dynamic>)> _eventHandlers = {};

  MainThreadCanvasEngine({
    required this.scene,
    required this.log,
    this.onMarkNeedsBuild,
  }) {
    _transitions = TransitionManager();
    _timers = TimerManager();
    _ticker = Ticker(_onTick);
  }

  void init() {
    _luaState = LuaState.newState();
    _luaState.openLibs();
    _stripDangerousGlobals(_luaState);
    _registerApi(_luaState);
    _isRunning = true;
    _ticker.start();
  }

  void dispose() {
    _isRunning = false;
    _ticker.dispose();
    _timers.cancelAll();
  }

  void executeScript(String scriptText) {
    final status = _luaState.loadString(scriptText);
    if (status != ThreadStatus.luaOk) {
      log('[Canvas] load error: $status');
      return;
    }
    final callStatus = _luaState.pCall(0, 0, 0);
    if (callStatus != ThreadStatus.luaOk) {
      final msg = _luaState.toStr(-1) ?? 'unknown';
      log('[Canvas] exec error: $msg');
      _luaState.pop(1);
    }
  }

  void callFunction(String name, {List<Object?>? args}) {
    _luaState.getGlobal(name);
    if (_luaState.type(-1) != LuaType.luaFunction) {
      _luaState.pop(1);
      return;
    }
    final count = args?.length ?? 0;
    if (args != null) {
      for (final arg in args) {
        _pushValue(_luaState, arg);
      }
    }
    _luaState.pCall(count, 0, 0);
  }

  void handleTap(double x, double y) {
    final hit = scene.hitTest(x, y);
    if (hit != null) {
      final handler = _eventHandlers['tap:${hit.id}'];
      if (handler != null) {
        handler({'x': x, 'y': y, 'target': hit.id});
      }
    }
  }

  void handleTouchStart(double x, double y) {
    final hit = scene.hitTest(x, y);
    if (hit != null) {
      final handler = _eventHandlers['touchStart:${hit.id}'];
      handler?.call({'x': x, 'y': y, 'target': hit.id});
    }
  }

  void handleTouchMove(double x, double y, double dx, double dy) {
    final hit = scene.hitTest(x, y);
    if (hit != null) {
      final handler = _eventHandlers['touchMove:${hit.id}'];
      handler?.call({'x': x, 'y': y, 'dx': dx, 'dy': dy, 'target': hit.id});
    }
  }

  void handleTouchEnd(double x, double y) {
    final hit = scene.hitTest(x, y);
    if (hit != null) {
      final handler = _eventHandlers['touchEnd:${hit.id}'];
      handler?.call({'x': x, 'y': y, 'target': hit.id});
    }
  }

  void _onTick(Duration elapsed) {
    if (!_isRunning) return;
    final now = DateTime.now();
    final delta = _lastFrame == null
        ? const Duration(milliseconds: 16)
        : now.difference(_lastFrame!);
    _lastFrame = now;
    _transitions.update(delta);
    _timers.update(delta);
    onMarkNeedsBuild?.call();
  }

  void _stripDangerousGlobals(LuaState state) {
    for (final name in ['os', 'io', 'package', 'debug']) {
      state.pushNil();
      state.setGlobal(name);
    }
    for (final name in ['dofile', 'loadfile']) {
      state.pushNil();
      state.setGlobal(name);
    }
  }

  void _registerApi(LuaState state) {
    _registerDisplayTable(state);
    _registerTransitionTable(state);
    _registerTimerTable(state);
  }

  void _registerDisplayTable(LuaState state) {
    state.newTable();

    _pushFn(state, 'newRect', _newRect);
    _pushFn(state, 'newCircle', _newCircle);
    _pushFn(state, 'newLine', _newLine);
    _pushFn(state, 'newPolygon', _newPolygon);
    _pushFn(state, 'newText', _newText);
    _pushFn(state, 'newImage', _newImage);
    _pushFn(state, 'newGroup', _newGroup);
    _pushFn(state, 'remove', _remove);
    _pushFn(state, 'getBounds', _getBounds);
    _pushFn(state, 'close', _close);

    state.setGlobal('display');
  }

  void _pushFn(LuaState state, String name, int Function(LuaState) fn) {
    state.pushString(name);
    state.pushDartFunction(fn);
    state.setTable(-3);
  }

  int _newRect(LuaState ls) {
    final x = ls.optNumber(1, 0) ?? 0;
    final y = ls.optNumber(2, 0) ?? 0;
    final w = ls.optNumber(3, 100) ?? 100;
    final h = ls.optNumber(4, 100) ?? 100;
    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.rect)
      ..x = x
      ..y = y
      ..width = w
      ..height = h
      ..fillColor = const Color(0xFFFFFFFF);
    scene.addObject(obj);
    _pushObj(ls, obj);
    return 1;
  }

  int _newCircle(LuaState ls) {
    final x = ls.optNumber(1, 0) ?? 0;
    final y = ls.optNumber(2, 0) ?? 0;
    final r = ls.optNumber(3, 50) ?? 50;
    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.circle)
      ..x = x
      ..y = y
      ..radius = r
      ..fillColor = const Color(0xFFFFFFFF);
    scene.addObject(obj);
    _pushObj(ls, obj);
    return 1;
  }

  int _newLine(LuaState ls) {
    final x1 = ls.optNumber(1, 0) ?? 0;
    final y1 = ls.optNumber(2, 0) ?? 0;
    final x2 = ls.optNumber(3, 100) ?? 100;
    final y2 = ls.optNumber(4, 100) ?? 100;
    final cx = (x1 + x2) / 2;
    final cy = (y1 + y2) / 2;
    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.line)
      ..x = cx
      ..y = cy
      ..points = [Offset(x1 - cx, y1 - cy), Offset(x2 - cx, y2 - cy)]
      ..strokeColor = const Color(0xFFFFFFFF)
      ..strokeWidth = 2;
    scene.addObject(obj);
    _pushObj(ls, obj);
    return 1;
  }

  int _newPolygon(LuaState ls) {
    final points = <Offset>[];
    var i = 1;
    while (ls.type(i) == LuaType.luaNumber) {
      points.add(Offset(ls.toNumber(i) ?? 0, ls.toNumber(i + 1) ?? 0));
      i += 2;
    }
    if (points.isEmpty) {
      ls.pushNil();
      return 1;
    }
    final cx = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
    final cy = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.polygon)
      ..x = cx
      ..y = cy
      ..polygonPoints = points.map((p) => Offset(p.dx - cx, p.dy - cy)).toList()
      ..fillColor = const Color(0xFFFFFFFF);
    scene.addObject(obj);
    _pushObj(ls, obj);
    return 1;
  }

  int _newText(LuaState ls) {
    final text = ls.toStr(1) ?? '';
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
    _pushObj(ls, obj);
    return 1;
  }

  int _newImage(LuaState ls) {
    final path = ls.toStr(1) ?? '';
    final x = ls.optNumber(2, 0) ?? 0;
    final y = ls.optNumber(3, 0) ?? 0;
    final w = ls.optNumber(4, 100) ?? 100;
    final h = ls.optNumber(5, 100) ?? 100;
    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.image)
      ..x = x
      ..y = y
      ..width = w
      ..height = h
      ..imagePath = path;
    scene.addObject(obj);
    _pushObj(ls, obj);
    return 1;
  }

  int _newGroup(LuaState ls) {
    final id = 'obj_${_objSeq++}';
    final obj = DisplayObject(id: id, type: DisplayObjectType.group);
    scene.addObject(obj);
    _pushObj(ls, obj);
    return 1;
  }

  int _remove(LuaState ls) {
    final obj = _getObj(ls, 1);
    if (obj != null) scene.removeObject(obj.id);
    return 0;
  }

  int _getBounds(LuaState ls) {
    final obj = _getObj(ls, 1);
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

  int _close(LuaState ls) {
    log('[Canvas] display.close() called');
    onClose?.call();
    return 0;
  }

  void _pushObj(LuaState ls, DisplayObject obj) {
    ls.newTable();
    ls.pushString('id');
    ls.pushString(obj.id);
    ls.setTable(-3);

    _addProp(ls, obj, 'x', (o) => o.x, (o, v) => o.x = v);
    _addProp(ls, obj, 'y', (o) => o.y, (o, v) => o.y = v);
    _addProp(ls, obj, 'rotation', (o) => o.rotation, (o, v) => o.rotation = v);
    _addProp(ls, obj, 'alpha', (o) => o.alpha, (o, v) => o.alpha = v.clamp(0.0, 1.0));
    _addProp(ls, obj, 'scaleX', (o) => o.scaleX, (o, v) => o.scaleX = v);
    _addProp(ls, obj, 'scaleY', (o) => o.scaleY, (o, v) => o.scaleY = v);
    _addProp(ls, obj, 'width', (o) => o.width, (o, v) => o.width = v);
    _addProp(ls, obj, 'height', (o) => o.height, (o, v) => o.height = v);
    _addProp(ls, obj, 'radius', (o) => o.radius, (o, v) => o.radius = v);
    _addProp(ls, obj, 'fontSize', (o) => o.fontSize, (o, v) => o.fontSize = v);
    _addProp(ls, obj, 'isVisible', (o) => o.isVisible ? 1.0 : 0.0, (o, v) => o.isVisible = v > 0);
    ls.pushString('text');
    ls.pushDartFunction((inner) {
      if (inner.getTop() >= 2) {
        obj.text = inner.toStr(2) ?? '';
        return 0;
      }
      ls.pushString(obj.text ?? '');
      return 1;
    });
    ls.setTable(-3);

    _addMethod(ls, obj, 'removeSelf', (inner) {
      scene.removeObject(obj.id);
      return 0;
    });
    _addMethod(ls, obj, 'setFillColor', (inner) => _setFillColor(inner, obj));
    _addMethod(ls, obj, 'setStrokeColor', (inner) => _setStrokeColor(inner, obj));
    _addMethod(ls, obj, 'addEventListener', (inner) => _addEventListener(inner, obj));
    _addMethod(ls, obj, 'insert', (inner) => _insertChild(inner, obj));
    _addMethod(ls, obj, 'toFront', (inner) {
      scene.objects.remove(obj);
      scene.objects.add(obj);
      return 0;
    });
    _addMethod(ls, obj, 'toBack', (inner) {
      scene.objects.remove(obj);
      scene.objects.insert(0, obj);
      return 0;
    });

    final ref = ++_refSeq;
    _objectRefs[ref] = obj;
    ls.pushString('__ref');
    ls.pushNumber(ref.toDouble());
    ls.setTable(-3);
  }

  void _addProp(
    LuaState ls,
    DisplayObject obj,
    String name,
    double Function(DisplayObject) getter,
    void Function(DisplayObject, double) setter,
  ) {
    ls.pushString(name);
    ls.pushDartFunction((inner) {
      if (inner.getTop() >= 2) {
        setter(obj, inner.toNumber(2) ?? 0);
        return 0;
      }
      ls.pushNumber(getter(obj));
      return 1;
    });
    ls.setTable(-3);
  }

  void _addMethod(
    LuaState ls,
    DisplayObject obj,
    String name,
    int Function(LuaState) fn,
  ) {
    ls.pushString(name);
    ls.pushDartFunction(fn);
    ls.setTable(-3);
  }

  int _setFillColor(LuaState ls, DisplayObject obj) {
    final r = ((ls.optNumber(1, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final g = ((ls.optNumber(2, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final b = ((ls.optNumber(3, 1) ?? 1) * 255).toInt().clamp(0, 255);
    final a = ls.getTop() >= 4
        ? ((ls.optNumber(4, 1) ?? 1) * 255).toInt().clamp(0, 255)
        : 255;
    obj.fillColor = Color.fromARGB(a, r, g, b);
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
    return 0;
  }

  int _addEventListener(LuaState ls, DisplayObject obj) {
    final eventType = ls.toStr(1) ?? '';
    if (ls.type(2) == LuaType.luaFunction) {
      final key = '$eventType:${obj.id}';
      _eventHandlers[key] = (event) {
        log('[Canvas] ${obj.id} event: $eventType');
      };
    }
    return 0;
  }

  int _insertChild(LuaState ls, DisplayObject obj) {
    final child = _getObj(ls, 1);
    if (child != null) {
      obj.children.add(child.id);
      child.parentId = obj.id;
    }
    return 0;
  }

  DisplayObject? _getObj(LuaState ls, int index) {
    if (ls.type(index) == LuaType.luaTable) {
      ls.getField(index, '__ref');
      final ref = (ls.toNumber(-1) ?? 0).toInt();
      ls.pop(1);
      return _objectRefs[ref];
    }
    return null;
  }

  void _pushValue(LuaState state, Object? value) {
    if (value == null) {
      state.pushNil();
    } else if (value is String) {
      state.pushString(value);
    } else if (value is num) {
      state.pushNumber(value.toDouble());
    } else if (value is bool) {
      state.pushBoolean(value);
    } else {
      state.pushString(value.toString());
    }
  }

  void _registerTransitionTable(LuaState state) {
    state.newTable();

    _pushFn(state, 'to', _transitionTo);
    _pushFn(state, 'dissolve', _transitionDissolve);
    _pushFn(state, 'cancel', _transitionCancel);

    state.setGlobal('transition');
  }

  int _transitionTo(LuaState ls) {
    final obj = _getObj(ls, 1);
    if (obj == null) return 0;
    final duration = ((ls.optNumber(2, 1000) ?? 1000)).toInt();
    final targetX = ls.optNumber(3, obj.x) ?? obj.x;
    final targetY = ls.optNumber(4, obj.y) ?? obj.y;
    final easing = ls.toStr(5) ?? 'linear';

    final startX = obj.x;
    final startY = obj.y;

    _transitions.createTransition(
      objectId: obj.id,
      duration: Duration(milliseconds: duration),
      properties: {'x': targetX, 'y': targetY},
      easing: easing,
      onUpdate: (progress) {
        obj.x = startX + (targetX - startX) * progress;
        obj.y = startY + (targetY - startY) * progress;
      },
    );
    return 0;
  }

  int _transitionDissolve(LuaState ls) {
    final obj = _getObj(ls, 1);
    if (obj == null) return 0;
    final duration = ((ls.optNumber(2, 500) ?? 500)).toInt();
    final targetAlpha = ls.optNumber(3, 0) ?? 0;
    final startAlpha = obj.alpha;

    _transitions.createTransition(
      objectId: obj.id,
      duration: Duration(milliseconds: duration),
      properties: {'alpha': targetAlpha},
      onUpdate: (progress) {
        obj.alpha = startAlpha + (targetAlpha - startAlpha) * progress;
      },
    );
    return 0;
  }

  int _transitionCancel(LuaState ls) {
    final obj = _getObj(ls, 1);
    if (obj != null) _transitions.cancelAll(obj.id);
    return 0;
  }

  void _registerTimerTable(LuaState state) {
    state.newTable();
    _pushFn(state, 'performWithDelay', _timerPerformWithDelay);
    _pushFn(state, 'cancel', _timerCancel);
    state.setGlobal('timer');
  }

  int _timerPerformWithDelay(LuaState ls) {
    final delay = ((ls.optNumber(1, 1000) ?? 1000)).toInt();
    final iterations = ((ls.optNumber(3, 1) ?? 1)).toInt();
    final timerId = 'timer_${DateTime.now().millisecondsSinceEpoch}';

    _timers.performWithDelay(
      Duration(milliseconds: delay),
      () {
        log('[Timer] $timerId fired');
        if (ls.type(2) == LuaType.luaFunction) {
          ls.pushString(timerId);
          ls.pCall(1, 0, 0);
        }
      },
      iterations: iterations,
    );

    ls.pushString(timerId);
    return 1;
  }

  int _timerCancel(LuaState ls) {
    final id = ls.toStr(1) ?? '';
    _timers.cancel(id);
    return 0;
  }
}
