import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bazarr_open.dart';
import '../bazarr_providers.dart';
import '../models/bazarr_models.dart';
import '../subtitles/bazarr_activity.dart';
import 'bazarr_coverage_bars.dart';
import 'bazarr_library_actions.dart';
import 'bazarr_library_items.dart';
import 'bazarr_library_logic.dart';
import 'bazarr_library_providers.dart';

/// How long typing pauses before the list narrows.
const Duration librarySearchDebounce = Duration(milliseconds: 200);

/// Bazarr's Library: every movie or series it manages with its audio and
/// subtitle languages, not just the ones missing something. The Missing
/// filter takes over the old Wanted lists: it adds "Search all missing", a
/// search button per movie, and series rows that expand to their missing
/// episodes.
class BazarrLibraryTab extends ConsumerStatefulWidget {
  const BazarrLibraryTab({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<BazarrLibraryTab> createState() => _BazarrLibraryTabState();
}

class _BazarrLibraryTabState extends ConsumerState<BazarrLibraryTab> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(bazarrLibraryUiProvider(widget.instance)).query,
  );
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  Instance get _instance => widget.instance;

  BazarrLibraryUi get _ui =>
      ref.read(bazarrLibraryUiProvider(_instance).notifier);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      // Clearing applies at once.
      _ui.setQuery('');
      return;
    }
    _debounce = Timer(librarySearchDebounce, () => _ui.setQuery(value));
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    _ui.setQuery('');
    setState(() {});
  }

  Future<void> _refresh(BazarrLibraryKind kind) async {
    ref
      ..invalidate(bazarrProfilesProvider(_instance))
      ..invalidate(bazarrEpisodesProvider);
    switch (kind) {
      case BazarrLibraryKind.movies:
        ref.invalidate(bazarrMoviesProvider(_instance));
        await ref.read(bazarrMoviesProvider(_instance).future);
      case BazarrLibraryKind.series:
        ref.invalidate(bazarrSeriesProvider(_instance));
        await ref.read(bazarrSeriesProvider(_instance).future);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The query cleared elsewhere ("Clear filters"): drop the typed text and
    // any pending debounce with it.
    ref.listen<String>(
      bazarrLibraryUiProvider(_instance)
          .select((BazarrLibraryUiState s) => s.query),
      (String? previous, String next) {
        if (next.isEmpty && _search.text.isNotEmpty) {
          _debounce?.cancel();
          _search.clear();
          setState(() {});
        }
      },
    );
    final BazarrLibraryKind kind = ref.watch(
      bazarrLibraryUiProvider(_instance)
          .select((BazarrLibraryUiState s) => s.kind),
    );
    return EasyRefresh(
      header: const ClassicHeader(
        dragText: 'Pull to refresh',
        armedText: 'Release ready',
        readyText: 'Refreshing...',
        processingText: 'Refreshing...',
        processedText: 'Succeeded',
        failedText: 'Failed',
        messageText: 'Last updated at %T',
      ),
      onRefresh: () => _refresh(kind),
      child: CustomScrollView(
        // Its own scroll position per kind: the movies' offset must not
        // carry into the series list.
        key: PageStorageKey<String>('bazarr-library-${kind.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _Header(
                instance: _instance,
                kind: kind,
                search: _search,
                searchFocus: _searchFocus,
                onSearchChanged: _onSearchChanged,
                onClearSearch: _clearSearch,
              ),
            ),
          ),
          switch (kind) {
            BazarrLibraryKind.movies => _MoviesContent(instance: _instance),
            BazarrLibraryKind.series => _SeriesContent(instance: _instance),
          },
        ],
      ),
    );
  }
}

