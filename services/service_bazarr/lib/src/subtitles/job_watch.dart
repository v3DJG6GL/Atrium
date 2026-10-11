import 'dart:async';

/// Schedules [callback] after [delay]; returns a function that cancels it.
typedef JobWatchSchedule = void Function() Function(
  Duration delay,
  void Function() callback,
);

/// Refreshes data after work a server runs in the background.
///
/// Bazarr (since 1.5.6) acknowledges searches, downloads, sync and translate
/// at once and does the work later in a job queue. The acknowledgement says
/// nothing about the outcome, so the UI must refresh the affected data once
/// the job is done. The queue doesn't say which job an action created, so the
/// watcher tracks the queue as a whole:
///
///   - [track] refreshes the keys at once (covers servers that finish the
///     work before answering) and starts polling the active-job list;
///   - every time a job leaves the list, tracked keys refresh again with
///     `midway: true` (several actions in a row each land as soon as their
///     job ends);
///   - once the list has been empty for two polls in a row, or the deadline
///     passed, a final refresh runs and tracking stops.
///
/// A server without a job list (`fetchActiveJobIds` resolves null) gets a few
/// timed refreshes instead.
///
/// Pure: time and scheduling are injected, so it is tested with a fake
/// scheduler. A port of Dashboarr's `lib/job-watch.ts`.
class JobWatch<K> {
  JobWatch({
    required Future<List<int>?> Function() fetchActiveJobIds,
    required void Function(List<K> keys, {required bool midway}) refresh,
    void Function(bool active)? onActiveChange,
    JobWatchSchedule? schedule,
    DateTime Function()? now,
    this.interval = const Duration(seconds: 2),
    this.maxDuration = const Duration(minutes: 2),
    this.fallbackDelays = const <Duration>[
      Duration(seconds: 3),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  })  : _fetchActiveJobIds = fetchActiveJobIds,
        _refresh = refresh,
        _onActiveChange = onActiveChange,
        _schedule = schedule ?? _timerSchedule,
        _now = now ?? DateTime.now;

  /// Time between two polls of the job list.
  final Duration interval;

  /// How long one [track] keeps watching at most, unless it passes its own.
  final Duration maxDuration;

  /// When to refresh on a server without a job list, counted from then.
  final List<Duration> fallbackDelays;

  // Ids of the jobs currently pending or running; null when the server has
  // no job list. A throw counts as "no information this tick".
  final Future<List<int>?> Function() _fetchActiveJobIds;
  // `midway` marks the refreshes while jobs are still running: another one
  // follows, so a fetch already in flight can be left to finish instead of
  // being restarted (a big list could otherwise never land).
  final void Function(List<K> keys, {required bool midway}) _refresh;
  // Fires true when tracking starts and false when it stops.
  final void Function(bool active)? _onActiveChange;
  final JobWatchSchedule _schedule;
  final DateTime Function() _now;

  List<K> _tracked = <K>[];
  Set<int> _lastIds = <int>{};
  int _emptyPolls = 0;
  DateTime _deadline = DateTime.fromMillisecondsSinceEpoch(0);
  void Function()? _cancelTimer;
  bool _polling = false;
  bool _disposed = false;
  final Set<void Function()> _fallbackCancels = <void Function()>{};

  /// Whether the job list is being watched (from the first [track] until the
  /// watch finishes or falls back to timed refreshes).
  bool get active => _polling;

  /// Refreshes [keys] now and watches the job queue until it drains.
  /// [maxDuration] extends the deadline for an action whose jobs run long (a
  /// library-wide search); it never shortens a deadline already set.
  void track(Iterable<K> keys, {Duration? maxDuration}) {
    if (_disposed) {
      return;
    }
    final List<K> list = keys.toList();
    if (list.isEmpty) {
      return;
    }
    _refresh(list, midway: false);
    for (final K key in list) {
      if (!_tracked.contains(key)) {
        _tracked.add(key);
      }
    }
    final DateTime candidate = _now().add(maxDuration ?? this.maxDuration);
    if (!_polling || candidate.isAfter(_deadline)) {
      _deadline = candidate;
    }
    _emptyPolls = 0;
    if (!_polling) {
      _polling = true;
      _onActiveChange?.call(true);
      _cancelTimer = _schedule(interval, _runTick);
    }
  }

  /// Stops everything: pending polls and fallback refreshes are cancelled and
  /// later calls do nothing.
  void dispose() {
    _disposed = true;
    _stop();
    for (final void Function() cancel in _fallbackCancels) {
      cancel();
    }
    _fallbackCancels.clear();
  }

  void _stop() {
    _cancelTimer?.call();
    _cancelTimer = null;
    final bool wasPolling = _polling;
    _polling = false;
    _tracked = <K>[];
    _lastIds = <int>{};
    _emptyPolls = 0;
    if (wasPolling) {
      _onActiveChange?.call(false);
    }
  }

  void _finish() {
    final List<K> keys = _tracked;
    _stop();
    if (keys.isNotEmpty) {
      _refresh(keys, midway: false);
    }
  }

  void _fallback() {
    final List<K> keys = _tracked;
    _stop();
    for (final Duration delay in fallbackDelays) {
      late final void Function() cancel;
      cancel = _schedule(delay, () {
        _fallbackCancels.remove(cancel);
        if (!_disposed) {
          _refresh(keys, midway: false);
        }
      });
      _fallbackCancels.add(cancel);
    }
  }

  void _runTick() => unawaited(_tick());

  Future<void> _tick() async {
    _cancelTimer = null;
    if (_disposed || _tracked.isEmpty) {
      _stop();
      return;
    }

    List<int>? ids;
    bool known = true;
    try {
      ids = await _fetchActiveJobIds();
    } on Object {
      known = false; // transient: just try again next tick
    }
    if (_disposed) {
      return;
    }
    if (known && ids == null) {
      _fallback();
      return;
    }

    if (ids != null) {
      final Set<int> current = ids.toSet();
      final bool someFinished = _lastIds.any((int id) => !current.contains(id));
      _lastIds = current;
      if (current.isEmpty) {
        _emptyPolls += 1;
        if (_emptyPolls >= 2) {
          _finish();
          return;
        }
      } else {
        _emptyPolls = 0;
      }
      if (someFinished) {
        _refresh(List<K>.of(_tracked), midway: true);
      }
    }

    if (!_now().isBefore(_deadline)) {
      _finish();
      return;
    }
    _cancelTimer = _schedule(interval, _runTick);
  }
}

void Function() _timerSchedule(Duration delay, void Function() callback) {
  final Timer timer = Timer(delay, callback);
  return timer.cancel;
}
