import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/service_bazarr.dart';

import 'support/fake_scheduler.dart';

const Instance bazarr = Instance(
  id: 'bazarr-1',
  name: 'Bazarr Test',
  kind: ServiceKind.bazarr,
  localUrl: 'http://localhost:6767',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'dummy-api-key'),
);

class FakeBazarrApi extends BazarrApi {
  FakeBazarrApi() : super(Dio());

  List<int>? Function() jobs = () => <int>[];
  int jobCalls = 0;

  @override
  Future<List<int>?> getActiveJobIds() async {
    jobCalls++;
    return jobs();
  }
}

class TestInstances extends Notifier<List<Instance>> {
  @override
  List<Instance> build() => const <Instance>[bazarr];

  void replace(List<Instance> instances) => state = instances;
}

final NotifierProvider<TestInstances, List<Instance>> testInstancesProvider =
    NotifierProvider<TestInstances, List<Instance>>(TestInstances.new);

int settledBuilds = 0;
int loadingBuilds = 0;
int unwatchedBuilds = 0;
Completer<int> loadingCompleter = Completer<int>();

final FutureProvider<int> settledProvider =
    FutureProvider<int>((Ref ref) async => ++settledBuilds);
final FutureProvider<int> loadingProvider = FutureProvider<int>((Ref ref) {
  loadingBuilds++;
  return loadingCompleter.future;
});
final FutureProvider<int> unwatchedProvider =
    FutureProvider<int>((Ref ref) async => ++unwatchedBuilds);

/// Lets microtasks, provider rebuilds and the awaited job fetch settle.
Future<void> pump() async {
  for (int i = 0; i < 5; i++) {
    await flush();
  }
}

