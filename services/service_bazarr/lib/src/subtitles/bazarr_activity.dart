import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meta/meta.dart';

import '../bazarr_api.dart';
import '../bazarr_providers.dart';
import 'bazarr_version.dart';
import 'job_watch.dart';

/// A provider the activity watcher refreshes after an action: any
/// `FutureProvider` (or family member) whose data the action can change.
typedef WatchedProvider = ProviderBase<AsyncValue<Object?>>;

/// How long "Search all missing" keeps watching Bazarr's queue.
const Duration bazarrSearchAllMaxDuration = Duration(minutes: 30);

/// Timing of the job watcher. Tests override [bazarrJobWatchConfigProvider]
/// with a fake [schedule] and [now].
@immutable
class JobWatchConfig {
  const JobWatchConfig({
    this.schedule,
    this.now,
    this.interval = const Duration(seconds: 2),
    this.maxDuration = const Duration(minutes: 2),
    this.fallbackDelays = const <Duration>[
      Duration(seconds: 3),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  });

  /// Null schedules with a [Timer].
  final JobWatchSchedule? schedule;

  /// Null reads [DateTime.now].
  final DateTime Function()? now;
  final Duration interval;
  final Duration maxDuration;
  final List<Duration> fallbackDelays;
}

/// The job watcher's timing; the defaults use real timers and the clock.
final Provider<JobWatchConfig> bazarrJobWatchConfigProvider =
    Provider<JobWatchConfig>((Ref ref) => const JobWatchConfig());

/// Busy rows and job-queue activity of one Bazarr.
@immutable
class BazarrActivityState {
  const BazarrActivityState({
    this.jobsActive = false,
    this.inFlight = const <String, int>{},
    this.awaitingJob = const <String>{},
  });

  /// True while the watcher polls Bazarr's job queue.
  final bool jobsActive;

  /// Requests still running, counted per busy key.
  final Map<String, int> inFlight;

  /// Keys whose request succeeded and whose job hasn't drained yet.
  final Set<String> awaitingJob;

  /// A row is busy from the tap until the queue drains or its request fails.
  bool isBusy(String key) =>
      (inFlight[key] ?? 0) > 0 || awaitingJob.contains(key);

  BazarrActivityState copyWith({
    bool? jobsActive,
    Map<String, int>? inFlight,
    Set<String>? awaitingJob,
  }) =>
      BazarrActivityState(
        jobsActive: jobsActive ?? this.jobsActive,
        inFlight: inFlight ?? this.inFlight,
        awaitingJob: awaitingJob ?? this.awaitingJob,
      );

  @override
  String toString() => 'BazarrActivityState(jobsActive: $jobsActive, '
      'inFlight: $inFlight, awaitingJob: $awaitingJob)';
}

/// One activity controller per Bazarr, keyed by the Bazarr instance **id**.
///
/// Kept alive so a search started on one screen still refreshes the data
/// after navigating away. Rebuilds — dropping busy rows and the watched set —
/// when that instance is edited or removed.
final bazarrActivityProvider =
    NotifierProvider.family<BazarrActivity, BazarrActivityState, String>(
  BazarrActivity.new,
);

/// Runs Bazarr actions, keeps their rows busy and refreshes the affected
/// providers once Bazarr's background jobs finish (see [JobWatch]).
class BazarrActivity extends Notifier<BazarrActivityState> {
  BazarrActivity(this.bazarrId);

  /// The Bazarr instance id.
  final String bazarrId;

  Instance? _instance;
  JobWatch<WatchedProvider>? _watch;

  // Bumped on every build and dispose, so late completions from an older
  // build (or after the instance changed) never touch the new state.
  int _generation = 0;

  @override
  BazarrActivityState build() {
    final Instance? instance = ref.watch(instanceByIdProvider(bazarrId));
    final JobWatchConfig config = ref.watch(bazarrJobWatchConfigProvider);
    final int generation = ++_generation;
    _instance = instance;
    final JobWatch<WatchedProvider> watch = JobWatch<WatchedProvider>(
      fetchActiveJobIds: () => _fetchActiveJobIds(instance),
      refresh: _refresh,
      onActiveChange: (bool active) => _onActiveChange(generation, active),
      schedule: config.schedule,
      now: config.now,
      interval: config.interval,
      maxDuration: config.maxDuration,
      fallbackDelays: config.fallbackDelays,
    );
    _watch = watch;
    ref.onDispose(() {
      _generation++;
      if (identical(_watch, watch)) {
        _watch = null;
      }
      watch.dispose();
    });
    return const BazarrActivityState();
  }

