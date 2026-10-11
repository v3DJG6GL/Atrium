import 'package:core_models/core_models.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../bazarr_providers.dart';
import '../models/bazarr_models.dart';
import 'bazarr_library_logic.dart';

/// What the Library tab of one Bazarr shows: the kind, each kind's filter
/// chip, a coverage bar's language filter, the (debounced) search and the
/// series rows expanded to their missing episodes.
@immutable
class BazarrLibraryUiState {
  const BazarrLibraryUiState({
    this.kind = BazarrLibraryKind.movies,
    this.movieFilter = LibraryFilter.all,
    this.seriesFilter = LibraryFilter.all,
    this.languageFilter,
    this.query = '',
    this.expanded = const <int>{},
  });

  final BazarrLibraryKind kind;
  final LibraryFilter movieFilter;
  final LibraryFilter seriesFilter;

  /// Movies only.
  final LanguageFilter? languageFilter;
  final String query;

  /// Sonarr series ids.
  final Set<int> expanded;

  /// The chip of the kind on screen.
  LibraryFilter get filter =>
      kind == BazarrLibraryKind.movies ? movieFilter : seriesFilter;

  bool get searching => query.trim().isNotEmpty;

  /// Something narrows the list: "No … match" rather than "no … yet".
  bool get filtered =>
      filter != LibraryFilter.all || languageFilter != null || searching;

  BazarrLibraryUiState copyWith({
    BazarrLibraryKind? kind,
    LibraryFilter? movieFilter,
    LibraryFilter? seriesFilter,
    LanguageFilter? Function()? languageFilter,
    String? query,
    Set<int>? expanded,
  }) =>
      BazarrLibraryUiState(
        kind: kind ?? this.kind,
        movieFilter: movieFilter ?? this.movieFilter,
        seriesFilter: seriesFilter ?? this.seriesFilter,
        languageFilter:
            languageFilter != null ? languageFilter() : this.languageFilter,
        query: query ?? this.query,
        expanded: expanded ?? this.expanded,
      );
}

/// The Library tab's state per Bazarr. Not auto-disposed, so it survives tab
/// switches.
final bazarrLibraryUiProvider = NotifierProvider.family<BazarrLibraryUi,
    BazarrLibraryUiState, Instance>(BazarrLibraryUi.new);

class BazarrLibraryUi extends Notifier<BazarrLibraryUiState> {
  BazarrLibraryUi(this.instance);

  final Instance instance;

  @override
  BazarrLibraryUiState build() => const BazarrLibraryUiState();

  /// Switches the kind, keeping each kind's chip. A language filter and
  /// expanded rows belong to the kind they were set on.
  void setKind(BazarrLibraryKind kind) {
    if (kind == state.kind) {
      return;
    }
    state = state.copyWith(
      kind: kind,
      languageFilter: () => null,
      expanded: const <int>{},
    );
  }

  /// Picks the chip of the kind on screen. Expanded rows collapse: their
  /// toggle may be gone.
  void setFilter(LibraryFilter filter) {
    state = switch (state.kind) {
      BazarrLibraryKind.movies =>
        state.copyWith(movieFilter: filter, expanded: const <int>{}),
      BazarrLibraryKind.series =>
        state.copyWith(seriesFilter: filter, expanded: const <int>{}),
    };
  }

  /// A tap on [code2]'s coverage bar.
  void cycleLanguage(String code2) {
    state = state.copyWith(
      languageFilter: () => nextLanguageFilter(state.languageFilter, code2),
    );
  }

  void setQuery(String query) {
    if (query == state.query) {
      return;
    }
    state = state.copyWith(query: query);
  }

  void toggleExpanded(int seriesId) {
    final Set<int> next = Set<int>.of(state.expanded);
    if (!next.remove(seriesId)) {
      next.add(seriesId);
    }
    state = state.copyWith(expanded: next);
  }

  /// "Clear filters": the chip, the language filter and the search.
  void clearFilters() {
    state = switch (state.kind) {
      BazarrLibraryKind.movies => state.copyWith(
          movieFilter: LibraryFilter.all,
          languageFilter: () => null,
          query: '',
        ),
      BazarrLibraryKind.series => state.copyWith(
          seriesFilter: LibraryFilter.all,
          languageFilter: () => null,
          query: '',
        ),
    };
  }
}

/// How the Library lays out one kind: rows or posters.
enum BazarrLibraryViewMode { list, posters }

/// Arguments of [bazarrLibraryViewModeProvider].
typedef BazarrLibraryViewKey = (Instance, BazarrLibraryKind);

/// The Library's layout per Bazarr and kind, kept in the settings box.
final bazarrLibraryViewModeProvider = NotifierProvider.family<
    BazarrLibraryViewModeNotifier,
    BazarrLibraryViewMode,
    BazarrLibraryViewKey>(BazarrLibraryViewModeNotifier.new);

class BazarrLibraryViewModeNotifier extends Notifier<BazarrLibraryViewMode> {
  BazarrLibraryViewModeNotifier(this.key);

  final BazarrLibraryViewKey key;

  /// The settings-box key of [instanceId]'s layout of [kind].
  static String storageKey(String instanceId, BazarrLibraryKind kind) =>
      'bazarr.libraryView.$instanceId.${kind.name}';

  Box<String>? get _box => Hive.isBoxOpen(AtriumBoxes.settings)
      ? Hive.box<String>(AtriumBoxes.settings)
      : null;

  String get _key => storageKey(key.$1.id, key.$2);

  @override
  BazarrLibraryViewMode build() {
    final String? raw = _box?.get(_key);
    return raw == BazarrLibraryViewMode.posters.name
        ? BazarrLibraryViewMode.posters
        : BazarrLibraryViewMode.list;
  }

