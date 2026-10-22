import 'dart:ui';

import 'package:canvas_app/plugin_host/canvas/display_object.dart';

enum TransitionType {
  to,
  dissolve,
  cancel,
}

class Transition {
  final String id;
  final String objectId;
  final Duration duration;
  final Duration delay;
  final Map<String, dynamic> properties;
  final Map<String, dynamic> startValues = {};
  final VoidCallback? onComplete;
  final Function(double progress)? onUpdate;
  final EasingFunction easing;
  int? iterations;
  bool autoReverse = false;

  double _elapsed = 0.0;
  bool _isComplete = false;
  bool _isPaused = false;
  bool _isReversing = false;

  Transition({
    required this.id,
    required this.objectId,
    required this.duration,
    this.delay = Duration.zero,
    required this.properties,
    this.onComplete,
    this.onUpdate,
    this.easing = EasingFunctions.linear,
    this.iterations,
    this.autoReverse = false,
  });

  bool get isComplete => _isComplete;
  bool get isPaused => _isPaused;

  void update(Duration delta) {
    if (_isComplete || _isPaused) return;

    if (_elapsed < delay.inMilliseconds) {
      _elapsed += delta.inMilliseconds;
      return;
    }

    _elapsed += delta.inMilliseconds;
    final activeDuration = _elapsed - delay.inMilliseconds;
    double progress = (activeDuration / duration.inMilliseconds).clamp(0.0, 1.0);

    if (autoReverse && progress >= 1.0) {
      _isReversing = !_isReversing;
      if (_isReversing) {
        _elapsed = delay.inMilliseconds.toDouble();
        return;
      }
    }

    final easedProgress = easing(progress);

    if (onUpdate != null) {
      onUpdate!(easedProgress);
    }

    if (progress >= 1.0) {
      if (iterations != null) {
        iterations = iterations! - 1;
        if (iterations! > 0) {
        _elapsed = delay.inMilliseconds.toDouble();
          return;
        }
      }
      _isComplete = true;
      onComplete?.call();
    }
  }
}

typedef EasingFunction = double Function(double t);

class EasingFunctions {
  static double easeInQuad(double t) => t * t;
  static double easeOutQuad(double t) => t * (2 - t);
  static double easeInOutQuad(double t) {
    if (t < 0.5) return 2 * t * t;
    return -1 + (4 - 2 * t) * t;
  }

