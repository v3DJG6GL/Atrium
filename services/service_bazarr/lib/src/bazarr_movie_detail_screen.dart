import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/bazarr_models.dart';
import 'subtitles/bazarr_subtitle_mapping.dart';
import 'subtitles/bazarr_subtitle_params.dart';
import 'subtitles/bazarr_subtitle_providers.dart';
import 'subtitles/manual_search/open_manual_search.dart';
import 'subtitles/subtitle_actions.dart';
import 'subtitles/ui/subtitle_flows.dart';
import 'subtitles/ui/subtitles_block.dart';

/// Per-movie subtitle view: the movie's subtitles and missing languages with
/// their actions (search, manual search, upload, sync, timing, translate,
/// clean up, delete) and its language profile. Watches just this movie, so
/// it refreshes in place after an action.
class BazarrMovieDetailScreen extends ConsumerWidget {
  const BazarrMovieDetailScreen({
    required this.instance,
    required this.radarrId,
    required this.title,
    super.key,
  });

  final Instance instance;
  final int radarrId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BazarrItemKey key = (instance, radarrId);
    final AsyncValue<BazarrMovie?> movie =
        ref.watch(bazarrMovieItemProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'Search subtitles',
            icon: const Icon(Icons.subtitles_outlined),
            onPressed: () => unawaited(
              openBazarrManualSearch(
                context,
                bazarr: instance,
                target: MovieTarget(radarrId),
                title: title,
              ),
            ),
          ),
        ],
      ),
      body: AsyncValueView<BazarrMovie?>(
        value: movie,
        onRetry: () => ref.invalidate(bazarrMovieItemProvider(key)),
        data: (BazarrMovie? m) {
          if (m == null) {
            return const EmptyView(
              icon: Icons.movie_outlined,
              title: 'Movie not found',
              message: 'It may have been removed from Bazarr.',
            );
          }
          return ListView(
            padding: Insets.page,
            children: <Widget>[
              _HeaderCard(movie: m),
              const SizedBox(height: Insets.md),
              Card(
                margin: EdgeInsets.zero,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.lg,
                        Insets.lg,
                        Insets.lg,
                        Insets.sm,
                      ),
                      child: Text(
                        'Subtitles',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    BazarrSubtitlesBlock(
                      bazarr: instance,
                      subject: SubtitleSubject(
                        target: MovieTarget(radarrId),
                        rows: m.subtitleRows(),
                        title: m.title.isEmpty ? title : m.title,
                        searchTitle: title,
                        profileId: m.profileId,
                        profileOwner: MovieProfileOwner(radarrId),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.xl),
            ],
          );
        },
      ),
    );
  }
}

/// Tonal hero header: a poster-stand-in tile, the title, and metadata pills.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.movie});

  final BazarrMovie movie;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int present = movie.subtitles.length;
    final int missing = movie.missingSubtitles.length;
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
            child: Icon(Icons.movie_outlined, color: cs.primary, size: 28),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  movie.title,
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
                    if (movie.year != null)
                      _MetaPill(
                        icon: Icons.calendar_today,
                        label: '${movie.year}',
                        color: cs.secondary,
                      ),
                    _MetaPill(
                      icon: movie.monitored
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      label: movie.monitored ? 'Monitored' : 'Unmonitored',
                      color: movie.monitored ? cs.primary : cs.outline,
                    ),
                    _MetaPill(
                      icon: Icons.subtitles_outlined,
                      label: '$present subs',
                      color: cs.tertiary,
                    ),
                    if (missing > 0)
                      _MetaPill(
                        icon: Icons.report_outlined,
                        label: '$missing missing',
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
