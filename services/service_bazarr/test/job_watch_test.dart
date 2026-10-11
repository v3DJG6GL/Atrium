import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/subtitles/job_watch.dart';

import 'support/fake_scheduler.dart';

typedef RefreshCall<K> = ({List<K> keys, bool midway});

class Harness<K> {
  Harness(
    List<List<int>?> queue, {
    Duration maxDuration = const Duration(seconds: 60),
    Duration interval = const Duration(seconds: 1),
    List<Duration> fallbackDelays = const <Duration>[
      Duration(seconds: 3),
      Duration(seconds: 10),
    ],
    Object? Function(int call)? throwOn,
  }) {
    watch = JobWatch<K>(
      fetchActiveJobIds: () async {
        fetches++;
        final Object? error = throwOn?.call(fetches);
        if (error != null) {
          throw error;
        }
        return _call < queue.length ? queue[_call++] : <int>[];
      },
      refresh: (List<K> keys, {required bool midway}) =>
          refreshes.add((keys: List<K>.of(keys), midway: midway)),
      onActiveChange: activeChanges.add,
      schedule: scheduler.schedule,
      now: () => scheduler.now,
      interval: interval,
      maxDuration: maxDuration,
      fallbackDelays: fallbackDelays,
    );
  }

  final FakeScheduler scheduler = FakeScheduler();
  final List<RefreshCall<K>> refreshes = <RefreshCall<K>>[];
  final List<bool> activeChanges = <bool>[];
  late final JobWatch<K> watch;
  int fetches = 0;
  int _call = 0;

  Future<void> advance(int ms) => scheduler.advance(Duration(milliseconds: ms));
}

