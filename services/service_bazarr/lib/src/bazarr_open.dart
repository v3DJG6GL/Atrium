import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bazarr_movie_detail_screen.dart';
import 'bazarr_series_detail_screen.dart';
import 'link/bazarr_link_providers.dart';
import 'models/bazarr_models.dart';
import 'subtitles/bazarr_subtitle_providers.dart';
import 'subtitles/ui/episode_subtitles_sheet.dart';

/// Opens Radarr and Sonarr pages, and builds their poster URLs, for Bazarr
/// screens.
///
/// Service packages must not import each other, so `app/` provides the
/// implementation by overriding [bazarrArrTargetsProvider].
abstract class ArrTargets {
  const ArrTargets();

  /// The Radarr movie page, with its Subtitles section expanded.
  Future<void> openRadarrMovie(
    BuildContext context, {
    required Instance radarr,
    required int movieId,
  });

  /// The Sonarr series page; with [episodeId], that episode's subtitles
  /// open on top of it.
  Future<void> openSonarrSeries(
    BuildContext context, {
    required Instance sonarr,
    required int seriesId,
    int? episodeId,
  });

  /// Builds poster URLs for the items of [arr] by their ids, or null while
  /// that instance's API isn't ready. Call once per list build, not per row.
  String? Function(int itemId)? posterResolver(
    WidgetRef ref,
    Instance arr, {
    int width = 250,
  });
}

/// Radarr and Sonarr pages and posters for Bazarr screens. Null (the
/// default) means Bazarr opens its own pages and shows no posters.
final Provider<ArrTargets?> bazarrArrTargetsProvider =
    Provider<ArrTargets?>((Ref ref) => null);

/// The Radarr or Sonarr whose items [bazarr]'s ids of [kind] belong to, and
/// the targets to open them with; null when Bazarr has to use its own pages.
({Instance arr, ArrTargets targets})? _arrFor(
  WidgetRef ref,
  Instance bazarr,
  ServiceKind kind,
) {
  final ArrTargets? targets = ref.read(bazarrArrTargetsProvider);
  final Instance? arr = ref.read(
    bazarrItemsArrProvider((bazarrId: bazarr.id, kind: kind)),
  );
  if (targets == null || arr == null) {
    return null;
  }
  return (arr: arr, targets: targets);
}

/// Poster URLs for [bazarr]'s items of [kind], from the Radarr or Sonarr
/// those items belong to; null when there's none.
String? Function(int itemId)? bazarrPosterResolver(
  WidgetRef ref,
  Instance bazarr,
  ServiceKind kind, {
  int width = 250,
}) {
  final ArrTargets? targets = ref.watch(bazarrArrTargetsProvider);
  final Instance? arr = ref.watch(
    bazarrItemsArrProvider((bazarrId: bazarr.id, kind: kind)),
  );
  if (targets == null || arr == null) {
    return null;
  }
  return targets.posterResolver(ref, arr, width: width);
}

/// Opens a movie of [bazarr]: on the Radarr page it belongs to when there is
/// one, otherwise on Bazarr's own movie page.
Future<void> openBazarrMovie(
  BuildContext context,
  WidgetRef ref,
  Instance bazarr, {
  required int radarrId,
  required String title,
}) {
  final ({Instance arr, ArrTargets targets})? target =
      _arrFor(ref, bazarr, ServiceKind.radarr);
  if (target != null) {
    return target.targets
        .openRadarrMovie(context, radarr: target.arr, movieId: radarrId);
  }
  return pushScreen<void>(
    context,
    BazarrMovieDetailScreen(
      instance: bazarr,
      radarrId: radarrId,
      title: title,
    ),
  );
}

/// Opens a series of [bazarr]: on the Sonarr page it belongs to when there
/// is one, otherwise on Bazarr's own series page. With [episodeId], that
/// episode's subtitles open on top.
Future<void> openBazarrSeries(
  BuildContext context,
  WidgetRef ref,
  Instance bazarr, {
  required int seriesId,
  BazarrSeries? series,
  int? episodeId,
}) {
  final ({Instance arr, ArrTargets targets})? target =
      _arrFor(ref, bazarr, ServiceKind.sonarr);
  if (target != null) {
    return target.targets.openSonarrSeries(
      context,
      sonarr: target.arr,
      seriesId: seriesId,
      episodeId: episodeId,
    );
  }
  return pushScreen<void>(
    context,
    _BazarrSeriesLoader(
      bazarr: bazarr,
      seriesId: seriesId,
      series: series,
      episodeId: episodeId,
    ),
  );
}

/// Bazarr's own series page for a series known only by id (e.g. from
/// History), opening [episodeId]'s subtitles once it has loaded.
class _BazarrSeriesLoader extends ConsumerStatefulWidget {
  const _BazarrSeriesLoader({
    required this.bazarr,
    required this.seriesId,
    this.series,
    this.episodeId,
  });

  final Instance bazarr;
  final int seriesId;
  final BazarrSeries? series;
  final int? episodeId;

  @override
  ConsumerState<_BazarrSeriesLoader> createState() =>
      _BazarrSeriesLoaderState();
}

class _BazarrSeriesLoaderState extends ConsumerState<_BazarrSeriesLoader> {
  bool _episodeOpened = false;

  void _openEpisodeOnce(BazarrSeries series) {
    final int? episodeId = widget.episodeId;
    if (episodeId == null || _episodeOpened) {
      return;
    }
    _episodeOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showEpisodeSubtitlesSheet(
        context,
        bazarr: widget.bazarr,
        seriesId: widget.seriesId,
        episodeId: episodeId,
        seriesTitle: series.title,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final BazarrSeries? known = widget.series;
    if (known != null) {
      _openEpisodeOnce(known);
      return BazarrSeriesDetailScreen(instance: widget.bazarr, series: known);
    }
    final AsyncValue<BazarrSeries?> item = ref.watch(
      bazarrSeriesItemProvider((widget.bazarr, widget.seriesId)),
    );
    return item.when(
      data: (BazarrSeries? series) {
        if (series == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyView(
              icon: Icons.closed_caption_off_outlined,
              title: 'Not in Bazarr',
              message: 'Bazarr doesn\'t list this series yet. It picks up '
                  'new Sonarr series on its next sync.',
            ),
          );
        }
        _openEpisodeOnce(series);
        return BazarrSeriesDetailScreen(
          instance: widget.bazarr,
          series: series,
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: ExpressiveProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: 'Couldn\'t load the series from Bazarr.',
          onRetry: () => ref.invalidate(
            bazarrSeriesItemProvider((widget.bazarr, widget.seriesId)),
          ),
        ),
      ),
    );
  }
}