/// Search, kind, coverage bars, chips and "Search all missing".
class _Header extends ConsumerWidget {
  const _Header({
    required this.instance,
    required this.kind,
    required this.search,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  final Instance instance;
  final BazarrLibraryKind kind;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool movies = kind == BazarrLibraryKind.movies;
    final BazarrLibraryViewMode mode =
        ref.watch(bazarrLibraryViewModeProvider((instance, kind)));
    final BazarrLibraryUi ui =
        ref.read(bazarrLibraryUiProvider(instance).notifier);
    final LibraryFilter filter = ref.watch(
      bazarrLibraryUiProvider(instance)
          .select((BazarrLibraryUiState s) => s.filter),
    );
    final LibraryCounts counts = ref.watch(
      movies
          ? bazarrMovieCountsProvider(instance)
          : bazarrSeriesCountsProvider(instance),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: SearchBar(
                controller: search,
                focusNode: searchFocus,
                hintText: movies ? 'Search movies' : 'Search series',
                elevation: const WidgetStatePropertyAll<double>(0),
                backgroundColor: WidgetStatePropertyAll<Color>(
                  theme.colorScheme.surfaceContainerHigh,
                ),
                constraints: const BoxConstraints(minHeight: 48),
                leading: const Icon(Icons.search),
                onTapOutside: (PointerDownEvent _) => searchFocus.unfocus(),
                onChanged: onSearchChanged,
                trailing: <Widget>[
                  if (search.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: onClearSearch,
                    ),
                ],
              ),
            ),
            const SizedBox(width: Insets.xs),
            IconButton(
              tooltip: mode == BazarrLibraryViewMode.list
                  ? 'Show posters'
                  : 'Show list',
              icon: Icon(
                mode == BazarrLibraryViewMode.list
                    ? Icons.grid_view
                    : Icons.view_list,
              ),
              onPressed: () => ref
                  .read(bazarrLibraryViewModeProvider((instance, kind)).notifier)
                  .toggle(),
            ),
          ],
        ),
        const SizedBox(height: Insets.md),
        SegmentedButton<BazarrLibraryKind>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<BazarrLibraryKind>>[
            ButtonSegment<BazarrLibraryKind>(
              value: BazarrLibraryKind.movies,
              label: Text('Movies'),
              icon: Icon(Icons.movie_outlined),
            ),
            ButtonSegment<BazarrLibraryKind>(
              value: BazarrLibraryKind.series,
              label: Text('Series'),
              icon: Icon(Icons.live_tv_outlined),
            ),
          ],
          selected: <BazarrLibraryKind>{kind},
          onSelectionChanged: (Set<BazarrLibraryKind> next) =>
              ui.setKind(next.first),
        ),
        const SizedBox(height: Insets.md),
        if (movies) _Coverage(instance: instance),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final LibraryFilter f in LibraryFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: Insets.sm),
                  child: FilterChip(
                    label: Text(
                      f == LibraryFilter.all
                          ? f.label
                          : '${f.label} ${counts.of(f)}',
                    ),
                    selected: filter == f,
                    showCheckmark: false,
                    onSelected: (bool _) => ui.setFilter(f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        if (filter == LibraryFilter.missing && counts.missing > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
            child: _SearchAllButton(
              instance: instance,
              kind: kind,
              missing: counts.missing,
            ),
          ),
      ],
    );
  }
}

class _Coverage extends ConsumerWidget {
  const _Coverage({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<LanguageCoverage> coverage =
        ref.watch(bazarrMovieCoverageProvider(instance));
    if (coverage.isEmpty) {
      return const SizedBox.shrink();
    }
    final LanguageFilter? selected = ref.watch(
      bazarrLibraryUiProvider(instance)
          .select((BazarrLibraryUiState s) => s.languageFilter),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: BazarrCoverageBars(
        coverage: coverage,
        selected: selected,
        onTap: (String code2) => ref
            .read(bazarrLibraryUiProvider(instance).notifier)
            .cycleLanguage(code2),
      ),
    );
  }
}

class _SearchAllButton extends ConsumerWidget {
  const _SearchAllButton({
    required this.instance,
    required this.kind,
    required this.missing,
  });

