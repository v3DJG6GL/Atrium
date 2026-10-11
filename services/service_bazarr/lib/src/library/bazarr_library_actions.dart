import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../bazarr_api.dart';
import '../bazarr_providers.dart';
import '../models/bazarr_models.dart';
import '../subtitles/bazarr_activity.dart';
import '../subtitles/bazarr_subtitle_params.dart';
import '../subtitles/subtitle_actions.dart';
import 'bazarr_library_logic.dart';

/// Busy keys of the Library's searches (see [BazarrActivity.run]). A movie's
/// and an episode's are the subtitle blocks' "Search" keys, so their missing
/// rows show busy there too.
abstract final class BazarrLibraryBusyKeys {
  /// A movie's search button: `m12:missing`.
  static String movie(int radarrId) =>
      SubtitleBusyKeys.allMissing(MovieTarget(radarrId));

  /// A missing episode's search button: `e34:missing`.
  static String episode(int seriesId, int episodeId) =>
      SubtitleBusyKeys.allMissing(EpisodeTarget(seriesId, episodeId));

  /// "Search all missing" of a kind: `all:movies`, `all:series`.
  static String all(BazarrLibraryKind kind) => 'all:${kind.name}';
}

/// Searches every missing language of [movie].
Future<void> searchLibraryMovie(
  BuildContext context,
  Instance bazarr,
  BazarrMovie movie,
) async {
  final SubtitleActions actions = SubtitleActions.of(context, bazarr: bazarr);
  final MovieTarget target = MovieTarget(movie.radarrId);
  try {
    await actions.container
        .read(bazarrActivityProvider(bazarr.id).notifier)
        .run<void>(
          BazarrLibraryBusyKeys.movie(movie.radarrId),
          (BazarrApi api) => api.searchMissingMovie(movie.radarrId),
          refresh: actions.refreshFor(target),
        );
  } on Object {
    actions.notify("Couldn't start the search");
    return;
  }
  actions.notify('Searching subtitles for ${movie.title}…');
}

/// Searches every missing language of [episode] of [series], one request
/// per language.
Future<void> searchLibraryEpisode(
  BuildContext context,
  Instance bazarr,
  BazarrSeries series,
  BazarrEpisode episode,
) async {
  final SubtitleActions actions = SubtitleActions.of(context, bazarr: bazarr);
  final EpisodeTarget target =
      EpisodeTarget(series.sonarrSeriesId, episode.sonarrEpisodeId);
  final List<LanguageChoice> languages = <LanguageChoice>[
    for (final BazarrSubtitle m in episode.missingSubtitles)
      LanguageChoice(code2: m.code2, forced: m.forced, hi: m.hi),
  ];
  try {
    await actions.container
        .read(bazarrActivityProvider(bazarr.id).notifier)
        .run<void>(
          BazarrLibraryBusyKeys.episode(
            series.sonarrSeriesId,
            episode.sonarrEpisodeId,
          ),
          (BazarrApi api) => runConcurrently<LanguageChoice>(
            languages,
            (LanguageChoice language) => api.searchLanguage(target, language),
          ),
          refresh: actions.refreshFor(target),
        );
  } on Object {
    actions.notify("Couldn't start the search");
    return;
  }
  actions.notify('Searching subtitles for ${series.title}…');
}

/// "Search all missing": after a confirmation, searches every missing
/// subtitle of every movie or every series.
Future<void> confirmSearchAllMissing(
  BuildContext context,
  Instance bazarr,
  BazarrLibraryKind kind,
) async {
  final SubtitleActions actions = SubtitleActions.of(context, bazarr: bazarr);
  final bool movies = kind == BazarrLibraryKind.movies;
  final String noun = movies ? 'movie' : 'episode';
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      icon: const Icon(Icons.manage_search),
      title: const Text('Search Missing Subtitles'),
      content: Text(
        'Bazarr will search every missing $noun subtitle in your library. '
        'This can queue a lot of searches at once.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Search'),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return;
  }
  final BazarrActivity activity =
      actions.container.read(bazarrActivityProvider(bazarr.id).notifier);
  // A second tap while the first request is still out would queue every
  // search again.
  if (actions.container
      .read(bazarrActivityProvider(bazarr.id))
      .isBusy(BazarrLibraryBusyKeys.all(kind))) {
    return;
  }
  try {
    await activity.run<void>(
      BazarrLibraryBusyKeys.all(kind),
      (BazarrApi api) => api.searchWanted(movies: movies),
      refresh: <WatchedProvider>[
        if (movies) bazarrMoviesProvider(bazarr) else bazarrSeriesProvider(bazarr),
        bazarrBadgesProvider(bazarr),
      ],
      maxDuration: bazarrSearchAllMaxDuration,
    );
  } on Object {
    actions.notify("Couldn't start the search");
    return;
  }
  actions.notify('Searching every missing $noun subtitle…');
}
