import 'dart:typed_data';

import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bazarr_api.dart';
import '../bazarr_providers.dart';
import '../history/bazarr_history_providers.dart';
import '../models/bazarr_models.dart';
import 'bazarr_activity.dart';
import 'bazarr_subtitle_params.dart';
import 'bazarr_subtitle_providers.dart';

/// Shows a short confirmation or error: a SnackBar, or a notice inside the
/// sheet that started the action.
typedef SubtitleNotify = void Function(String message);

/// Whose language profile a profile change sets: a movie's or a series'.
@immutable
sealed class ProfileOwner {
  const ProfileOwner();

  /// Busy key of a profile change.
  String get busyKey;
}

final class MovieProfileOwner extends ProfileOwner {
  const MovieProfileOwner(this.radarrId);

  final int radarrId;

  @override
  String get busyKey => 'profile:m$radarrId';

  @override
  bool operator ==(Object other) =>
      other is MovieProfileOwner && other.radarrId == radarrId;

  @override
  int get hashCode => Object.hash('movie', radarrId);
}

final class SeriesProfileOwner extends ProfileOwner {
  const SeriesProfileOwner(this.seriesId);

  final int seriesId;

  @override
  String get busyKey => 'profile:s$seriesId';

  @override
  bool operator ==(Object other) =>
      other is SeriesProfileOwner && other.seriesId == seriesId;

  @override
  int get hashCode => Object.hash('series', seriesId);
}

/// The Bazarr subtitle a row stands for, for the API calls that take one.
BazarrSubtitle bazarrSubtitleOf(SubtitleTrack track) => BazarrSubtitle(
      name: track.name,
      code2: track.code2,
      code3: track.code3 ?? '',
      hi: track.hi,
      forced: track.forced,
      path: track.path,
      id: track.id,
      embeddedTrackId: track.embeddedTrackId,
      fileSize: track.fileSize,
    );

/// Runs [run] for every item of [items], at most [concurrency] at a time.
/// Fails only when every call failed (with the first error), since a bulk
/// search that started most of its searches did its job.
Future<void> runConcurrently<T>(
  List<T> items,
  Future<void> Function(T item) run, {
  int concurrency = 4,
}) async {
  if (items.isEmpty) {
    return;
  }
  final List<Object> failures = <Object>[];
  StackTrace? firstTrace;
  int next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final T item = items[next++];
      try {
        await run(item);
      } on Object catch (e, st) {
        failures.add(e);
        firstTrace ??= st;
      }
    }
  }

  await Future.wait(<Future<void>>[
    for (int i = 0; i < concurrency && i < items.length; i++) worker(),
  ]);
  if (failures.length == items.length) {
    Error.throwWithStackTrace(failures.first, firstTrace!);
  }
}

/// Busy keys of the subtitle actions (see [BazarrActivity.run]).
abstract final class SubtitleBusyKeys {
  /// One row of a movie or episode: `m12:de||missing`.
  static String row(SubtitleTarget target, String rowKey) =>
      '${target.key}:$rowKey';

  /// A movie's "Search" (all missing languages in one request).
  static String allMissing(SubtitleTarget target) => '${target.key}:missing';

  /// An upload to a movie or episode.
  static String upload(SubtitleTarget target) => '${target.key}:upload';

  /// "Search missing" of one season.
  static String season(int seriesId, int season) => 'season:$seriesId:$season';

  /// "Search missing" of a whole series.
  static String series(int seriesId) => 'series:$seriesId';

  /// Whether [row] of [target] is busy in [state].
  static bool rowBusy(
    BazarrActivityState state,
    SubtitleTarget target,
    SubtitleRow row,
  ) =>
      state.isBusy(SubtitleBusyKeys.row(target, row.key)) ||
      (row.state == SubtitleState.missing &&
          state.isBusy(SubtitleBusyKeys.allMissing(target)));
}

/// The subtitle actions of one Bazarr: searches, uploads, deletes, the
/// subtitle tools and profile changes, each run through
/// [bazarrActivityProvider] so its row stays busy and the data refreshes
/// once Bazarr's jobs finish, with the confirmations and errors the UI
/// shows.
///
/// Holds the [ProviderContainer], not a widget's ref, so an action that
/// outlives the widget that started it still completes.
class SubtitleActions {
  SubtitleActions({
    required this.container,
    required this.bazarr,
    required this.notify,
  });

  /// Actions for [bazarr] from [context]'s provider scope, notifying with a
  /// SnackBar unless [notify] is given.
  factory SubtitleActions.of(
    BuildContext context, {
    required Instance bazarr,
    SubtitleNotify? notify,
  }) {
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    return SubtitleActions(
      container: ProviderScope.containerOf(context, listen: false),
      bazarr: bazarr,
      notify: notify ??
          (String message) {
            messenger
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          },
    );
  }

  final ProviderContainer container;
  final Instance bazarr;
  final SubtitleNotify notify;

  BazarrActivity get _activity =>
      container.read(bazarrActivityProvider(bazarr.id).notifier);