void main() {
  late FakeScheduler scheduler;
  late FakeBazarrApi api;

  setUp(() {
    scheduler = FakeScheduler();
    api = FakeBazarrApi();
    settledBuilds = 0;
    loadingBuilds = 0;
    unwatchedBuilds = 0;
    loadingCompleter = Completer<int>();
  });

  ProviderContainer makeContainer({String version = '1.6.2'}) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        activeInstancesProvider.overrideWith(
          (Ref ref) => ref.watch(testInstancesProvider),
        ),
        bazarrApiProvider.overrideWith((Ref ref, Instance _) async => api),
        bazarrSystemStatusProvider.overrideWith(
          (Ref ref, Instance _) async =>
              BazarrSystemStatus(bazarrVersion: version),
        ),
        bazarrJobWatchConfigProvider.overrideWithValue(
          JobWatchConfig(
            schedule: scheduler.schedule,
            now: () => scheduler.now,
            interval: const Duration(seconds: 1),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      bazarrActivityProvider(bazarr.id),
      (BazarrActivityState? _, BazarrActivityState __) {},
    );
    return container;
  }

  BazarrActivity activity(ProviderContainer c) =>
      c.read(bazarrActivityProvider(bazarr.id).notifier);

  BazarrActivityState stateOf(ProviderContainer c) =>
      c.read(bazarrActivityProvider(bazarr.id));

  Future<void> advance(int ms) async {
    await scheduler.advance(Duration(milliseconds: ms));
    await pump();
  }

  Future<void> listenToWatched(ProviderContainer c) async {
    c.listen(settledProvider, (AsyncValue<int>? _, AsyncValue<int> __) {});
    c.listen(loadingProvider, (AsyncValue<int>? _, AsyncValue<int> __) {});
    await c.read(settledProvider.future);
    await pump();
  }

  test(
      'a midway refresh skips a loading provider and invalidates a settled '
      'one; the final refresh invalidates every provider that exists',
      () async {
    final ProviderContainer c = makeContainer();
    await listenToWatched(c);
    expect(settledBuilds, 1);
    expect(loadingBuilds, 1);

    final List<List<int>> queue = <List<int>>[
      <int>[1],
      <int>[],
      <int>[],
    ];
    api.jobs = () => queue.isEmpty ? <int>[] : queue.removeAt(0);

    activity(c).track(<WatchedProvider>[
      settledProvider,
      loadingProvider,
      unwatchedProvider,
    ]);
    await pump();
    // Immediate refresh: everything that exists, loading or not.
    expect(settledBuilds, 2);
    expect(loadingBuilds, 2);
    expect(unwatchedBuilds, 0);
    expect(stateOf(c).jobsActive, isTrue);

    await advance(1000); // [1]
    expect(settledBuilds, 2);

    await advance(1000); // [] — job 1 ended: midway
    expect(settledBuilds, 3);
    expect(loadingBuilds, 2, reason: 'a loading provider is left to finish');
    expect(unwatchedBuilds, 0, reason: 'a provider nobody uses stays off');

    await advance(1000); // [] again — final
    expect(settledBuilds, 4);
    expect(loadingBuilds, 3);
    expect(unwatchedBuilds, 0);
    expect(stateOf(c).jobsActive, isFalse);
    expect(api.jobCalls, 3);
  });

  test('busy is counted per request and cleared when the queue drains',
      () async {
    final ProviderContainer c = makeContainer();
    await listenToWatched(c);
    bool queueBusy = true;
    api.jobs = () => queueBusy ? <int>[5] : <int>[];

    final Completer<void> first = Completer<void>();
    final Completer<void> second = Completer<void>();
    final Future<void> a = activity(c).run<void>(
      'm12:en',
      (BazarrApi _) => first.future,
      refresh: <WatchedProvider>[settledProvider],
    );
    final Future<void> b = activity(c).run<void>(
      'm12:en',
      (BazarrApi _) => second.future,
      refresh: <WatchedProvider>[settledProvider],
    );
    await pump();
    expect(stateOf(c).inFlight['m12:en'], 2);
    expect(stateOf(c).isBusy('m12:en'), isTrue);
    expect(stateOf(c).isBusy('m13:en'), isFalse);

    first.complete();
    await a;
    expect(stateOf(c).inFlight['m12:en'], 1);
    expect(stateOf(c).awaitingJob, <String>{'m12:en'});
    expect(stateOf(c).jobsActive, isTrue);

    second.complete();
    await b;
    expect(stateOf(c).inFlight.containsKey('m12:en'), isFalse);
    expect(stateOf(c).isBusy('m12:en'), isTrue, reason: 'awaiting its job');

    await advance(1000); // [5]
    expect(stateOf(c).isBusy('m12:en'), isTrue);

    queueBusy = false;
    await advance(1000); // [] — job ended
    expect(stateOf(c).isBusy('m12:en'), isTrue);
    await advance(1000); // [] again — drained
    expect(stateOf(c).isBusy('m12:en'), isFalse);
    expect(stateOf(c).awaitingJob, isEmpty);
    expect(stateOf(c).jobsActive, isFalse);
  });

  test('a failed request releases its row and rethrows', () async {
    final ProviderContainer c = makeContainer();
    final Completer<void> request = Completer<void>();
    final Future<void> run = activity(c).run<void>(
      's1',
      (BazarrApi _) => request.future,
      refresh: <WatchedProvider>[settledProvider],
    );
    await pump();
    expect(stateOf(c).isBusy('s1'), isTrue);

    request.completeError(StateError('boom'));
    await expectLater(run, throwsStateError);
    expect(stateOf(c).isBusy('s1'), isFalse);
    expect(stateOf(c).inFlight, isEmpty);
    expect(stateOf(c).awaitingJob, isEmpty);
    expect(stateOf(c).jobsActive, isFalse);
    expect(scheduler.pending, 0);
  });

  test('a request without providers to refresh is busy only while it runs',
      () async {
    final ProviderContainer c = makeContainer();
    final int result = await activity(c).run<int>(
      'x',
      (BazarrApi _) async => 7,
      refresh: const <WatchedProvider>[],
    );
    expect(result, 7);
    expect(stateOf(c).isBusy('x'), isFalse);
    expect(stateOf(c).jobsActive, isFalse);
  });

  test('the action gets the instance API', () async {
    final ProviderContainer c = makeContainer();
    final BazarrApi got = await activity(c).run<BazarrApi>(
      'x',
      (BazarrApi a) async => a,
      refresh: const <WatchedProvider>[],
    );
    expect(got, same(api));
  });

  test('a Bazarr older than 1.5.6 gets timed refreshes without polling',
      () async {
    final ProviderContainer c = makeContainer(version: '1.5.5');
    c.listen(
      bazarrSystemStatusProvider(bazarr),
      (AsyncValue<BazarrSystemStatus>? _, AsyncValue<BazarrSystemStatus> __) {},
    );
    await c.read(bazarrSystemStatusProvider(bazarr).future);
    await listenToWatched(c);

    activity(c).track(<WatchedProvider>[settledProvider]);
    await pump();
    expect(settledBuilds, 2);

    await advance(2000); // first tick: no job list → fallback
    expect(api.jobCalls, 0);
    expect(stateOf(c).jobsActive, isFalse);
    expect(settledBuilds, 2);

    await advance(3000);
    expect(settledBuilds, 3);
    await advance(7000);
    expect(settledBuilds, 4);
    await advance(20000);
    expect(settledBuilds, 5);
  });

  test('editing the instance resets busy rows and ignores late completions',
      () async {
    final ProviderContainer c = makeContainer();
    api.jobs = () => <int>[5];

    await activity(c).run<void>(
      'done',
      (BazarrApi _) async {},
      refresh: <WatchedProvider>[settledProvider],
    );
    final Completer<void> slow = Completer<void>();
    final Future<void> pending = activity(c).run<void>(
      'late',
      (BazarrApi _) => slow.future,
      refresh: <WatchedProvider>[settledProvider],
    );
    await pump();
    expect(stateOf(c).isBusy('done'), isTrue);
    expect(stateOf(c).isBusy('late'), isTrue);
    expect(stateOf(c).jobsActive, isTrue);
    expect(scheduler.pending, 1);

    c
        .read(testInstancesProvider.notifier)
        .replace(<Instance>[bazarr.copyWith(name: 'Renamed')]);
    await pump();
    expect(stateOf(c).isBusy('done'), isFalse);
    expect(stateOf(c).isBusy('late'), isFalse);
    expect(stateOf(c).jobsActive, isFalse);
    expect(scheduler.pending, 0, reason: 'the old watch is disposed');

    slow.complete();
    await pending;
    await pump();
    expect(stateOf(c).isBusy('late'), isFalse);
    expect(stateOf(c).awaitingJob, isEmpty);
    expect(scheduler.pending, 0);
  });

  test('a removed instance makes actions fail', () async {
    final ProviderContainer c = makeContainer();
    c.read(testInstancesProvider.notifier).replace(const <Instance>[]);
    await pump();
    await expectLater(
      activity(c).run<void>(
        'x',
        (BazarrApi _) async {},
        refresh: <WatchedProvider>[settledProvider],
      ),
      throwsStateError,
    );
    expect(stateOf(c).isBusy('x'), isFalse);
  });
}
