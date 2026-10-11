import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/bazarr_api.dart';
import 'package:service_bazarr/src/bazarr_providers.dart';
import 'package:service_bazarr/src/history/bazarr_history_logic.dart';
import 'package:service_bazarr/src/history/bazarr_history_providers.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';

const Instance bazarr = Instance(
  id: 'bazarr-1',
  name: 'Bazarr Test',
  kind: ServiceKind.bazarr,
  localUrl: 'http://localhost:6767',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'dummy-api-key'),
);

/// Serves history pages; a request whose (movies?, start) is in [gates]
/// waits for that completer.
class GatedBazarrApi extends BazarrApi {
  GatedBazarrApi({required this.movies, required this.episodes}) : super(Dio());

  List<BazarrHistoryItem> movies;
  List<BazarrHistoryItem> episodes;
  final Map<(bool, int), Completer<void>> gates =
      <(bool, int), Completer<void>>{};
  final Set<bool> failing = <bool>{};
  final List<(bool, int)> requests = <(bool, int)>[];

  @override
  Future<BazarrHistoryPage> getHistoryPage({
    required bool movies,
    int start = 0,
    int length = 50,
  }) async {
    requests.add((movies, start));
    await gates[(movies, start)]?.future;
    if (failing.contains(movies)) {
      throw StateError('history down');
    }
    final List<BazarrHistoryItem> all = movies ? this.movies : episodes;
    return BazarrHistoryPage(
      items: start >= all.length
          ? const <BazarrHistoryItem>[]
          : all.sublist(start, (start + length).clamp(0, all.length)),
      total: all.length,
    );
  }
}

List<BazarrHistoryItem> moviesNamed(String prefix, int count) =>
    <BazarrHistoryItem>[
      for (int i = 0; i < count; i++)
        BazarrHistoryItem(
          title: '$prefix $i',
          action: 1,
          radarrId: i + 1,
          parsedTimestamp:
              '10/12/26 ${(11 - i ~/ 60).toString().padLeft(2, '0')}'
              ':${(59 - i % 60).toString().padLeft(2, '0')}:00',
        ),
    ];

