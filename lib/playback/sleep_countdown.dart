import 'dart:async';

/// Injected monotonic time and wakeup cancellation keep playback time independent
/// of seeks, wall-clock changes and callback delivery delays.
typedef SleepSchedule = void Function() Function(
  Duration delay,
  void Function() wake,
);

void Function() scheduleSleepWakeup(Duration delay, void Function() wake) {
  final timer = Timer(delay, wake);
  return timer.cancel;
}

class SleepCountdown {
  SleepCountdown({
    required this.clock,
    required this.schedule,
    required this.onWake,
  });
  final Duration Function() clock;
  final SleepSchedule schedule;
  final void Function(int generation) onWake;
  Duration? _remaining;
  Duration _last = Duration.zero;
  bool _counting = false;
  bool waitingForEnd = false;
  String? lockedEntryId;
  int generation = 0;
  void Function()? _cancelWake;
  bool _disposed = false;
  bool get active => _remaining != null;
  Duration get remaining {
    final value = _remaining ?? Duration.zero;
    if (!_counting) return value;
    final result = value - (clock() - _last);
    return result.isNegative ? Duration.zero : result;
  }

  void start(Duration duration) {
    if (duration <= Duration.zero ||
        duration > const Duration(hours: 12, minutes: 59)) {
      throw ArgumentError.value(duration, 'duration', '必须大于0且不超过12小时59分钟');
    }
    cancel();
    _remaining = duration;
    _last = clock();
  }

  /// Observed transitions settle the *previous* state before taking the new one.
  /// No position value enters this calculation.
  void update({required bool counting, required String? entryId}) {
    if (_disposed || !active) return;
    final now = clock();
    if (_counting) {
      final delta = now - _last;
      if (!delta.isNegative) _remaining = _remaining! - delta;
    }
    _last = now;
    _cancelWake?.call();
    _cancelWake = null;
    if (waitingForEnd) {
      _counting = false;
      return;
    }
    if (_remaining! <= Duration.zero) {
      _remaining = Duration.zero;
      _counting = false;
      waitingForEnd = true;
      lockedEntryId = entryId;
      return;
    }
    _counting = counting;
    if (counting) {
      final token = generation;
      _cancelWake = schedule(_remaining!, () {
        if (!_disposed && token == generation) onWake(token);
      });
    }
  }

  void cancel() {
    generation++;
    _cancelWake?.call();
    _cancelWake = null;
    _remaining = null;
    _counting = false;
    waitingForEnd = false;
    lockedEntryId = null;
  }

  void dispose() {
    cancel();
    _disposed = true;
  }
}