void main() {
  test(
      'refreshes at once, again when a job ends, and stops once the queue '
      'stays empty', () async {
    final Harness<String> h = Harness<String>(<List<int>?>[
      <int>[7],
      <int>[7],
      <int>[],
      <int>[],
    ]);
    h.watch.track(<String>['movie-1']);
    expect(h.refreshes, hasLength(1));
    expect(h.refreshes.last.midway, isFalse);

    await h.advance(1000); // [7]
    await h.advance(1000); // [7]
    expect(h.refreshes, hasLength(1));

    await h.advance(1000); // [] — job 7 ended
    expect(h.refreshes, hasLength(2));

    await h.advance(1000); // [] again — done
    expect(h.refreshes, hasLength(3));
    expect(h.refreshes.last.keys, <String>['movie-1']);
    expect(h.refreshes.last.midway, isFalse);

    await h.advance(5000);
    expect(h.fetches, 4);
    expect(h.watch.active, isFalse);
  });

  test('merges keys tracked while polling', () async {
    final Harness<String> h = Harness<String>(<List<int>?>[
      <int>[1],
      <int>[],
      <int>[],
    ]);
    h.watch.track(<String>['a']);
    await h.advance(1000);
    h.watch.track(<String>['b']);
    await h.advance(1000);
    await h.advance(1000);
    expect(h.refreshes.last.keys, <String>['a', 'b']);
    expect(h.refreshes.last.midway, isFalse);
  });

  test('gives up at the deadline with a final refresh', () async {
    final Harness<String> h = Harness<String>(
      List<List<int>?>.generate(50, (_) => <int>[9]),
      maxDuration: const Duration(seconds: 3),
    );
    h.watch.track(<String>['x']);
    await h.advance(1000);
    await h.advance(1000);
    await h.advance(1000);
    expect(h.refreshes, hasLength(2));
    final int calls = h.fetches;
    await h.advance(5000);
    expect(h.fetches, calls);
  });

  test('lets a long action extend the deadline, never shorten it', () async {
    final Harness<String> h = Harness<String>(
      List<List<int>?>.generate(50, (_) => <int>[9]),
      maxDuration: const Duration(seconds: 3),
    );
    h.watch.track(<String>['all'], maxDuration: const Duration(seconds: 10));
    h.watch.track(<String>['row']);
    for (int i = 0; i < 5; i++) {
      await h.advance(1000);
    }
    expect(h.refreshes, hasLength(2)); // both tracks, no final yet
    for (int i = 0; i < 5; i++) {
      await h.advance(1000);
    }
    expect(h.refreshes, hasLength(3)); // final refresh at 10s
  });

  test('marks refreshes while jobs still run as midway', () async {
    final Harness<String> h = Harness<String>(<List<int>?>[
      <int>[1, 2],
      <int>[2],
      <int>[],
      <int>[],
    ]);
    h.watch.track(<String>['x']);
    await h.advance(1000); // [1, 2]
    await h.advance(1000); // [2] — job 1 ended, more to come
    expect(h.refreshes.last.keys, <String>['x']);
    expect(h.refreshes.last.midway, isTrue);
    await h.advance(1000); // []
    await h.advance(1000); // [] — done
    expect(h.refreshes.last.keys, <String>['x']);
    expect(h.refreshes.last.midway, isFalse);
  });

  test('tracks a key once however often it is passed, compared by value',
      () async {
    final Harness<(String, String, String, String)> h =
        Harness<(String, String, String, String)>(<List<int>?>[
      <int>[1],
      <int>[],
      <int>[],
    ]);
    h.watch.track(<(String, String, String, String)>[
      ('bazarr', 'b1', 'movie', '1'),
    ]);
    h.watch.track(<(String, String, String, String)>[
      ('bazarr', 'b1', 'movie', '1'),
    ]);
    await h.advance(1000);
    await h.advance(1000);
    await h.advance(1000);
    expect(
      h.refreshes.last.keys,
      <(String, String, String, String)>[('bazarr', 'b1', 'movie', '1')],
    );
  });

  test('falls back to timed refreshes without a job list', () async {
    final Harness<String> h = Harness<String>(<List<int>?>[null]);
    h.watch.track(<String>['x']);
    await h.advance(1000);
    expect(h.refreshes, hasLength(1));
    expect(h.watch.active, isFalse);
    await h.advance(3000);
    expect(h.refreshes, hasLength(2));
    expect(h.refreshes.last.midway, isFalse);
    await h.advance(7000);
    expect(h.refreshes, hasLength(3));
    await h.advance(60000);
    expect(h.refreshes, hasLength(3));
    expect(h.fetches, 1);
  });

  test('reports when it starts and stops working', () async {
    final Harness<String> h = Harness<String>(<List<int>?>[
      <int>[1],
      <int>[],
      <int>[],
    ]);
    h.watch.track(<String>['a']);
    h.watch.track(<String>['b']);
    expect(h.activeChanges, <bool>[true]);
    expect(h.watch.active, isTrue);
    await h.advance(1000);
    await h.advance(1000);
    await h.advance(1000);
    expect(h.activeChanges, <bool>[true, false]);
    expect(h.watch.active, isFalse);
  });

  test('does nothing after dispose', () async {
    final Harness<String> h = Harness<String>(<List<int>?>[
      <int>[1],
      <int>[],
      <int>[],
    ]);
    h.watch.track(<String>['x']);
    h.watch.dispose();
    await h.advance(5000);
    h.watch.track(<String>['y']);
    expect(h.refreshes, hasLength(1));
    expect(h.scheduler.pending, 0);
  });

  test('ignores a failed poll and keeps polling', () async {
    final Harness<String> h = Harness<String>(
      <List<int>?>[
        <int>[1],
        <int>[],
        <int>[],
      ],
      throwOn: (int call) => call == 1 ? StateError('offline') : null,
    );
    h.watch.track(<String>['x']);
    await h.advance(1000); // throws — ignored
    expect(h.refreshes, hasLength(1));
    expect(h.watch.active, isTrue);
    await h.advance(1000); // [1]
    await h.advance(1000); // [] — job ended
    await h.advance(1000); // [] — done
    expect(h.refreshes, hasLength(3));
    expect(h.refreshes[1].midway, isTrue);
    expect(h.refreshes[2].midway, isFalse);
  });

  test('dispose cancels pending fallback refreshes', () async {
    final Harness<String> h = Harness<String>(<List<int>?>[null]);
    h.watch.track(<String>['x']);
    await h.advance(1000);
    expect(h.scheduler.pending, 2);
    h.watch.dispose();
    expect(h.scheduler.pending, 0);
    await h.advance(30000);
    expect(h.refreshes, hasLength(1));
  });

  test('dispose during a poll stops without refreshing', () async {
    final Harness<String> h = Harness<String>(<List<int>?>[
      <int>[1],
      <int>[],
    ]);
    h.watch.track(<String>['x']);
    await h.advance(1000);
    h.scheduler.runNext(); // starts the second poll
    h.watch.dispose();
    await h.advance(0);
    expect(h.refreshes, hasLength(1));
    expect(h.scheduler.pending, 0);
  });
}
