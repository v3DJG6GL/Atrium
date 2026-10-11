import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:service_bazarr/service_bazarr.dart';
import 'package:service_radarr/service_radarr.dart';
import 'package:service_sonarr/service_sonarr.dart';

/// Lets Bazarr screens open Radarr and Sonarr pages and show their posters.
/// Installed in bootstrap; service packages can't import each other.
class AppArrTargets extends ArrTargets {
  const AppArrTargets();

  @override
  Future<void> openRadarrMovie(
    BuildContext context, {
    required Instance radarr,
    required int movieId,
  }) =>
      pushScreen<void>(
        context,
        MovieDetailScreen(
          instance: radarr,
          movieId: movieId,
          expandSubtitles: true,
        ),
      );

  @override
  Future<void> openSonarrSeries(
    BuildContext context, {
    required Instance sonarr,
    required int seriesId,
    int? episodeId,
  }) =>
      pushScreen<void>(
        context,
        _SonarrSeriesLoader(
          sonarr: sonarr,
          seriesId: seriesId,
          episodeId: episodeId,
        ),
      );

  @override
  String? Function(int itemId)? posterResolver(
    WidgetRef ref,
    Instance arr, {
    int width = 250,
  }) {
    switch (arr.kind) {
      case ServiceKind.radarr:
        final RadarrApi? api = ref.watch(radarrApiProvider(arr)).value;
        if (api == null) {
          return null;
        }
        return (int id) => api.posterUrl(
              RadarrImage(coverType: 'poster', url: '/MediaCover/$id/poster.jpg'),
              width: width,
            );
      case ServiceKind.sonarr:
        final SonarrApi? api = ref.watch(sonarrApiProvider(arr)).value;
        if (api == null) {
          return null;
        }
        return (int id) => api.posterUrl(
              SonarrImage(coverType: 'poster', url: '/MediaCover/$id/poster.jpg'),
              width: width,
            );
      default:
        return null;
    }
  }
}

/// [SeriesDetailScreen] needs the whole series, while Bazarr knows only its
/// id; this loads it first.
class _SonarrSeriesLoader extends ConsumerWidget {
  const _SonarrSeriesLoader({
    required this.sonarr,
    required this.seriesId,
    this.episodeId,
  });

  final Instance sonarr;
  final int seriesId;
  final int? episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SonarrSeries> series =
        ref.watch(sonarrSeriesByIdProvider((sonarr, seriesId)));
    return series.when(
      data: (SonarrSeries s) => SeriesDetailScreen(
        instance: sonarr,
        series: s,
        openEpisodeSubtitles: episodeId,
      ),
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: ExpressiveProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: "Couldn't load the series from Sonarr.",
          onRetry: () =>
              ref.invalidate(sonarrSeriesByIdProvider((sonarr, seriesId))),
        ),
      ),
    );
  }
}
