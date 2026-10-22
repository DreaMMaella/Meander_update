import 'package:flutter/foundation.dart';

class TimerHandle {
  final String id;
  final Duration delay;
  final Duration? repeatDelay;
  final int? iterations;
  final VoidCallback callback;
  int _remainingIterations;
  Duration _elapsed = Duration.zero;
  bool _isPaused = false;
  bool _isComplete = false;

  TimerHandle({
    required this.id,
    required this.delay,
    this.repeatDelay,
    this.iterations,
    required this.callback,
  }) : _remainingIterations = iterations ?? 1;

  bool get isComplete => _isComplete;
  bool get isPaused => _isPaused;

  void update(Duration delta) {
    if (_isComplete || _isPaused) return;

    _elapsed += delta;
    if (_elapsed >= delay) {
      callback();
      _elapsed = Duration.zero;

      if (_remainingIterations > 1) {
        _remainingIterations--;
      } else if (_remainingIterations == 1 && repeatDelay != null) {
        _remainingIterations = -1;
      } else if (_remainingIterations == 1) {
        _isComplete = true;
      }
    }
  }

  void cancel() {
    _isComplete = true;
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }
}

class TimerManager {
  final Map<String, TimerHandle> _timers = {};
  int _seq = 0;

  String performWithDelay(Duration delay, VoidCallback callback, {int iterations = 1}) {
    final id = 'timer_${_seq++}';
    _timers[id] = TimerHandle(
      id: id,
      delay: delay,
      iterations: iterations,
      callback: callback,
    );
    return id;
  }

  String scheduleRepeating(Duration delay, Duration repeatDelay, VoidCallback callback, {int? iterations}) {
    final id = 'timer_${_seq++}';
    _timers[id] = TimerHandle(
      id: id,
      delay: delay,
      repeatDelay: repeatDelay,
      iterations: iterations,
      callback: callback,
    );
    return id;
  }

  void update(Duration delta) {
    final toRemove = <String>[];
    for (final entry in _timers.entries) {
      entry.value.update(delta);
      if (entry.value.isComplete) {
        toRemove.add(entry.key);
      }
    }
    for (final id in toRemove) {
      _timers.remove(id);
    }
  }

  void cancel(String timerId) {
    _timers[timerId]?.cancel();
    _timers.remove(timerId);
  }

  void cancelAll() {
    _timers.clear();
  }

  void pause(String timerId) {
    _timers[timerId]?.pause();
  }

  void resume(String timerId) {
    _timers[timerId]?.resume();
  }

  void pauseAll() {
    for (final timer in _timers.values) {
      timer.pause();
    }
  }

  void resumeAll() {
    for (final timer in _timers.values) {
      timer.resume();
    }
  }
}
