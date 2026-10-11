import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bazarr_providers.dart';
import '../../models/bazarr_models.dart';
import '../bazarr_subtitle_providers.dart';
import '../subtitle_actions.dart';
import '../subtitle_ui_text.dart';
import 'episode_subtitles_sheet.dart';
import 'series_coverage_card.dart';
import 'subtitle_flows.dart';
import 'subtitles_section.dart';

/// The Subtitles section of a Sonarr series page, from the Bazarr serving
/// that Sonarr: the coverage card once the series' profile has settled,
/// "Couldn't reach" or "doesn't list this series" otherwise, nothing while
/// loading. Brings its own top spacing when it shows anything.
class BazarrSeriesSubtitlesSection extends ConsumerWidget {
  const BazarrSeriesSubtitlesSection({
    required this.bazarr,
    required this.series,
    this.expanded = false,
    super.key,
  });

  final Instance bazarr;
  final SeriesSubtitlesRef series;

  /// Start with the coverage grid open.
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BazarrItemKey key = (bazarr, series.seriesId);
    final AsyncValue<BazarrSeries?> item =
        ref.watch(bazarrSeriesItemProvider(key));
    final AsyncValue<BazarrSeriesEpisodes> episodes =
        ref.watch(bazarrSeriesEpisodesViewProvider(key));
    final CoverageGrid? grid = ref.watch(bazarrSeriesCoverageProvider(key));
    final String name = bazarrDisplayName(bazarr);

    final Widget body;
    if ((!episodes.hasValue && episodes.hasError) ||
        (!item.hasValue && item.hasError)) {
      body = SubtitlesUnreachable(
        bazarrName: name,
        onRetry: () {
          ref.invalidate(bazarrSeriesItemProvider(key));
          ref.invalidate(
            bazarrEpisodesProvider(
              (instance: bazarr, seriesId: series.seriesId),
            ),
          );
        },
      );
    } else if (item.hasValue && item.value == null) {
      body = SubtitlesNotListed(bazarrName: name, series: true);
    } else if (grid == null || !episodes.hasValue) {
      return const SizedBox.shrink();
    } else {
      final int? profileId = item.value?.profileId;
      body = BazarrSeriesCoverageCard(
        grid: grid,
        expanded: expanded,
        profileName: profileDisplayName(
          profileId,
          ref.watch(bazarrProfilesProvider(bazarr)),
        ),
        onPressProfile: () => unawaited(
          openLanguageProfilePicker(
            context,
            SubtitleActions.of(context, bazarr: bazarr),
            owner: SeriesProfileOwner(series.seriesId),
            current: profileId,
          ),
        ),
        onOpenEpisode: (int episodeId) => unawaited(
          showEpisodeSubtitlesSheet(
            context,
            bazarr: bazarr,
            seriesId: series.seriesId,
            episodeId: episodeId,
            seriesTitle: series.title,
            originalLanguage: series.originalLanguage,
            episodeInfo: series.episodeInfo,
          ),
        ),
        onSearchSeason: (int season) => unawaited(
          SubtitleActions.of(context, bazarr: bazarr).searchSeason(
            seriesId: series.seriesId,
            season: season,
            episodes: ref
                    .read(bazarrSeriesEpisodesViewProvider(key))
                    .value
                    ?.episodes ??
                const <BazarrEpisode>[],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: Insets.lg),
        SubtitlesSectionHeader(
          bazarrName: name,
          unreachable: (episodes.hasError && episodes.hasValue) ||
              (item.hasError && item.hasValue),
        ),
        body,
      ],
    );
  }
}
