import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bazarr_open.dart';
import '../bazarr_providers.dart';
import '../models/bazarr_models.dart';
import '../subtitles/bazarr_activity.dart';
import '../subtitles/bazarr_subtitle_mapping.dart';
import 'bazarr_library_actions.dart';
import 'bazarr_library_logic.dart';

// Rows and poster cells of the Bazarr library. Artwork comes from the Radarr
// or Sonarr the Bazarr's ids belong to (bazarrPosterResolver); without one
// the cells show a placeholder icon.

/// Builds poster URLs by Radarr movie id or Sonarr series id.
typedef PosterUrlOf = String? Function(int itemId);

const double _thumbWidth = 44;
const double _thumbHeight = 64;

/// "S01E02".
String episodeCode(int? season, int? episode) =>
    'S${(season ?? 0).toString().padLeft(2, '0')}'
    'E${(episode ?? 0).toString().padLeft(2, '0')}';

String _movieLabel(BazarrMovie movie) {
  final LibraryItemState state = classifyMovie(movie);
  return <String>[
    movie.title,
    if (movie.year != null) '${movie.year}',
    switch (state) {
      LibraryItemState.noProfile => 'No language profile',
      LibraryItemState.missing => 'Missing ${movie.missingSubtitles.map(
            (BazarrSubtitle m) => m.name.isNotEmpty ? m.name : m.code2,
          ).join(', ')} subtitles',
      _ => 'All profile languages present',
    },
  ].join(', ');
}

String _seriesLabel(BazarrSeries series) {
  final LibraryItemState state = classifySeries(series);
  final int done = seriesSubtitledCount(series);
  final int missing = series.episodeMissingCount;
  return <String>[
    series.title,
    if (series.year != null) '${series.year}',
    if (state == LibraryItemState.noProfile)
      'No language profile'
    else if (series.episodeFileCount <= 0)
      'No episode files'
    else
      '$done of ${series.episodeFileCount} episodes subtitled',
    if (state == LibraryItemState.missing)
      '$missing ${missing == 1 ? 'episode' : 'episodes'} missing subtitles',
  ].join(', ');
}

List<AudioTag> _audioOf(BazarrMovie movie) =>
    audioTagsFromLanguages(movie.audioLanguages());

List<SubtitleChip> _chipsOf(BazarrMovie movie) =>
    buildSubtitleChips(movie.subtitleRows());

/// A poster image, or [icon] while there's none.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.icon, this.iconSize = 20});

  final String? url;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, size: iconSize, color: scheme.onSurfaceVariant),
      ),
    );
    final String? url = this.url;
    if (url == null || url.isEmpty) {
      return placeholder;
    }
    return AtriumNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (BuildContext _, String __) => placeholder,
      errorWidget: (BuildContext _, String __, Object ___) => placeholder,
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.icon});

  final String? url;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          width: _thumbWidth,
          height: _thumbHeight,
          child: _Artwork(url: url, icon: icon),
        ),
      );
}

/// A small filled search button with a spinner while busy.
class LibrarySearchButton extends StatelessWidget {
  const LibrarySearchButton({
    required this.label,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 32,
      child: IconButton.filled(
        tooltip: label,
        padding: EdgeInsets.zero,
        iconSize: 16,
        onPressed: busy ? null : onPressed,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.6),
        ),
        icon: busy
            ? SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : const Icon(Icons.search),
      ),
    );
  }
}

BoxDecoration _cardDecoration(ColorScheme scheme) => BoxDecoration(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(Radii.lg),
    );

// --- Movies ---

/// A movie row: thumb, title, "year · No language profile", and its audio
/// and subtitle languages. With [showSearch], a button searches its missing
/// languages.
class BazarrMovieRow extends ConsumerWidget {
  const BazarrMovieRow({
    required this.bazarr,
    required this.movie,
    required this.posterUrl,
    required this.showSearch,
    super.key,
  });

