import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bazarr_providers.dart';
import 'models/bazarr_models.dart';
import 'subtitles/bazarr_subtitle_mapping.dart';
import 'subtitles/bazarr_subtitle_params.dart';
import 'subtitles/manual_search/open_manual_search.dart';
import 'subtitles/subtitle_ui_text.dart';
import 'subtitles/ui/episode_subtitles_sheet.dart';

/// Per-series subtitle view: the episode list with each episode's subtitle
/// chips. Tapping an episode opens its subtitles sheet (search, upload,
/// sync, timing, translate, clean up, delete); the search button opens the
/// manual search.
class BazarrSeriesDetailScreen extends ConsumerWidget {
  const BazarrSeriesDetailScreen({
    required this.instance,
    required this.series,
    super.key,
  });

  final Instance instance;
  final BazarrSeries series;

  static const ClassicHeader _refreshHeader = ClassicHeader(
    dragText: 'Pull to refresh',
    armedText: 'Release ready',
    readyText: 'Refreshing...',
    processingText: 'Refreshing...',
    processedText: 'Succeeded',
    failedText: 'Failed',
    messageText: 'Last updated at %T',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BazarrEpisodesArgs args =
        (instance: instance, seriesId: series.sonarrSeriesId);
    final AsyncValue<List<BazarrEpisode>> episodes =
        ref.watch(bazarrEpisodesProvider(args));
    return Scaffold(
      appBar: AppBar(
        title: Text(series.title, overflow: TextOverflow.ellipsis),
      ),
      body: AsyncValueView<List<BazarrEpisode>>(
        value: episodes,
        onRetry: () => ref.invalidate(bazarrEpisodesProvider(args)),
        data: (List<BazarrEpisode> eps) => EasyRefresh(
          header: _refreshHeader,
          onRefresh: () async => ref.invalidate(bazarrEpisodesProvider(args)),
          child: eps.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const <Widget>[
                    SizedBox(height: 100),
                    EmptyView(
                      icon: Icons.subtitles_outlined,
                      title: 'No episodes',
                      message: 'This series has no episode files in Bazarr.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: Insets.page,
                  itemCount: eps.length + 1,
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Insets.md),
                        child: _HeaderCard(series: series),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Insets.sm),
                      child: _EpisodeCard(
                        instance: instance,
                        series: series,
                        episode: eps[index - 1],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Tonal hero header: a poster-stand-in tile, the title, and metadata pills.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.series});

  final BazarrSeries series;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.tv_outlined, color: cs.primary, size: 28),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.xs,
                  runSpacing: Insets.xs,
                  children: <Widget>[
                    if (series.year != null)
                      _MetaPill(
                        icon: Icons.calendar_today,
                        label: '${series.year}',
                        color: cs.secondary,
                      ),
                    _MetaPill(
                      icon: series.monitored
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      label: series.monitored ? 'Monitored' : 'Unmonitored',
                      color: series.monitored ? cs.primary : cs.outline,
                    ),
                    _MetaPill(
                      icon: Icons.video_library_outlined,
                      label: '${series.episodeFileCount} files',
                      color: cs.tertiary,
                    ),
                    if (series.episodeMissingCount > 0)
                      _MetaPill(
                        icon: Icons.report_outlined,
                        label: '${series.episodeMissingCount} missing',
                        color: cs.error,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.instance,
    required this.series,
    required this.episode,
  });

  final Instance instance;
  final BazarrSeries series;
  final BazarrEpisode episode;

  String get _code => episodeCode(episode.season, episode.episode);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<SubtitleChip> chips = buildSubtitleChips(episode.subtitleRows());
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(
          showEpisodeSubtitlesSheet(
            context,
            bazarr: instance,
            seriesId: episode.sonarrSeriesId,
            episodeId: episode.sonarrEpisodeId,
            seriesTitle: series.title,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '$_code · ${episode.title}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Search subtitles',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.subtitles_outlined),
                    onPressed: () => unawaited(
                      openBazarrManualSearch(
                        context,
                        bazarr: instance,
                        target: EpisodeTarget(
                          episode.sonarrSeriesId,
                          episode.sonarrEpisodeId,
                        ),
                        title: _code,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),
              if (chips.isEmpty)
                Text(
                  'No subtitles tracked',
                  style:
                      theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                )
              else
                Padding(
                  // Room for the corner badges.
                  padding: const EdgeInsets.only(top: Insets.xs),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: Insets.sm,
                    children: <Widget>[
                      for (final SubtitleChip c in chips)
                        SubtitleTrackChip.fromChip(
                          c,
                          size: TagSize.sm,
                          ringColor: cs.surfaceContainerHigh,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small tonal metadata pill (icon + label), tinted by [color].
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
