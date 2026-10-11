import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../bazarr_providers.dart';
import '../link/bazarr_link_providers.dart';
import '../models/bazarr_models.dart';
import 'bazarr_subtitle_providers.dart';
import 'subtitle_actions.dart';
import 'ui/episode_subtitles_sheet.dart';
import 'ui/movie_subtitles_card.dart';
import 'ui/series_subtitles_section.dart';

/// The Bazarr implementation of [SubtitlesBridge]: what the Radarr movie
/// page and the Sonarr series page show from the Bazarr serving their
/// instance (see `bazarrForArrProvider`). `app/` installs it with
/// `subtitlesBridgeProvider.overrideWithValue(const BazarrSubtitlesBridge())`.
///
/// Every lookup goes through the arr instance's id to the profile's current
/// instances, so a screen holding a stale [Instance] still finds the right
/// Bazarr.
final class BazarrSubtitlesBridge extends SubtitlesBridge {
  const BazarrSubtitlesBridge();

  @override
  Widget movieSection({
    required Instance radarr,
    required MovieSubtitlesRef movie,
  }) =>
      _ServedByBazarr(
        arr: radarr,
        builder: (Instance bazarr) =>
            BazarrMovieSubtitlesCard(
          bazarr: bazarr,
          movie: movie,
          expanded: movie.expanded,
        ),
      );

  @override
  Widget seriesSection({
    required Instance sonarr,
    required SeriesSubtitlesRef series,
  }) =>
      _ServedByBazarr(
        arr: sonarr,
        builder: (Instance bazarr) =>
            BazarrSeriesSubtitlesSection(bazarr: bazarr, series: series),
      );

  @override
  ProviderListenable<SeriesSubtitles> series(Instance sonarr, int seriesId) =>
      bazarrSeriesSubtitlesProvider((sonarr.id, seriesId));

  @override
  Future<void> openEpisode(
    BuildContext context, {
    required Instance sonarr,
    required SeriesSubtitlesRef series,
    required int episodeId,
  }) async {
    final Instance? bazarr = _servingBazarr(context, sonarr);
    if (bazarr == null) {
      return;
    }
    await showEpisodeSubtitlesSheet(
      context,
      bazarr: bazarr,
      seriesId: series.seriesId,
      episodeId: episodeId,
      seriesTitle: series.title,
      originalLanguage: series.originalLanguage,
      episodeInfo: series.episodeInfo,
    );
  }

  @override
  Future<void> searchSeasonMissing(
    BuildContext context, {
    required Instance sonarr,
    required int seriesId,
    required int season,
  }) async {
    final Instance? bazarr = _servingBazarr(context, sonarr);
    if (bazarr == null) {
      return;
    }
    final SubtitleActions actions = SubtitleActions.of(context, bazarr: bazarr);
    final List<BazarrEpisode> episodes;
    try {
      episodes = await actions.container.read(
        bazarrEpisodesProvider((instance: bazarr, seriesId: seriesId)).future,
      );
    } on Object {
      actions.notify("Couldn't start the search");
      return;
    }
    await actions.searchSeason(
      seriesId: seriesId,
      season: season,
      episodes: episodes,
    );
  }

  @override
  Future<void> searchSeriesMissing(
    BuildContext context, {
    required Instance sonarr,
    required SeriesSubtitlesRef series,
  }) async {
    final Instance? bazarr = _servingBazarr(context, sonarr);
    if (bazarr == null) {
      return;
    }
    await SubtitleActions.of(context, bazarr: bazarr).searchSeries(
      seriesId: series.seriesId,
      title: series.title,
    );
  }

  @override
  void refresh(Instance arr, int itemId) =>
      requestBazarrItemRefresh(arr, itemId);

  /// The Bazarr serving [arr] now, from [context]'s provider scope.
  static Instance? _servingBazarr(BuildContext context, Instance arr) {
    final ProviderContainer container =
        ProviderScope.containerOf(context, listen: false);
    final Instance? current = container.read(instanceByIdProvider(arr.id));
    return current == null
        ? null
        : container.read(bazarrForArrProvider(current));
  }
}

/// Builds [builder] for the Bazarr serving [arr] (resolved from the
/// profile's current instances), or nothing when none does.
class _ServedByBazarr extends ConsumerWidget {
  const _ServedByBazarr({required this.arr, required this.builder});

  final Instance arr;
  final Widget Function(Instance bazarr) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Instance? current = ref.watch(instanceByIdProvider(arr.id));
    final Instance? bazarr =
        current == null ? null : ref.watch(bazarrForArrProvider(current));
    if (bazarr == null) {
      return const SizedBox.shrink();
    }
    // A different Bazarr starts the section afresh.
    return KeyedSubtree(
      key: ValueKey<String>(bazarr.id),
      child: builder(bazarr),
    );
  }
}
