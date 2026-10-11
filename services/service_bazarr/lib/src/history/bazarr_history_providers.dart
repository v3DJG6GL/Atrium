import 'package:core_models/core_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../bazarr_api.dart';
import '../bazarr_providers.dart';
import '../models/bazarr_models.dart';
import '../subtitles/bazarr_activity.dart';
import 'bazarr_history_logic.dart';

/// One history stream of one Bazarr: its movies or its episodes.
typedef BazarrHistoryStreamKey = ({Instance instance, HistoryKind kind});

/// The loaded pages of one history stream.
@immutable
class BazarrHistoryStream {
  const BazarrHistoryStream({
    required this.items,
    required this.total,
    this.exhausted = false,
    this.loadingMore = false,
    this.pageError,
  });

  /// Every entry loaded so far, newest first.
  final List<BazarrHistoryItem> items;

  /// The stream's size as Bazarr last reported it.
  final int total;

  /// True once a page came back empty: nothing more to load, whatever
  /// [total] says.
  final bool exhausted;

  /// True while the next page loads.
  final bool loadingMore;

  /// Why the last next-page request failed; cleared by the next attempt.
  final Object? pageError;

  bool get hasMore => !exhausted && items.length < total;

  BazarrHistoryStream copyWith({
    bool? loadingMore,
    Object? pageError,
    bool clearPageError = false,
  }) =>
      BazarrHistoryStream(
        items: items,
        total: total,
        exhausted: exhausted,
        loadingMore: loadingMore ?? this.loadingMore,
        pageError: clearPageError ? null : (pageError ?? this.pageError),
      );
}

/// One history stream, a page (Bazarr's default 50) at a time. Kept alive so the History tab
/// keeps its pages across tab switches; invalidating it (pull to refresh, the
/// activity watcher) reloads the first page.
final bazarrHistoryStreamProvider = AsyncNotifierProvider.family<
    BazarrHistoryStreamNotifier, BazarrHistoryStream, BazarrHistoryStreamKey>(
  BazarrHistoryStreamNotifier.new,
  retry: (int _, Object __) => null,
);

class BazarrHistoryStreamNotifier extends AsyncNotifier<BazarrHistoryStream> {
  BazarrHistoryStreamNotifier(this.key);

  final BazarrHistoryStreamKey key;

  // Bumped on every build, so a page requested before a refresh never lands
  // on the refreshed list.
  int _generation = 0;

  @override
  Future<BazarrHistoryStream> build() async {
    _generation++;
    final BazarrApi api =
        await ref.watch(bazarrApiProvider(key.instance).future);
    final BazarrHistoryPage page = await api.getHistoryPage(
      movies: key.kind == HistoryKind.movie,
    );
    return BazarrHistoryStream(
      items: page.items,
      total: page.total,
      exhausted: page.items.isEmpty,
    );
  }

  /// Appends the next page. Does nothing while the stream (re)loads, while a
  /// page is loading, or when there's nothing left. A failed page keeps the
  /// list and records [BazarrHistoryStream.pageError]; the next call tries
  /// again.
  Future<void> loadMore() async {
    // A refresh is running: its first page replaces what's loaded, so a page
    // fetched now would be appended to stale entries. The tab asks again
    // once it settles.
    if (state.isLoading) {
      return;
    }
    final BazarrHistoryStream? current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) {
      return;
    }
    final int generation = _generation;
    state = AsyncData<BazarrHistoryStream>(
      current.copyWith(loadingMore: true, clearPageError: true),
    );
    try {
      final BazarrApi api =
          await ref.read(bazarrApiProvider(key.instance).future);
      final BazarrHistoryPage page = await api.getHistoryPage(
        movies: key.kind == HistoryKind.movie,
        start: current.items.length,
      );
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = AsyncData<BazarrHistoryStream>(
        BazarrHistoryStream(
          items: <BazarrHistoryItem>[...current.items, ...page.items],
          total: page.total,
          exhausted: page.items.isEmpty,
        ),
      );
    } on Object catch (e) {
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = AsyncData<BazarrHistoryStream>(
        current.copyWith(loadingMore: false, pageError: e),
      );
    }
  }
}

/// Every history stream of [bazarr], for the activity watcher to refresh
/// after a subtitle action.
List<WatchedProvider> bazarrHistoryRefresh(Instance bazarr) =>
    <WatchedProvider>[
      for (final HistoryKind kind in HistoryKind.values)
        bazarrHistoryStreamProvider((instance: bazarr, kind: kind)),
    ];

/// Which history the History tab shows.
enum BazarrHistoryFilter {
  all('All'),
  movies('Movies'),
  episodes('Episodes');

  const BazarrHistoryFilter(this.label);

  final String label;

  /// The streams this filter reads.
  List<HistoryKind> get kinds => switch (this) {
        BazarrHistoryFilter.all => HistoryKind.values,
        BazarrHistoryFilter.movies => const <HistoryKind>[HistoryKind.movie],
        BazarrHistoryFilter.episodes => const <HistoryKind>[
            HistoryKind.episode,
          ],
      };
}

/// The History tab's filter per Bazarr; survives tab switches.
final bazarrHistoryFilterProvider = NotifierProvider.family<
    BazarrHistoryFilterNotifier, BazarrHistoryFilter, Instance>(
  BazarrHistoryFilterNotifier.new,
);

class BazarrHistoryFilterNotifier extends Notifier<BazarrHistoryFilter> {
  BazarrHistoryFilterNotifier(this.instance);

  final Instance instance;

  @override
  BazarrHistoryFilter build() => BazarrHistoryFilter.all;

