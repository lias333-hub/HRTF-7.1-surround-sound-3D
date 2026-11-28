import 'dart:async';

/// Merges a burst of calls into one run of [action].
///
/// A slider reports dozens of changes a second, and each one used to write to the disk and call into Android
/// (AU-26). [run] starts a [delay] timer at the first call of a burst and later calls inside that window add nothing,
/// so a long drag still produces one run every [delay] (not only after the finger stops). [action] gets no argument:
/// it must read the latest value itself, which is what makes dropping the in-between calls safe.
///
/// [flush] runs the action right now when a run is pending (the finger was lifted, the screen is closing);
/// [cancel] forgets the pending run.
class Throttle {
  Throttle(this.delay, this.action);

  final Duration delay;
  final void Function() action;
  Timer? _timer;

  /// A run is waiting for its timer.
  bool get pending => _timer != null;

  void run() {
    _timer ??= Timer(delay, _fire);
  }

  void flush() {
    final t = _timer;
    if (t == null) return;
    t.cancel();
    _fire();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _fire() {
    _timer = null;
    action();
  }
}
