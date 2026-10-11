/// A hand-written fake clock and timer queue for `JobWatch`.
///
/// [advance] runs every timer due within the window in time order (timers
/// scheduled synchronously while it runs are included, like fake timers in
/// other test frameworks), moves the clock to the end of the window and then
/// lets pending microtasks (the awaited job fetch) settle.
class FakeScheduler {
  FakeScheduler([DateTime? start]) : now = start ?? DateTime(2026);

  DateTime now;
  final List<_FakeTimer> _timers = <_FakeTimer>[];
  int _seq = 0;

  /// Number of timers still scheduled.
  int get pending => _timers.length;

  /// A `JobWatchSchedule`.
  void Function() schedule(Duration delay, void Function() callback) {
    final _FakeTimer timer = _FakeTimer(now.add(delay), _seq++, callback);
    _timers.add(timer);
    return () => _timers.remove(timer);
  }

  Future<void> advance(Duration by) async {
    final DateTime target = now.add(by);
    while (true) {
      final _FakeTimer? next = _nextDue(target);
      if (next == null) {
        break;
      }
      _fire(next);
    }
    now = target;
    await flush();
  }

  /// Runs the earliest timer at once, whenever it is due.
  void runNext() {
    final _FakeTimer? next = _nextDue(null);
    if (next != null) {
      _fire(next);
    }
  }

  _FakeTimer? _nextDue(DateTime? until) {
    _FakeTimer? best;
    for (final _FakeTimer t in _timers) {
      if (until != null && t.due.isAfter(until)) {
        continue;
      }
      if (best == null ||
          t.due.isBefore(best.due) ||
          (t.due == best.due && t.seq < best.seq)) {
        best = t;
      }
    }
    return best;
  }

  void _fire(_FakeTimer timer) {
    _timers.remove(timer);
    if (timer.due.isAfter(now)) {
      now = timer.due;
    }
    timer.callback();
  }
}

/// Lets every pending microtask run (one event-loop turn).
Future<void> flush() => Future<void>(() {});

class _FakeTimer {
  _FakeTimer(this.due, this.seq, this.callback);

  final DateTime due;
  final int seq;
  final void Function() callback;
}