  void toggle() => set(
        state == BazarrLibraryViewMode.list
            ? BazarrLibraryViewMode.posters
            : BazarrLibraryViewMode.list,
      );

  void set(BazarrLibraryViewMode mode) {
    state = mode;
    _box?.put(_key, mode.name);
  }
}

// --- Derived data ---
//
// Recomputed only when the list or the profiles change (a refresh that
// keeps the loaded list doesn't), never in build().

final _moviesListProvider =
    Provider.autoDispose.family<List<BazarrMovie>?, Instance>(
  (Ref ref, Instance instance) => ref.watch(
    bazarrMoviesProvider(instance)
        .select((AsyncValue<List<BazarrMovie>> a) => a.value),
  ),
);

final _seriesListProvider =
    Provider.autoDispose.family<List<BazarrSeries>?, Instance>(
  (Ref ref, Instance instance) => ref.watch(
    bazarrSeriesProvider(instance)
        .select((AsyncValue<List<BazarrSeries>> a) => a.value),
  ),
);

/// The languages each of the Bazarr's profiles asks for.
final bazarrProfileLanguagesProvider =
    Provider.autoDispose.family<ProfileLanguages, Instance>(
  (Ref ref, Instance instance) {
    final List<BazarrLanguageProfile>? profiles = ref.watch(
      bazarrProfilesProvider(instance)
          .select((AsyncValue<List<BazarrLanguageProfile>> a) => a.value),
    );
    return profileLanguageMap(profiles ?? const <BazarrLanguageProfile>[]);
  },
);

/// The movie chips' counts.
final bazarrMovieCountsProvider =
    Provider.autoDispose.family<LibraryCounts, Instance>(
  (Ref ref, Instance instance) => filterCounts<BazarrMovie>(
    ref.watch(_moviesListProvider(instance)) ?? const <BazarrMovie>[],
    classifyMovie,
  ),
);

/// The series chips' counts.
final bazarrSeriesCountsProvider =
    Provider.autoDispose.family<LibraryCounts, Instance>(
  (Ref ref, Instance instance) => filterCounts<BazarrSeries>(
    ref.watch(_seriesListProvider(instance)) ?? const <BazarrSeries>[],
    classifySeries,
  ),
);

/// The coverage bars: every language a profile asks for across the movies.
final bazarrMovieCoverageProvider =
    Provider.autoDispose.family<List<LanguageCoverage>, Instance>(
  (Ref ref, Instance instance) => computeLanguageCoverage(
    ref.watch(_moviesListProvider(instance)) ?? const <BazarrMovie>[],
    ref.watch(bazarrProfileLanguagesProvider(instance)),
  ),
);

/// The movies' search index. Watched only while a search is active, and
/// kept across keystrokes.
final bazarrMovieSearchIndexProvider =
    Provider.autoDispose.family<LibraryIndex<BazarrMovie>, Instance>(
  (Ref ref, Instance instance) => buildLibraryIndex<BazarrMovie>(
    ref.watch(_moviesListProvider(instance)),
    (BazarrMovie m) => LibraryMatchFields(
      title: m.title,
      year: (m.year ?? 0) > 0 ? m.year : null,
    ),
  ),
);

/// The series' search index; see [bazarrMovieSearchIndexProvider].
final bazarrSeriesSearchIndexProvider =
    Provider.autoDispose.family<LibraryIndex<BazarrSeries>, Instance>(
  (Ref ref, Instance instance) => buildLibraryIndex<BazarrSeries>(
    ref.watch(_seriesListProvider(instance)),
    (BazarrSeries s) => LibraryMatchFields(
      title: s.title,
      year: (s.year ?? 0) > 0 ? s.year : null,
    ),
  ),
);

/// The movies the Library lists: searched, then the chip and the language
/// filter applied. Empty until the movies load.
final bazarrShownMoviesProvider =
    Provider.autoDispose.family<List<BazarrMovie>, Instance>(
  (Ref ref, Instance instance) {
    final (String query, LibraryFilter filter, LanguageFilter? language) =
        ref.watch(
      bazarrLibraryUiProvider(instance).select(
        (BazarrLibraryUiState s) =>
            (s.query.trim(), s.movieFilter, s.languageFilter),
      ),
    );
    final List<BazarrMovie> movies =
        ref.watch(_moviesListProvider(instance)) ?? const <BazarrMovie>[];
    final List<BazarrMovie> searched = query.isEmpty
        ? movies
        : filterLibraryIndex<BazarrMovie>(
            ref.watch(bazarrMovieSearchIndexProvider(instance)),
            query,
          );
    return filterMovies(
      searched,
      filter,
      language: language,
      profileLanguages: ref.watch(bazarrProfileLanguagesProvider(instance)),
    );
  },
);

/// The series the Library lists: searched, then the chip applied.
final bazarrShownSeriesProvider =
    Provider.autoDispose.family<List<BazarrSeries>, Instance>(
  (Ref ref, Instance instance) {
    final (String query, LibraryFilter filter) = ref.watch(
      bazarrLibraryUiProvider(instance).select(
        (BazarrLibraryUiState s) => (s.query.trim(), s.seriesFilter),
      ),
    );
    final List<BazarrSeries> series =
        ref.watch(_seriesListProvider(instance)) ?? const <BazarrSeries>[];
    final List<BazarrSeries> searched = query.isEmpty
        ? series
        : filterLibraryIndex<BazarrSeries>(
            ref.watch(bazarrSeriesSearchIndexProvider(instance)),
            query,
          );
    return filterSeries(searched, filter);
  },
);