  final Instance instance;
  final BazarrLibraryKind kind;
  final int missing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = subtitleMissingColor(scheme);
    final bool busy = ref.watch(
      bazarrActivityProvider(instance.id).select(
        (BazarrActivityState s) => s.isBusy(BazarrLibraryBusyKeys.all(kind)),
      ),
    );
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.1),
        disabledForegroundColor: color.withValues(alpha: 0.6),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(vertical: Insets.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      onPressed:
          busy ? null : () => confirmSearchAllMissing(context, instance, kind),
      icon: busy
          ? SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : const Icon(Icons.search, size: 16),
      label: Text(busy ? 'Searching…' : 'Search all $missing missing'),
    );
  }
}

// --- Content ---

/// Loading, a failed first load, the empty states, or the list itself.
class _MoviesContent extends ConsumerWidget {
  const _MoviesContent({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BazarrMovie>> movies =
        ref.watch(bazarrMoviesProvider(instance));
    final Widget? state = _stateSliver(
      ref,
      value: movies,
      errorTitle: "Couldn't load Bazarr's movies",
      onRetry: () => ref.invalidate(bazarrMoviesProvider(instance)),
    );
    if (state != null) {
      return state;
    }
    final List<BazarrMovie> shown =
        ref.watch(bazarrShownMoviesProvider(instance));
    if (shown.isEmpty) {
      return _EmptySliver(instance: instance, kind: BazarrLibraryKind.movies);
    }
    final ({LibraryFilter filter, LanguageFilter? language}) ui = ref.watch(
      bazarrLibraryUiProvider(instance).select(
        (BazarrLibraryUiState s) =>
            (filter: s.movieFilter, language: s.languageFilter),
      ),
    );
    final bool searchable = ui.filter == LibraryFilter.missing ||
        ui.language?.show == LanguageShow.missing;
    final PosterUrlOf? posterOf =
        bazarrPosterResolver(ref, instance, ServiceKind.radarr);
    final BazarrLibraryViewMode mode = ref.watch(
      bazarrLibraryViewModeProvider((instance, BazarrLibraryKind.movies)),
    );
    if (mode == BazarrLibraryViewMode.posters) {
      return _PosterGrid(
        count: shown.length,
        builder: (BuildContext context, int i) => BazarrMoviePoster(
          key: ValueKey<int>(shown[i].radarrId),
          bazarr: instance,
          movie: shown[i],
          posterUrl: posterOf?.call(shown[i].radarrId),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
      sliver: SliverList.builder(
        itemCount: shown.length,
        itemBuilder: (BuildContext context, int i) {
          final BazarrMovie m = shown[i];
          return BazarrMovieRow(
            key: ValueKey<int>(m.radarrId),
            bazarr: instance,
            movie: m,
            posterUrl: posterOf?.call(m.radarrId),
            showSearch: searchable && m.missingSubtitles.isNotEmpty,
          );
        },
      ),
    );
  }
}

class _SeriesContent extends ConsumerWidget {
  const _SeriesContent({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BazarrSeries>> series =
        ref.watch(bazarrSeriesProvider(instance));
    final Widget? state = _stateSliver(
      ref,
      value: series,
      errorTitle: "Couldn't load Bazarr's series",
      onRetry: () => ref.invalidate(bazarrSeriesProvider(instance)),
    );
    if (state != null) {
      return state;
    }
    final List<BazarrSeries> shown =
        ref.watch(bazarrShownSeriesProvider(instance));
    if (shown.isEmpty) {
      return _EmptySliver(instance: instance, kind: BazarrLibraryKind.series);
    }
    final ({LibraryFilter filter, Set<int> expanded}) ui = ref.watch(
      bazarrLibraryUiProvider(instance).select(
        (BazarrLibraryUiState s) =>
            (filter: s.seriesFilter, expanded: s.expanded),
      ),
    );
    final PosterUrlOf? posterOf =
        bazarrPosterResolver(ref, instance, ServiceKind.sonarr);
    final BazarrLibraryViewMode mode = ref.watch(
      bazarrLibraryViewModeProvider((instance, BazarrLibraryKind.series)),
    );
    if (mode == BazarrLibraryViewMode.posters) {
      return _PosterGrid(
        count: shown.length,
        builder: (BuildContext context, int i) => BazarrSeriesPoster(
          key: ValueKey<int>(shown[i].sonarrSeriesId),
          bazarr: instance,
          series: shown[i],
          posterUrl: posterOf?.call(shown[i].sonarrSeriesId),
        ),
      );
    }
    final BazarrLibraryUi notifier =
        ref.read(bazarrLibraryUiProvider(instance).notifier);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
      sliver: SliverList.builder(
        itemCount: shown.length,
        itemBuilder: (BuildContext context, int i) {
          final BazarrSeries s = shown[i];
          return BazarrSeriesRow(
            key: ValueKey<int>(s.sonarrSeriesId),
            bazarr: instance,
            series: s,
            posterUrl: posterOf?.call(s.sonarrSeriesId),
            expandable: ui.filter == LibraryFilter.missing,
            expanded: ui.expanded.contains(s.sonarrSeriesId),
            onToggle: () => notifier.toggleExpanded(s.sonarrSeriesId),
          );
        },
      ),
    );
  }
}

/// The sliver for a list that isn't ready: a spinner on the first load, the
/// error when the first load failed, else null. After a failed refresh the
/// loaded list still shows.
Widget? _stateSliver<T>(
  WidgetRef ref, {
  required AsyncValue<List<T>> value,
  required String errorTitle,
  required VoidCallback onRetry,
}) {
  if (value.hasValue) {
    return null;
  }
  if (value.hasError) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: ErrorView(
        title: errorTitle,
        message: switch (value.error) {
          NetworkException(:final String message) when message.isNotEmpty =>
            message,
          _ => 'Pull to refresh or try again.',
        },
        onRetry: onRetry,
      ),
    );
  }
  return const SliverFillRemaining(
    hasScrollBody: false,
    child: Center(child: ExpressiveProgressIndicator()),
  );
}

class _EmptySliver extends ConsumerWidget {
  const _EmptySliver({required this.instance, required this.kind});

