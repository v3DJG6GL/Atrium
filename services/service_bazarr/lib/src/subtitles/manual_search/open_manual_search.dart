import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/widgets.dart';

import '../../bazarr_search_screen.dart';
import '../bazarr_subtitle_params.dart';

/// Opens the manual subtitle search for [target] on [bazarr].
///
/// [title] names what is searched, e.g. a movie title or "S01E02".
Future<void> openBazarrManualSearch(
  BuildContext context, {
  required Instance bazarr,
  required SubtitleTarget target,
  required String title,
}) =>
    pushScreen<void>(
      context,
      switch (target) {
        MovieTarget(:final int radarrId) => BazarrSubtitleSearchScreen(
            instance: bazarr,
            isMovie: true,
            id: radarrId,
            seriesId: 0,
            title: title,
          ),
        EpisodeTarget(:final int seriesId, :final int episodeId) =>
          BazarrSubtitleSearchScreen(
            instance: bazarr,
            isMovie: false,
            id: episodeId,
            seriesId: seriesId,
            title: title,
          ),
      },
    );