  void set(BazarrHistoryFilter filter) => state = filter;
}

/// The clock the History tab's day groups ("Today", "Yesterday") use.
final bazarrHistoryClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

/// One row of the History list: a day header or an entry.
@immutable
sealed class BazarrHistoryRow {
  const BazarrHistoryRow();
}

final class BazarrHistoryDayRow extends BazarrHistoryRow {
  const BazarrHistoryDayRow(this.group);

  final HistoryDayGroup group;
}

final class BazarrHistoryEntryRow extends BazarrHistoryRow {
  const BazarrHistoryEntryRow(this.entry);

  final HistoryEntry entry;
}

/// What the History tab shows for the current filter.
@immutable
class BazarrHistoryView {
  const BazarrHistoryView({
    required this.filter,
    required this.rows,
    required this.entryCount,
    required this.waiting,
    required this.error,
    required this.loadingMore,
    required this.toPage,
    required this.failedPages,
  });

  final BazarrHistoryFilter filter;

  /// Day headers and entries, newest first.
  final List<BazarrHistoryRow> rows;

  /// Entries in [rows].
  final int entryCount;

  /// True until every stream the filter reads has its first page (or
  /// failed): showing the faster stream in full would drop most of it again
  /// once the slower one lands.
  final bool waiting;

  /// The first error of a stream the filter reads: its first page, a
  /// refresh, or a next page.
  final Object? error;

  /// True while a stream loads its next page.
  final bool loadingMore;

  /// The streams "load more" pages; empty when there's nothing left.
  final List<HistoryKind> toPage;

  /// Streams whose last next-page request failed. Only a scroll retries
  /// them, so a broken page doesn't loop.
  final Set<HistoryKind> failedPages;

  bool get hasMore => toPage.isNotEmpty;
}

/// The merged, day-grouped history of [instance] for its current filter.
/// Watches only the streams that filter reads.
final bazarrHistoryViewProvider =
    Provider.autoDispose.family<BazarrHistoryView, Instance>(
  (Ref ref, Instance instance) {
    final BazarrHistoryFilter filter =
        ref.watch(bazarrHistoryFilterProvider(instance));
    final DateTime now = ref.watch(bazarrHistoryClockProvider)();
    final Map<HistoryKind, AsyncValue<BazarrHistoryStream>> streams =
        <HistoryKind, AsyncValue<BazarrHistoryStream>>{
      for (final HistoryKind kind in filter.kinds)
        kind: ref.watch(
          bazarrHistoryStreamProvider((instance: instance, kind: kind)),
        ),
    };

    List<BazarrHistoryItem> itemsOf(HistoryKind kind) =>
        streams[kind]?.value?.items ?? const <BazarrHistoryItem>[];
    bool moreOf(HistoryKind kind) => streams[kind]?.value?.hasMore ?? false;

    final bool waiting = streams.values.any(
      (AsyncValue<BazarrHistoryStream> s) => !s.hasValue && !s.hasError,
    );
    Object? error;
    for (final AsyncValue<BazarrHistoryStream> s in streams.values) {
      error ??= s.error ?? s.value?.pageError;
    }
    final HistoryStreamFlags more = (
      movies: moreOf(HistoryKind.movie),
      episodes: moreOf(HistoryKind.episode),
    );
    final List<BazarrHistoryItem> movies = itemsOf(HistoryKind.movie);
    final List<BazarrHistoryItem> episodes = itemsOf(HistoryKind.episode);

    final List<HistoryEntry> entries = waiting
        ? const <HistoryEntry>[]
        : mergeHistoryStreams(movies, episodes, more);
    final List<BazarrHistoryRow> rows = <BazarrHistoryRow>[
      for (final HistoryDayGroup group
          in groupHistoryByDay(entries, now: now)) ...<BazarrHistoryRow>[
        BazarrHistoryDayRow(group),
        for (final HistoryEntry entry in group.entries)
          BazarrHistoryEntryRow(entry),
      ],
    ];
    final HistoryStreamFlags page =
        historyStreamsToPage(movies, episodes, more);
    return BazarrHistoryView(
      filter: filter,
      rows: rows,
      entryCount: entries.length,
      waiting: waiting,
      error: error,
      loadingMore: streams.values.any(
        (AsyncValue<BazarrHistoryStream> s) => s.value?.loadingMore ?? false,
      ),
      toPage: waiting
          ? const <HistoryKind>[]
          : <HistoryKind>[
              if (page.movies) HistoryKind.movie,
              if (page.episodes) HistoryKind.episode,
            ],
      failedPages: <HistoryKind>{
        for (final MapEntry<HistoryKind, AsyncValue<BazarrHistoryStream>> s
            in streams.entries)
          if (s.value.value?.pageError != null) s.key,
      },
    );
  },
);

/// Keys of the history entries blacklisted from this app, per Bazarr: an
/// entry's own flag only flips once history refetches, which can take the
/// whole replacement search.
final bazarrHistoryBlacklistedProvider =
    NotifierProvider.family<BazarrHistoryBlacklisted, Set<String>, Instance>(
  BazarrHistoryBlacklisted.new,
);

class BazarrHistoryBlacklisted extends Notifier<Set<String>> {
  BazarrHistoryBlacklisted(this.instance);

  final Instance instance;

  @override
  Set<String> build() => const <String>{};

  void add(String key) {
    if (ref.mounted) {
      state = <String>{...state, key};
    }
  }

  void remove(String key) {
    if (ref.mounted) {
      state = <String>{...state.where((String k) => k != key)};
    }
  }
}