  static double easeInCubic(double t) => t * t * t;
  static double easeOutCubic(double t) => (--t) * t * t + 1;
  static double easeInOutCubic(double t) {
    if (t < 0.5) return 4 * t * t * t;
    return (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;
  }

  static double easeInQuart(double t) => t * t * t * t;
  static double easeOutQuart(double t) => 1 - (--t) * t * t * t;

  static double easeInQuint(double t) => t * t * t * t * t;
  static double easeOutQuint(double t) => 1 + (--t) * t * t * t * t;

  static double easeInSine(double t) => 1 - cos(t * pi / 2);
  static double easeOutSine(double t) => sin(t * pi / 2);
  static double easeInOutSine(double t) => -(cos(pi * t) - 1) / 2;

  static double easeInExpo(double t) {
    if (t == 0) return 0;
    return pow(2, 10 * (t - 1));
  }

  static double easeOutExpo(double t) {
    if (t == 1) return 1;
    return 1 - pow(2, -10 * t);
  }

  static double easeInBack(double t) {
    final s = 1.70158;
    return (s + 1) * t * t * t - s * t * t;
  }

  static double easeOutBack(double t) {
    final s = 1.70158;
    return (t - 1) * (t - 1) * ((s + 1) * (t - 1) + s) + 1;
  }

  static double easeInElastic(double t) {
    if (t == 0 || t == 1) return t;
    return -pow(2, 10 * (t - 1)) * sin((t - 1.1) * 5 * pi);
  }

  static double easeOutElastic(double t) {
    if (t == 0 || t == 1) return t;
    return pow(2, -10 * t) * sin((t - 0.1) * 5 * pi) + 1;
  }

  static double bounce(double t) {
    if (t < 1 / 2.75) {
      return 7.5625 * t * t;
    } else if (t < 2 / 2.75) {
      return 7.5625 * (t -= 1.5 / 2.75) * t + 0.75;
    } else if (t < 2.5 / 2.75) {
      return 7.5625 * (t -= 2.25 / 2.75) * t + 0.9375;
    } else {
      return 7.5625 * (t -= 2.625 / 2.75) * t + 0.984375;
    }
  }

  static double easeOutBounce(double t) => bounce(t);
  static double easeInBounce(double t) => 1 - bounce(1 - t);

  static double linear(double t) => t;

  static double pow(double base, double exp) {
    var result = 1.0;
    for (var i = 0; i < exp; i++) result *= base;
    return result;
  }

  static double sin(double x) {
    var sum = 0.0;
    var term = x;
    for (var i = 0; i < 10; i++) {
      sum += term;
      term *= -x * x / ((2 * i + 2) * (2 * i + 3));
    }
    return sum;
  }

  static double cos(double x) {
    var sum = 0.0;
    var term = 1.0;
    for (var i = 0; i < 10; i++) {
      sum += term;
      term *= -x * x / ((2 * i + 1) * (2 * i + 2));
    }
    return sum;
  }

  static const double pi = 3.1415926535897932;

  static EasingFunction fromName(String name) {
    switch (name) {
      case 'linear':
        return linear;
      case 'inQuad':
        return easeInQuad;
      case 'outQuad':
        return easeOutQuad;
      case 'inOutQuad':
        return easeInOutQuad;
      case 'inCubic':
        return easeInCubic;
      case 'outCubic':
        return easeOutCubic;
      case 'inOutCubic':
        return easeInOutCubic;
      case 'inQuart':
        return easeInQuart;
      case 'outQuart':
        return easeOutQuart;
      case 'inQuint':
        return easeInQuint;
      case 'outQuint':
        return easeOutQuint;
      case 'inSine':
        return easeInSine;
      case 'outSine':
        return easeOutSine;
      case 'inOutSine':
        return easeInOutSine;
      case 'inExpo':
        return easeInExpo;
      case 'outExpo':
        return easeOutExpo;
      case 'inBack':
        return easeInBack;
      case 'outBack':
        return easeOutBack;
      case 'inElastic':
        return easeInElastic;
      case 'outElastic':
        return easeOutElastic;
      case 'outBounce':
        return easeOutBounce;
      case 'inBounce':
        return easeInBounce;
      default:
        return linear;
    }
  }
}

class TransitionManager {
  final Map<String, Transition> _transitions = {};
  final Map<String, List<Transition>> _byObject = {};
  int _seq = 0;

  String createTransition({
    required String objectId,
    required Duration duration,
    Duration delay = Duration.zero,
    required Map<String, dynamic> properties,
    VoidCallback? onComplete,
    Function(double progress)? onUpdate,
    String easing = 'linear',
    int? iterations,
    bool autoReverse = false,
  }) {
    final id = 't_${_seq++}';
    final transition = Transition(
      id: id,
      objectId: objectId,
      duration: duration,
      delay: delay,
      properties: properties,
      onComplete: onComplete,
      onUpdate: onUpdate,
      easing: EasingFunctions.fromName(easing),
      iterations: iterations,
      autoReverse: autoReverse,
    );
    _transitions[id] = transition;
    _byObject.putIfAbsent(objectId, () => []).add(transition);
    return id;
  }

  void update(Duration delta) {
    final toRemove = <String>[];
    for (final entry in _transitions.entries) {
      entry.value.update(delta);
      if (entry.value.isComplete) {
        toRemove.add(entry.key);
      }
    }
    for (final id in toRemove) {
      _transitions.remove(id);
    }
  }

  void cancel(String transitionId) {
    _transitions.remove(transitionId);
  }

  void cancelAll(String objectId) {
    _byObject[objectId]?.forEach((t) => _transitions.remove(t.id));
    _byObject.remove(objectId);
  }

  void pause(String transitionId) {
    _transitions[transitionId]?._isPaused = true;
  }

  void resume(String transitionId) {
    _transitions[transitionId]?._isPaused = false;
  }

  void pauseAll(String objectId) {
    _byObject[objectId]?.forEach((t) => t._isPaused = true);
  }

  void resumeAll(String objectId) {
    _byObject[objectId]?.forEach((t) => t._isPaused = false);
  }
}