  BazarrActivityState get _state =>
      container.read(bazarrActivityProvider(bazarr.id));

  /// What an action on [target] can change.
  List<WatchedProvider> refreshFor(SubtitleTarget target) => <WatchedProvider>[
        ...switch (target) {
          MovieTarget(:final int radarrId) => <WatchedProvider>[
              bazarrMovieItemProvider((bazarr, radarrId)),
              bazarrMoviesProvider(bazarr),
            ],
          EpisodeTarget(:final int seriesId) => <WatchedProvider>[
              bazarrEpisodesProvider((instance: bazarr, seriesId: seriesId)),
              bazarrSeriesItemProvider((bazarr, seriesId)),
              bazarrSeriesProvider(bazarr),
            ],
        },
        bazarrBadgesProvider(bazarr),
        ...bazarrHistoryRefresh(bazarr),
      ];

  /// What a profile change of [owner] can change.
  List<WatchedProvider> refreshForProfile(ProfileOwner owner) =>
      switch (owner) {
        MovieProfileOwner(:final int radarrId) => <WatchedProvider>[
            bazarrMovieItemProvider((bazarr, radarrId)),
          ],
        SeriesProfileOwner(:final int seriesId) => <WatchedProvider>[
            bazarrSeriesItemProvider((bazarr, seriesId)),
            bazarrEpisodesProvider((instance: bazarr, seriesId: seriesId)),
          ],
      };

  Future<T> _run<T>(
    String busyKey,
    Future<T> Function(BazarrApi api) action, {
    required List<WatchedProvider> refresh,
    Duration? maxDuration,
  }) =>
      _activity.run<T>(
        busyKey,
        action,
        refresh: refresh,
        maxDuration: maxDuration,
      );

  // --- Searches ---

  /// Searches one missing language.
  Future<void> searchLanguage(SubtitleTarget target, SubtitleRow row) async {
    try {
      await _run<void>(
        SubtitleBusyKeys.row(target, row.key),
        (BazarrApi api) => api.searchLanguage(target, _choiceOf(row)),
        refresh: refreshFor(target),
      );
    } on Object {
      notify("Couldn't start the search");
      return;
    }
    notify('Searching ${row.name} subtitles…');
  }

  /// The block's "Search": every missing language of a movie (one request)
  /// or of an episode (one per language not already being searched).
  Future<void> searchAllMissing(
    SubtitleTarget target,
    List<SubtitleRow> rows,
  ) async {
    final List<SubtitleRow> missing = rows
        .where((SubtitleRow r) => r.state == SubtitleState.missing)
        .toList(growable: false);
    if (missing.isEmpty) {
      notify('No subtitles are missing');
      return;
    }
    final BazarrActivityState state = _state;
    final List<SubtitleRow> todo = missing
        .where(
          (SubtitleRow r) => !SubtitleBusyKeys.rowBusy(state, target, r),
        )
        .toList(growable: false);
    if (todo.isEmpty) {
      notify('Already searching');
      return;
    }
    // A movie searches every missing language in one request.
    final List<SubtitleRow> searched = target is MovieTarget ? missing : todo;
    final String message = searched.length == 1
        ? 'Searching ${searched.single.name} subtitles…'
        : 'Searching ${searched.length} missing languages…';
    switch (target) {
      case MovieTarget(:final int radarrId):
        try {
          await _run<void>(
            SubtitleBusyKeys.allMissing(target),
            (BazarrApi api) => api.searchMissingMovie(radarrId),
            refresh: refreshFor(target),
          );
        } on Object {
          notify("Couldn't start the search");
          return;
        }
      case EpisodeTarget():
        final List<bool> started = await Future.wait(<Future<bool>>[
          for (final SubtitleRow row in todo)
            _run<void>(
              SubtitleBusyKeys.row(target, row.key),
              (BazarrApi api) => api.searchLanguage(target, _choiceOf(row)),
              refresh: refreshFor(target),
            ).then((_) => true, onError: (Object _) => false),
        ]);
        if (!started.contains(true)) {
          notify("Couldn't start the search");
          return;
        }
    }
    notify(message);
  }

  /// Whether a bulk search of [seriesId] under [key] overlaps one whose
  /// requests still run: the series search covers every season.
  bool _bulkOverlaps(int seriesId, String key) {
    final Map<String, int> inFlight = _state.inFlight;
    final String seriesKey = SubtitleBusyKeys.series(seriesId);
    if (key == seriesKey) {
      return inFlight.keys.any(
        (String k) => k == seriesKey || k.startsWith('season:$seriesId:'),
      );
    }
    return inFlight.containsKey(key) || inFlight.containsKey(seriesKey);
  }