void main() {
  const BazarrHistoryStreamKey movieKey =
      (instance: bazarr, kind: HistoryKind.movie);

  ProviderContainer makeContainer(
    GatedBazarrApi api, {
    BazarrHistoryFilter filter = BazarrHistoryFilter.all,
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        bazarrApiProvider.overrideWith((Ref ref, Instance _) async => api),
      ],
    );
    addTearDown(container.dispose);
    container.read(bazarrHistoryFilterProvider(bazarr).notifier).set(filter);
    container.listen(
      bazarrHistoryViewProvider(bazarr),
      (BazarrHistoryView? _, BazarrHistoryView __) {},
    );
    return container;
  }

  BazarrHistoryStream streamOf(ProviderContainer c) =>
      c.read(bazarrHistoryStreamProvider(movieKey)).requireValue;

  test('"All" shows nothing until both first pages arrived', () async {
    final GatedBazarrApi api = GatedBazarrApi(
      movies: moviesNamed('Movie', 3),
      episodes: const <BazarrHistoryItem>[
        BazarrHistoryItem(
          seriesTitle: 'Show',
          action: 1,
          sonarrSeriesId: 1,
          sonarrEpisodeId: 1,
          parsedTimestamp: '10/12/26 08:00:00',
        ),
      ],
    );
    final Completer<void> episodes = Completer<void>();
    api.gates[(false, 0)] = episodes;
    final ProviderContainer c = makeContainer(api);

    await c.read(bazarrHistoryStreamProvider(movieKey).future);
    BazarrHistoryView view = c.read(bazarrHistoryViewProvider(bazarr));
    expect(view.waiting, isTrue);
    expect(view.rows, isEmpty);

    episodes.complete();
    await c.read(
      bazarrHistoryStreamProvider((instance: bazarr, kind: HistoryKind.episode))
          .future,
    );
    view = c.read(bazarrHistoryViewProvider(bazarr));
    expect(view.waiting, isFalse);
    expect(view.entryCount, 4);
  });

  test('the Movies filter loads only the movie stream', () async {
    final GatedBazarrApi api = GatedBazarrApi(
      movies: moviesNamed('Movie', 3),
      episodes: const <BazarrHistoryItem>[],
    );
    final ProviderContainer c =
        makeContainer(api, filter: BazarrHistoryFilter.movies);
    await c.read(bazarrHistoryStreamProvider(movieKey).future);

    expect(api.requests, <(bool, int)>[(true, 0)]);
    expect(c.read(bazarrHistoryViewProvider(bazarr)).entryCount, 3);
  });

  test('a refresh during loadMore drops the stale page', () async {
    final GatedBazarrApi api = GatedBazarrApi(
      movies: moviesNamed('Movie', 120),
      episodes: const <BazarrHistoryItem>[],
    );
    final ProviderContainer c = makeContainer(api);
    await c.read(bazarrHistoryStreamProvider(movieKey).future);
    expect(streamOf(c).items, hasLength(50));

    final Completer<void> page = Completer<void>();
    api.gates[(true, 50)] = page;
    final Future<void> loading =
        c.read(bazarrHistoryStreamProvider(movieKey).notifier).loadMore();
    await Future<void>(() {});
    expect(streamOf(c).loadingMore, isTrue);

    // The library changed: the refresh's first page has new titles.
    api.movies = moviesNamed('Fresh', 120);
    c.invalidate(bazarrHistoryStreamProvider(movieKey));
    await c.read(bazarrHistoryStreamProvider(movieKey).future);
    page.complete();
    await loading;

    final BazarrHistoryStream stream = streamOf(c);
    expect(stream.items, hasLength(50));
    expect(stream.items.first.title, 'Fresh 0');
    expect(stream.loadingMore, isFalse);
  });

  test('loadMore waits while the stream refreshes', () async {
    final GatedBazarrApi api = GatedBazarrApi(
      movies: moviesNamed('Movie', 120),
      episodes: const <BazarrHistoryItem>[],
    );
    final ProviderContainer c = makeContainer(api);
    await c.read(bazarrHistoryStreamProvider(movieKey).future);

    final Completer<void> refresh = Completer<void>();
    api.gates[(true, 0)] = refresh;
    c.invalidate(bazarrHistoryStreamProvider(movieKey));
    c.read(bazarrHistoryStreamProvider(movieKey));
    await c.read(bazarrHistoryStreamProvider(movieKey).notifier).loadMore();

    expect(api.requests.where(((bool, int) r) => r.$2 == 50), isEmpty);

    refresh.complete();
    await c.read(bazarrHistoryStreamProvider(movieKey).future);
    await c.read(bazarrHistoryStreamProvider(movieKey).notifier).loadMore();
    expect(streamOf(c).items, hasLength(100));
  });

  test('a failed page keeps the list and is reported', () async {
    final GatedBazarrApi api = GatedBazarrApi(
      movies: moviesNamed('Movie', 120),
      episodes: const <BazarrHistoryItem>[],
    );
    final ProviderContainer c =
        makeContainer(api, filter: BazarrHistoryFilter.movies);
    await c.read(bazarrHistoryStreamProvider(movieKey).future);

    api.failing.add(true);
    await c.read(bazarrHistoryStreamProvider(movieKey).notifier).loadMore();

    expect(streamOf(c).items, hasLength(50));
    expect(streamOf(c).pageError, isA<StateError>());
    final BazarrHistoryView view = c.read(bazarrHistoryViewProvider(bazarr));
    expect(view.failedPages, <HistoryKind>{HistoryKind.movie});
    expect(view.error, isA<StateError>());

    api.failing.clear();
    await c.read(bazarrHistoryStreamProvider(movieKey).notifier).loadMore();
    expect(streamOf(c).items, hasLength(100));
    expect(streamOf(c).pageError, isNull);
  });

  test('one failed stream still shows the other, with the error', () async {
    final GatedBazarrApi api = GatedBazarrApi(
      movies: moviesNamed('Movie', 3),
      episodes: const <BazarrHistoryItem>[],
    )..failing.add(false);
    final ProviderContainer c = makeContainer(api);
    await c.read(bazarrHistoryStreamProvider(movieKey).future);
    await expectLater(
      c.read(
        bazarrHistoryStreamProvider(
          (instance: bazarr, kind: HistoryKind.episode),
        ).future,
      ),
      throwsStateError,
    );

    final BazarrHistoryView view = c.read(bazarrHistoryViewProvider(bazarr));
    expect(view.waiting, isFalse);
    expect(view.entryCount, 3);
    expect(view.error, isA<StateError>());
  });

  test('bazarrHistoryRefresh lists both streams', () {
    expect(bazarrHistoryRefresh(bazarr), <Object>[
      bazarrHistoryStreamProvider(movieKey),
      bazarrHistoryStreamProvider(
        (instance: bazarr, kind: HistoryKind.episode),
      ),
    ]);
  });
}