  /// Refreshes [providers] now and again as Bazarr's jobs finish, until the
  /// queue drains or [maxDuration] (default 2 min) passes.
  void track(List<WatchedProvider> providers, {Duration? maxDuration}) {
    if (providers.isEmpty) {
      return;
    }
    _watch?.track(providers, maxDuration: maxDuration);
  }

  /// Runs [action] against this Bazarr with [busyKey] busy. On success the
  /// key stays busy until the job queue drains, and [refresh] is tracked; on
  /// failure the key is released and the error rethrown.
  Future<T> run<T>(
    String busyKey,
    Future<T> Function(BazarrApi api) action, {
    required List<WatchedProvider> refresh,
    Duration? maxDuration,
  }) async {
    final int generation = _generation;
    _changeInFlight(busyKey, 1);
    final T result;
    try {
      final BazarrApi api = await _api();
      result = await action(api);
    } on Object {
      if (_isCurrent(generation)) {
        _changeInFlight(busyKey, -1);
      }
      rethrow;
    }
    if (!_isCurrent(generation)) {
      return result;
    }
    final Map<String, int> inFlight = _decremented(state.inFlight, busyKey);
    state = state.copyWith(
      inFlight: inFlight,
      awaitingJob:
          refresh.isEmpty ? null : <String>{...state.awaitingJob, busyKey},
    );
    track(refresh, maxDuration: maxDuration);
    return result;
  }

  Future<BazarrApi> _api() {
    final Instance? instance = _instance;
    if (instance == null) {
      return Future<BazarrApi>.error(
        StateError('Bazarr instance $bazarrId is not in the active profile'),
      );
    }
    return ref.read(bazarrApiProvider(instance).future);
  }

  Future<List<int>?> _fetchActiveJobIds(Instance? instance) async {
    if (instance == null || !ref.mounted) {
      return null;
    }
    // A Bazarr without a job queue (before 1.5.6) may answer the route with
    // its web UI instead of a 404; go straight to timed refreshes.
    final BazarrVersionInfo info =
        ref.read(bazarrVersionInfoProvider(instance));
    if (info.state == BazarrVersionState.known &&
        !info.supports(BazarrFeature.jobs)) {
      return null;
    }
    final BazarrApi api = await ref.read(bazarrApiProvider(instance).future);
    return api.getActiveJobIds();
  }

  // Midway (jobs still running, another refresh follows): don't restart a
  // provider already loading — a big list could otherwise never land — and
  // leave unwatched providers alone. The final refresh invalidates every
  // provider that exists.
  void _refresh(List<WatchedProvider> providers, {required bool midway}) {
    if (!ref.mounted) {
      return;
    }
    for (final WatchedProvider provider in providers) {
      if (!ref.exists(provider)) {
        continue;
      }
      if (midway && ref.read(provider).isLoading) {
        continue;
      }
      ref.invalidate(provider);
    }
  }

  void _onActiveChange(int generation, bool active) {
    if (!_isCurrent(generation)) {
      return;
    }
    state = state.copyWith(
      jobsActive: active,
      awaitingJob: active ? null : const <String>{},
    );
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  void _changeInFlight(String key, int delta) {
    state = state.copyWith(
      inFlight: delta > 0
          ? <String, int>{
              ...state.inFlight,
              key: (state.inFlight[key] ?? 0) + 1,
            }
          : _decremented(state.inFlight, key),
    );
  }

  static Map<String, int> _decremented(Map<String, int> inFlight, String key) {
    final int next = (inFlight[key] ?? 0) - 1;
    return <String, int>{
      for (final MapEntry<String, int> e in inFlight.entries)
        if (e.key != key) e.key: e.value,
      if (next > 0) key: next,
    };
  }
}
