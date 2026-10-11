import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bazarr_api.dart';
import 'models/bazarr_models.dart';

/// A [BazarrApi] for an instance, over the shared `instanceDioProvider`.
final bazarrApiProvider = FutureProvider.family<BazarrApi, Instance>(
    (Ref ref, Instance instance) async {
  final dio = await ref.watch(instanceDioProvider(instance).future);
  return BazarrApi(dio);
});

/// Summary badge counts for an instance.
final bazarrBadgesProvider = FutureProvider.family<BazarrBadges, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getBadges();
});

/// The unified "wanted subtitles" list (episodes + movies) for an instance.
final bazarrWantedProvider =
    FutureProvider.family<List<BazarrWantedRow>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  final List<BazarrWantedEpisode> eps = await api.getWantedEpisodes();
  final List<BazarrWantedMovie> movies = await api.getWantedMovies();
  return <BazarrWantedRow>[
    for (final BazarrWantedEpisode e in eps)
      BazarrWantedRow(
        title: e.seriesTitle,
        subtitle: <String>[
          if (e.episodeNumber.isNotEmpty) e.episodeNumber,
          if (e.episodeTitle.isNotEmpty) e.episodeTitle,
        ].join(' · '),
        missing: e.missingSubtitles,
        isMovie: false,
      ),
    for (final BazarrWantedMovie m in movies)
      BazarrWantedRow(
        title: m.title,
        subtitle: 'Movie',
        missing: m.missingSubtitles,
        isMovie: true,
      ),
  ];
});

/// All series with subtitle status, sorted by title.
final bazarrSeriesProvider =
    FutureProvider.family<List<BazarrSeries>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  final List<BazarrSeries> list = await api.getSeries();
  list.sort(
    (BazarrSeries a, BazarrSeries b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return list;
});

/// All movies with subtitle status, sorted by title.
final bazarrMoviesProvider =
    FutureProvider.family<List<BazarrMovie>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  final List<BazarrMovie> list = await api.getMovies();
  list.sort(
    (BazarrMovie a, BazarrMovie b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return list;
});

/// Args for [bazarrEpisodesProvider]: an instance plus the Sonarr series id.
typedef BazarrEpisodesArgs = ({Instance instance, int seriesId});

/// Episodes for one series, sorted by season then episode number.
final bazarrEpisodesProvider =
    FutureProvider.family<List<BazarrEpisode>, BazarrEpisodesArgs>((
  Ref ref,
  BazarrEpisodesArgs args,
) async {
  final BazarrApi api =
      await ref.watch(bazarrApiProvider(args.instance).future);
  final List<BazarrEpisode> eps = await api.getEpisodes(args.seriesId);
  eps.sort((BazarrEpisode a, BazarrEpisode b) {
    final int s = (a.season ?? 0).compareTo(b.season ?? 0);
    return s != 0 ? s : (a.episode ?? 0).compareTo(b.episode ?? 0);
  });
  return eps;
});

/// Unified subtitle history (episodes + movies), newest first.
final bazarrHistoryProvider =
    FutureProvider.family<List<BazarrHistoryItem>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  final List<BazarrHistoryItem> eps = await api.getEpisodeHistory();
  final List<BazarrHistoryItem> movies = await api.getMovieHistory();
  final List<BazarrHistoryItem> all = <BazarrHistoryItem>[...eps, ...movies];
  all.sort((BazarrHistoryItem a, BazarrHistoryItem b) {
    final DateTime? da = _parseHistoryTs(a.parsedTimestamp);
    final DateTime? db = _parseHistoryTs(b.parsedTimestamp);
    if (da == null || db == null) {
      return 0;
    }
    return db.compareTo(da);
  });
  return all;
});

/// Unified blacklist (episodes + movies). The movies endpoint errors on some
/// Bazarr versions, so it is tolerated independently of the episodes one.
final bazarrBlacklistProvider =
    FutureProvider.family<List<BazarrBlacklistItem>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  final List<BazarrBlacklistItem> eps = await api.getEpisodeBlacklist();
  List<BazarrBlacklistItem> movies = const <BazarrBlacklistItem>[];
  try {
    movies = await api.getMovieBlacklist();
  } on Object catch (_) {
    // Tolerate the movies-blacklist quirk; show episodes regardless.
  }
  return <BazarrBlacklistItem>[...eps, ...movies];
});

/// Parses Bazarr's `parsed_timestamp` ("MM/DD/YY HH:MM:SS") for sorting.
DateTime? _parseHistoryTs(String s) {
  try {
    final List<String> parts = s.trim().split(' ');
    if (parts.length < 2) {
      return null;
    }
    final List<String> d = parts[0].split('/');
    final List<String> t = parts[1].split(':');
    if (d.length < 3 || t.length < 3) {
      return null;
    }
    int yy = int.parse(d[2]);
    if (yy < 100) {
      yy += 2000;
    }
    return DateTime(
      yy,
      int.parse(d[0]),
      int.parse(d[1]),
      int.parse(t[0]),
      int.parse(t[1]),
      int.parse(t[2]),
    );
  } on Object {
    return null;
  }
}

/// System status (versions, OS, database, uptime). Also the source of the
/// version gates (`bazarrVersionInfoProvider`), so it refreshes itself after
/// an hour to pick up a Bazarr upgrade.
final bazarrSystemStatusProvider =
    FutureProvider.family<BazarrSystemStatus, Instance>((
  Ref ref,
  Instance instance,
) async {
  final Timer refreshTimer =
      Timer(const Duration(hours: 1), ref.invalidateSelf);
  ref.onDispose(refreshTimer.cancel);
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getSystemStatus();
});

/// Active health issues (empty when healthy).
final bazarrSystemHealthProvider =
    FutureProvider.family<List<BazarrHealthItem>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getSystemHealth();
});

/// Scheduled tasks.
final bazarrSystemTasksProvider =
    FutureProvider.family<List<BazarrSystemTask>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getSystemTasks();
});

/// Subtitle provider statuses.
final bazarrProviderStatusesProvider =
    FutureProvider.family<List<BazarrProviderStatus>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getProviderStatuses();
});

/// Existing backups.
final bazarrBackupsProvider =
    FutureProvider.family<List<BazarrBackup>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getBackups();
});

/// Recent log lines, newest first.
final bazarrLogsProvider =
    FutureProvider.family<List<BazarrLogEntry>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getLogs();
});

/// All subtitle languages with enabled flags (Settings > Languages).
final bazarrLanguagesProvider =
    FutureProvider.family<List<BazarrLanguage>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  final List<BazarrLanguage> list = await api.getLanguages();
  list.sort(
    (BazarrLanguage a, BazarrLanguage b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return list;
});

/// Full Bazarr settings object (Settings > Providers: enabled list + per-
/// provider config sections).
final bazarrSettingsProvider =
    FutureProvider.family<Map<String, dynamic>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getBazarrSettings();
});

/// Language profiles (Settings > Language Profiles).
final bazarrProfilesProvider =
    FutureProvider.family<List<BazarrLanguageProfile>, Instance>((
  Ref ref,
  Instance instance,
) async {
  final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
  return api.getProfiles();
});