  /// Searches every missing language of every episode of [season], at most
  /// four requests at a time. Nothing to do when nothing is missing.
  Future<void> searchSeason({
    required int seriesId,
    required int season,
    required List<BazarrEpisode> episodes,
  }) async {
    final List<BazarrEpisode> gaps = episodes
        .where(
          (BazarrEpisode e) =>
              (e.season ?? 0) == season && e.missingSubtitles.isNotEmpty,
        )
        .toList(growable: false);
    if (gaps.isEmpty) {
      return;
    }
    final String key = SubtitleBusyKeys.season(seriesId, season);
    if (_bulkOverlaps(seriesId, key)) {
      notify('That search is still running');
      return;
    }
    final List<(EpisodeTarget, LanguageChoice)> requests =
        <(EpisodeTarget, LanguageChoice)>[
      for (final BazarrEpisode e in gaps)
        for (final BazarrSubtitle m in e.missingSubtitles)
          (
            EpisodeTarget(seriesId, e.sonarrEpisodeId),
            LanguageChoice(code2: m.code2, forced: m.forced, hi: m.hi),
          ),
    ];
    try {
      await _run<void>(
        key,
        (BazarrApi api) => runConcurrently<(EpisodeTarget, LanguageChoice)>(
          requests,
          ((EpisodeTarget, LanguageChoice) r) => api.searchLanguage(r.$1, r.$2),
        ),
        refresh: refreshFor(EpisodeTarget(seriesId, 0)),
        maxDuration: bazarrSearchAllMaxDuration,
      );
    } on Object {
      notify("Couldn't start the search");
      return;
    }
    final int n = gaps.length;
    notify('Searching subtitles for $n episode${n == 1 ? '' : 's'}…');
  }

  /// Searches every missing language of a whole series.
  Future<void> searchSeries({
    required int seriesId,
    required String title,
  }) async {
    final String key = SubtitleBusyKeys.series(seriesId);
    if (_bulkOverlaps(seriesId, key)) {
      notify('That search is still running');
      return;
    }
    try {
      await _run<void>(
        key,
        (BazarrApi api) => api.searchMissingSeries(seriesId),
        refresh: refreshFor(EpisodeTarget(seriesId, 0)),
        maxDuration: bazarrSearchAllMaxDuration,
      );
    } on Object {
      notify("Couldn't start the search");
      return;
    }
    notify(
      'Searching missing subtitles for '
      '${title.isEmpty ? 'this show' : title}…',
    );
  }

  // --- Files and tools ---

  /// Uploads [bytes] as [fileName]. Throws on failure: the upload sheet
  /// shows the error itself.
  Future<void> upload(
    SubtitleTarget target,
    LanguageChoice language, {
    required String fileName,
    required Uint8List bytes,
  }) =>
      _run<void>(
        SubtitleBusyKeys.upload(target),
        (BazarrApi api) => api.uploadSubtitle(
          target,
          language,
          MultipartFile.fromBytes(bytes, filename: fileName),
        ),
        refresh: refreshFor(target),
      );

  /// Deletes the external file of [row].
  Future<void> delete(SubtitleTarget target, SubtitleRow row) async {
    final SubtitleTrack? track = row.track;
    if (track == null) {
      return;
    }
    try {
      await _run<void>(
        SubtitleBusyKeys.row(target, row.key),
        (BazarrApi api) => api.deleteSubtitle(target, bazarrSubtitleOf(track)),
        refresh: refreshFor(target),
      );
    } on Object {
      notify("Couldn't delete the subtitle");
      return;
    }
    notify('Deleted ${row.name} subtitle');
  }

  /// Runs a subtitle tool on [row]; [started] confirms it.
  Future<void> runTool(
    SubtitleTarget target,
    SubtitleRow row,
    SubtitleToolAction action, {
    required String started,
  }) async {
    try {
      await applyTool(target, row, action);
    } on Object {
      notify("Bazarr couldn't run that");
      return;
    }
    notify(started);
  }

  /// Runs a subtitle tool on [row] and throws on failure, for a sheet that
  /// shows the error itself.
  Future<void> applyTool(
    SubtitleTarget target,
    SubtitleRow row,
    SubtitleToolAction action,
  ) async {
    final SubtitleTrack? track = row.track;
    if (track == null) {
      return;
    }
    await _run<void>(
      SubtitleBusyKeys.row(target, row.key),
      (BazarrApi api) =>
          api.runSubtitleTool(target, bazarrSubtitleOf(track), action),
      refresh: refreshFor(target),
    );
  }

  // --- Profile ---

  /// Sets the language profile of [owner] ([profileId] null: none);
  /// [name] names it in the confirmation.
  Future<void> setProfile(
    ProfileOwner owner,
    int? profileId, {
    required String name,
  }) async {
    try {
      await _run<void>(
        owner.busyKey,
        (BazarrApi api) => switch (owner) {
          MovieProfileOwner(:final int radarrId) =>
            api.setLanguageProfile(radarrId: radarrId, profileId: profileId),
          SeriesProfileOwner(:final int seriesId) =>
            api.setLanguageProfile(seriesId: seriesId, profileId: profileId),
        },
        refresh: refreshForProfile(owner),
      );
    } on Object {
      notify("Couldn't change the language profile");
      return;
    }
    notify('Language profile set to $name');
  }

  static LanguageChoice _choiceOf(SubtitleRow row) =>
      LanguageChoice(code2: row.code2, forced: row.forced, hi: row.hi);
}