  final Instance bazarr;
  final BazarrMovie movie;
  final String? posterUrl;
  final bool showSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool noProfile = classifyMovie(movie) == LibraryItemState.noProfile;
    final String subline = <String>[
      if (movie.year != null) '${movie.year}',
      if (noProfile) 'No language profile',
    ].join(' · ');
    final bool busy = showSearch &&
        ref.watch(
          bazarrActivityProvider(bazarr.id).select(
            (BazarrActivityState s) =>
                s.isBusy(BazarrLibraryBusyKeys.movie(movie.radarrId)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Stack(
        children: <Widget>[
          Material(
            color: Colors.transparent,
            child: Ink(
              decoration: _cardDecoration(scheme),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.lg),
                onTap: () => openBazarrMovie(
                  context,
                  ref,
                  bazarr,
                  radarrId: movie.radarrId,
                  title: movie.title,
                ),
                child: Semantics(
                  button: true,
                  label: _movieLabel(movie),
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.sm + 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _Thumb(url: posterUrl, icon: Icons.movie_outlined),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Padding(
                                padding: EdgeInsets.only(
                                  right: showSearch ? 36 : 0,
                                ),
                                child: Text(
                                  movie.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (subline.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    subline,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: Insets.xs),
                              LanguageLines(
                                audio: _audioOf(movie),
                                subtitles: _chipsOf(movie),
                                ringColor: scheme.surfaceContainerHigh,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showSearch)
            Positioned(
              top: Insets.sm,
              right: Insets.sm,
              child: LibrarySearchButton(
                label: 'Search missing subtitles for ${movie.title}',
                busy: busy,
                onPressed: () => searchLibraryMovie(context, bazarr, movie),
              ),
            ),
        ],
      ),
    );
  }
}

/// A movie's poster cell: art with its languages stacked over the bottom,
/// title and year.
class BazarrMoviePoster extends ConsumerWidget {
  const BazarrMoviePoster({
    required this.bazarr,
    required this.movie,
    required this.posterUrl,
    super.key,
  });

  final Instance bazarr;
  final BazarrMovie movie;
  final String? posterUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return _PosterTile(
      url: posterUrl,
      icon: Icons.movie_outlined,
      title: movie.title,
      year: movie.year,
      semanticLabel: _movieLabel(movie),
      complete: classifyMovie(movie) == LibraryItemState.complete,
      onTap: () => openBazarrMovie(
        context,
        ref,
        bazarr,
        radarrId: movie.radarrId,
        title: movie.title,
      ),
      overlay: Container(
        color: scheme.surface.withValues(alpha: 0.85),
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
        child: LanguageLines(
          audio: _audioOf(movie),
          subtitles: _chipsOf(movie),
          size: TagSize.xs,
          stacked: true,
          ringColor: scheme.surface,
        ),
      ),
    );
  }
}

// --- Series ---

/// A series row: thumb, title, the missing episode count or a check,
/// "year · No language profile|No episode files" and the share of episodes
/// subtitled. With [expandable] (the Missing filter), it expands to its
/// missing episodes.
class BazarrSeriesRow extends ConsumerWidget {
  const BazarrSeriesRow({
    required this.bazarr,
    required this.series,
    required this.posterUrl,
    required this.expandable,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final Instance bazarr;
  final BazarrSeries series;
  final String? posterUrl;
  final bool expandable;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final LibraryItemState state = classifySeries(series);
    final bool noFiles = series.episodeFileCount <= 0;
    final bool showProgress = state != LibraryItemState.noProfile && !noFiles;
    final bool canExpand = expandable && series.episodeMissingCount > 0;
    // A filter change or the last missing episode getting fixed removes the
    // toggle: the row collapses rather than stranding the list open.
    final bool open = expanded && canExpand;
    final String subline = <String>[
      if (series.year != null) '${series.year}',
      if (state == LibraryItemState.noProfile)
        'No language profile'
      else if (noFiles)
        'No episode files',
    ].join(' · ');
    void openSeries() => openBazarrSeries(
          context,
          ref,
          bazarr,
          seriesId: series.sonarrSeriesId,
          series: series,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: _cardDecoration(scheme),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      onTap: openSeries,
                      child: Semantics(
                        button: true,
                        label: _seriesLabel(series),
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.all(Insets.sm + 2),
                          child: Row(
                            children: <Widget>[
                              _Thumb(
                                url: posterUrl,
                                icon: Icons.live_tv_outlined,
                              ),
                              const SizedBox(width: Insets.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            series.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: Insets.sm),
                                        if (state == LibraryItemState.missing)
                                          _MissingCount(
                                            count: series.episodeMissingCount,
                                          )
                                        else if (state ==
                                            LibraryItemState.complete)
                                          Icon(
                                            Icons.check,
                                            size: 16,
                                            color: scheme.primary,
                                          ),
                                      ],
                                    ),
                                    if (subline.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          subline,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    if (showProgress)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: Insets.sm,
                                        ),
                                        child: _SeriesProgress(series: series),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canExpand)
                    Padding(
                      padding: const EdgeInsets.only(right: Insets.sm),
                      child: IconButton.filledTonal(
                        tooltip: open
                            ? 'Hide missing episodes'
                            : 'Show missing episodes',
                        onPressed: onToggle,
                        icon: Icon(
                          open ? Icons.expand_less : Icons.expand_more,
                        ),
                      ),
                    ),
                ],
              ),
              if (open)
                _MissingEpisodes(
                  bazarr: bazarr,
                  series: series,
                  onShowAll: openSeries,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingCount extends StatelessWidget {
  const _MissingCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final Color color = subtitleMissingColor(Theme.of(context).colorScheme);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.closed_caption_outlined, size: 15, color: color),
        const SizedBox(width: Insets.xs),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _SeriesProgress extends StatelessWidget {
  const _SeriesProgress({required this.series});

  final BazarrSeries series;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: LinearProgressIndicator(
            value: seriesCoverage(series),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(width: Insets.sm),
        Text(
          '${seriesSubtitledCount(series)}/${series.episodeFileCount}',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

const int _missingPreview = 5;

/// A series' episodes missing subtitles, newest first, loaded once the row
/// expands.
class _MissingEpisodes extends ConsumerWidget {
  const _MissingEpisodes({
    required this.bazarr,
    required this.series,
    required this.onShowAll,
  });

  final Instance bazarr;
  final BazarrSeries series;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AsyncValue<List<BazarrEpisode>> episodes = ref.watch(
      bazarrEpisodesProvider(
        (instance: bazarr, seriesId: series.sonarrSeriesId),
      ),
    );
    final Border divider =
        Border(top: BorderSide(color: scheme.outlineVariant, width: 0.5));
    final List<BazarrEpisode>? data = episodes.value;
    if (data == null && !episodes.hasError) {
      return Container(
        decoration: BoxDecoration(border: divider),
        padding: const EdgeInsets.symmetric(vertical: Insets.md),
        alignment: Alignment.center,
        child: const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final List<BazarrEpisode> missing = <BazarrEpisode>[
      for (final BazarrEpisode e in data ?? const <BazarrEpisode>[])
        if (e.missingSubtitles.isNotEmpty) e,
    ]..sort((BazarrEpisode a, BazarrEpisode b) {
        final int bySeason = (b.season ?? 0).compareTo(a.season ?? 0);
        return bySeason != 0
            ? bySeason
            : (b.episode ?? 0).compareTo(a.episode ?? 0);
      });
    // Only a failed first load is an error: a failed background refresh
    // keeps the episodes already loaded. The series' missing count can be
    // ahead of its episodes; say so rather than expanding to nothing.
    if (data == null || missing.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(border: divider),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md + 2,
          vertical: Insets.sm + 2,
        ),
        child: Text(
          data == null
              ? "Couldn't load the episodes"
              : 'No episodes are missing subtitles',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final BazarrEpisode e in missing.take(_missingPreview))
          Container(
            decoration: BoxDecoration(border: divider),
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md + 2,
              vertical: Insets.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${episodeCode(e.season, e.episode)} — ${e.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      LanguageLines(
                        subtitles: buildSubtitleChips(
                          buildSubtitleRows(
                            missing: e.missingSubtitles
                                .map((BazarrSubtitle s) => s.toTrack()),
                          ),
                        ),
                        ringColor: scheme.surfaceContainerHigh,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.sm),
                _EpisodeSearchButton(
                  bazarr: bazarr,
                  series: series,
                  episode: e,
                ),
              ],
            ),
          ),
        if (missing.length > _missingPreview)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onShowAll,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(border: divider),
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.md + 2,
                  vertical: Insets.sm + 2,
                ),
                child: Text(
                  'All ${missing.length} episodes on the series page',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EpisodeSearchButton extends ConsumerWidget {
  const _EpisodeSearchButton({
    required this.bazarr,
    required this.series,
    required this.episode,
  });

  final Instance bazarr;
  final BazarrSeries series;
  final BazarrEpisode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool busy = ref.watch(
      bazarrActivityProvider(bazarr.id).select(
        (BazarrActivityState s) => s.isBusy(
          BazarrLibraryBusyKeys.episode(
            series.sonarrSeriesId,
            episode.sonarrEpisodeId,
          ),
        ),
      ),
    );
    return LibrarySearchButton(
      label: 'Search subtitles for '
          '${episodeCode(episode.season, episode.episode)}',
      busy: busy,
      onPressed: () => searchLibraryEpisode(context, bazarr, series, episode),
    );
  }
}

/// A series' poster cell: art with the share of episodes subtitled over the
/// bottom, title and year.
class BazarrSeriesPoster extends ConsumerWidget {
  const BazarrSeriesPoster({
    required this.bazarr,
    required this.series,
    required this.posterUrl,
    super.key,
  });

  final Instance bazarr;
  final BazarrSeries series;
  final String? posterUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final LibraryItemState state = classifySeries(series);
    final bool complete = state == LibraryItemState.complete;
    final bool showProgress =
        state != LibraryItemState.noProfile && series.episodeFileCount > 0;
    return _PosterTile(
      url: posterUrl,
      icon: Icons.live_tv_outlined,
      title: series.title,
      year: series.year,
      semanticLabel: _seriesLabel(series),
      complete: complete,
      onTap: () => openBazarrSeries(
        context,
        ref,
        bazarr,
        seriesId: series.sonarrSeriesId,
        series: series,
      ),
      overlay: showProgress
          ? Container(
              color: scheme.surface.withValues(alpha: 0.85),
              padding: const EdgeInsets.all(6),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.closed_caption_outlined,
                    size: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Insets.xs),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: seriesCoverage(series),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: Insets.xs),
                  Text(
                    '${seriesSubtitledCount(series)}/'
                    '${series.episodeFileCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: complete
                          ? scheme.primary
                          : series.episodeMissingCount > 0
                              ? subtitleMissingColor(scheme)
                              : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

// --- Shared bits ---

/// Text below a poster cell's art: two lines of label text.
const double posterCaptionHeight = 40;

class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.url,
    required this.icon,
    required this.title,
    required this.year,
    required this.semanticLabel,
    required this.complete,
    required this.onTap,
    required this.overlay,
  });

  final String? url;
  final IconData icon;
  final String title;
  final int? year;
  final String semanticLabel;
  final bool complete;
  final VoidCallback onTap;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget? overlay = this.overlay;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _Artwork(url: url, icon: icon, iconSize: 32),
                    if (complete)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check,
                            size: 12,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    if (overlay != null)
                      Positioned(left: 0, right: 0, bottom: 0, child: overlay),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (year != null)
              Text(
                '$year',
                maxLines: 1,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