  final Instance instance;
  final BazarrLibraryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool filtered = ref.watch(
      bazarrLibraryUiProvider(instance)
          .select((BazarrLibraryUiState s) => s.filtered),
    );
    final String noun = kind == BazarrLibraryKind.movies ? 'movies' : 'series';
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Insets.xl),
        child: filtered
            ? EmptyView(
                icon: Icons.closed_caption_off_outlined,
                title: 'No $noun match',
                action: OutlinedButton(
                  onPressed: () => ref
                      .read(bazarrLibraryUiProvider(instance).notifier)
                      .clearFilters(),
                  child: const Text('Clear filters'),
                ),
              )
            : EmptyView(
                icon: Icons.closed_caption_off_outlined,
                title: 'Bazarr has no $noun yet',
                message: 'They appear once Bazarr syncs with Radarr and Sonarr.',
              ),
      ),
    );
  }
}

/// Poster cells, about 130 px wide.
class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.count, required this.builder});

  final int count;
  final NullableIndexedWidgetBuilder builder;

  static const double _maxCellWidth = 130;
  static const double _gap = Insets.sm + 2;

  @override
  Widget build(BuildContext context) {
    final double caption =
        MediaQuery.textScalerOf(context).scale(posterCaptionHeight);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
      sliver: SliverLayoutBuilder(
        builder: (BuildContext context, SliverConstraints constraints) {
          final double width = constraints.crossAxisExtent;
          final int columns =
              ((width + _gap) / (_maxCellWidth + _gap)).ceil().clamp(1, 12);
          final double cell = (width - _gap * (columns - 1)) / columns;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: _gap,
              mainAxisSpacing: _gap,
              mainAxisExtent: cell * 3 / 2 + Insets.xs + caption,
            ),
            itemCount: count,
            itemBuilder: builder,
          );
        },
      ),
    );
  }
}
