import 'package:freezed_annotation/freezed_annotation.dart';

part 'bazarr_models.freezed.dart';
part 'bazarr_models.g.dart';

/// `GET /api/badges` → summary counts shown in the header.
@freezed
abstract class BazarrBadges with _$BazarrBadges {
  const factory BazarrBadges({
    @Default(0) int episodes,
    @Default(0) int movies,
    @Default(0) int providers,
  }) = _BazarrBadges;

  factory BazarrBadges.fromJson(Map<String, dynamic> json) =>
      _$BazarrBadgesFromJson(json);
}

/// `GET /api/episodes/wanted` → `{ "data": [ … ], "total": N }`.
@freezed
abstract class BazarrWantedEpisodes with _$BazarrWantedEpisodes {
  const factory BazarrWantedEpisodes({
    @Default(<BazarrWantedEpisode>[]) List<BazarrWantedEpisode> data,
    @Default(0) int total,
  }) = _BazarrWantedEpisodes;

  factory BazarrWantedEpisodes.fromJson(Map<String, dynamic> json) =>
      _$BazarrWantedEpisodesFromJson(json);
}

@freezed
abstract class BazarrWantedEpisode with _$BazarrWantedEpisode {
  const factory BazarrWantedEpisode({
    @JsonKey(name: 'seriesTitle') @Default('') String seriesTitle,
    @JsonKey(name: 'episodeTitle') @Default('') String episodeTitle,
    @JsonKey(name: 'episode_number') @Default('') String episodeNumber,
    @JsonKey(name: 'sonarrSeriesId') @Default(0) int sonarrSeriesId,
    @JsonKey(name: 'sonarrEpisodeId') @Default(0) int sonarrEpisodeId,
    @JsonKey(name: 'missing_subtitles')
    @Default(<BazarrSubtitle>[])
    List<BazarrSubtitle> missingSubtitles,
  }) = _BazarrWantedEpisode;

  factory BazarrWantedEpisode.fromJson(Map<String, dynamic> json) =>
      _$BazarrWantedEpisodeFromJson(json);
}

/// `GET /api/movies/wanted` → `{ "data": [ … ], "total": N }`.
@freezed
abstract class BazarrWantedMovies with _$BazarrWantedMovies {
  const factory BazarrWantedMovies({
    @Default(<BazarrWantedMovie>[]) List<BazarrWantedMovie> data,
    @Default(0) int total,
  }) = _BazarrWantedMovies;

  factory BazarrWantedMovies.fromJson(Map<String, dynamic> json) =>
      _$BazarrWantedMoviesFromJson(json);
}

@freezed
abstract class BazarrWantedMovie with _$BazarrWantedMovie {
  const factory BazarrWantedMovie({
    @Default('') String title,
    @JsonKey(name: 'radarrId') @Default(0) int radarrId,
    @JsonKey(name: 'missing_subtitles')
    @Default(<BazarrSubtitle>[])
    List<BazarrSubtitle> missingSubtitles,
  }) = _BazarrWantedMovie;

  factory BazarrWantedMovie.fromJson(Map<String, dynamic> json) =>
      _$BazarrWantedMovieFromJson(json);
}

/// One subtitle entry, used for both present subtitles and missing ones.
/// Among present subtitles an external file carries a [path], an embedded
/// track (inside the video file) has none. Bazarr returns these as objects
/// with snake_case language codes.
@freezed
abstract class BazarrSubtitle with _$BazarrSubtitle {
  const factory BazarrSubtitle({
    @Default('') String name,
    @Default('') String code2,
    @Default('') String code3,
    @Default(false) bool hi,
    @Default(false) bool forced,
    String? path,

    /// Bazarr's subtitle row id. Addresses an embedded track (no [path]) in
    /// `PATCH /subtitles` as `subtitles_id`; null while Bazarr hasn't indexed
    /// the track.
    int? id,
    @JsonKey(name: 'embedded_track_id') int? embeddedTrackId,
    @JsonKey(name: 'file_size') int? fileSize,
  }) = _BazarrSubtitle;

  factory BazarrSubtitle.fromJson(Map<String, dynamic> json) =>
      _$BazarrSubtitleFromJson(json);
}

/// `GET /api/series` data item (Sonarr-backed). [episodeMissingCount] is the
/// number of episodes still missing subtitles.
@freezed
abstract class BazarrSeries with _$BazarrSeries {
  const factory BazarrSeries({
    @Default(0) int sonarrSeriesId,
    @Default('') String title,
    @JsonKey(fromJson: _yearFromJson) int? year,
    @Default(false) bool monitored,
    int? profileId,
    @Default(0) int episodeFileCount,
    @Default(0) int episodeMissingCount,
    String? poster,
    String? seriesType,
    @JsonKey(name: 'audio_language')
    @Default(<BazarrLanguage>[])
    List<BazarrLanguage> audioLanguage,
    String? path,
    bool? ended,
  }) = _BazarrSeries;

  factory BazarrSeries.fromJson(Map<String, dynamic> json) =>
      _$BazarrSeriesFromJson(json);
}

/// `GET /api/movies` data item (Radarr-backed), with its present and missing
/// subtitle lists inline.
@freezed
abstract class BazarrMovie with _$BazarrMovie {
  const factory BazarrMovie({
    @Default(0) int radarrId,
    @Default('') String title,
    @JsonKey(fromJson: _yearFromJson) int? year,
    @Default(false) bool monitored,
    int? profileId,
    String? poster,
    @Default(<BazarrSubtitle>[]) List<BazarrSubtitle> subtitles,
    @JsonKey(name: 'missing_subtitles')
    @Default(<BazarrSubtitle>[])
    List<BazarrSubtitle> missingSubtitles,
    @JsonKey(name: 'audio_language')
    @Default(<BazarrLanguage>[])
    List<BazarrLanguage> audioLanguage,
    String? path,
    String? sceneName,
  }) = _BazarrMovie;

  factory BazarrMovie.fromJson(Map<String, dynamic> json) =>
      _$BazarrMovieFromJson(json);
}

/// `GET /api/episodes?seriesid[]=` data item, with present and missing subtitle
/// lists inline.
@freezed
abstract class BazarrEpisode with _$BazarrEpisode {
  const factory BazarrEpisode({
    @Default(0) int sonarrEpisodeId,
    @Default(0) int sonarrSeriesId,
    @Default('') String title,
    int? season,
    int? episode,
    @Default(false) bool monitored,
    @Default(<BazarrSubtitle>[]) List<BazarrSubtitle> subtitles,
    @JsonKey(name: 'missing_subtitles')
    @Default(<BazarrSubtitle>[])
    List<BazarrSubtitle> missingSubtitles,
    @JsonKey(name: 'audio_language')
    @Default(<BazarrLanguage>[])
    List<BazarrLanguage> audioLanguage,
    String? path,
    String? sceneName,
  }) = _BazarrEpisode;

  factory BazarrEpisode.fromJson(Map<String, dynamic> json) =>
      _$BazarrEpisodeFromJson(json);
}

/// One manual-search result from `GET /providers/episodes|movies`. The
/// download POST round-trips [provider], [subtitle] (a base64 token), and the
/// string flags [hearingImpaired]/[forced]/[originalFormat] back to Bazarr.
@freezed
abstract class BazarrSubtitleSearchResult with _$BazarrSubtitleSearchResult {
  const factory BazarrSubtitleSearchResult({
    @Default('') String language,
    @Default('') String provider,
    @Default(0) num score,
    @JsonKey(name: 'orig_score') num? origScore,
    @JsonKey(name: 'score_without_hash') num? scoreWithoutHash,
    @Default(<String>[]) List<String> matches,
    @JsonKey(name: 'dont_matches')
    @Default(<String>[])
    List<String> dontMatches,
    @JsonKey(name: 'hearing_impaired') @Default('False') String hearingImpaired,
    @Default('False') String forced,
    @JsonKey(name: 'original_format') @Default('False') String originalFormat,
    @Default('') String subtitle,
    @JsonKey(name: 'release_info')
    @Default(<String>[])
    List<String> releaseInfo,
    String? uploader,
    String? url,
  }) = _BazarrSubtitleSearchResult;

  factory BazarrSubtitleSearchResult.fromJson(Map<String, dynamic> json) =>
      _$BazarrSubtitleSearchResultFromJson(json);
}

/// One entry from `GET /episodes/history` or `/movies/history`. [isMovie] is
/// set by the client (not in the JSON) so the two can share a unified list.
/// [action] is Bazarr's history action code (0 deleted, 1 downloaded,
/// 2 downloaded manually, 3 upgraded, 4 uploaded, 5 synced, 6 translated,
/// 7 extracted); [description] is the human-readable summary.
@freezed
abstract class BazarrHistoryItem with _$BazarrHistoryItem {
  const factory BazarrHistoryItem({
    @JsonKey(name: 'seriesTitle') @Default('') String seriesTitle,
    @Default('') String title,
    @JsonKey(name: 'episode_number') @Default('') String episodeNumber,
    @JsonKey(name: 'episodeTitle') @Default('') String episodeTitle,
    @Default('') String description,
    @Default('') String timestamp,
    @JsonKey(name: 'parsed_timestamp') @Default('') String parsedTimestamp,
    @Default('') String provider,
    @Default('') String score,
    @Default(0) int action,
    BazarrSubtitle? language,
    @Default(false) bool blacklisted,
    @JsonKey(name: 'radarrId') int? radarrId,
    @JsonKey(name: 'sonarrSeriesId') int? sonarrSeriesId,
    @JsonKey(name: 'sonarrEpisodeId') int? sonarrEpisodeId,
    @JsonKey(name: 'subs_id') String? subsId,
    @JsonKey(name: 'subtitles_path') String? subtitlesPath,
    @Default(<String>[]) List<String> matches,
    @JsonKey(name: 'dont_matches')
    @Default(<String>[])
    List<String> dontMatches,
    @Default(false) bool upgradable,
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(false)
    bool isMovie,
  }) = _BazarrHistoryItem;

  factory BazarrHistoryItem.fromJson(Map<String, dynamic> json) =>
      _$BazarrHistoryItemFromJson(json);
}

/// One entry from `GET /episodes/blacklist` or `/movies/blacklist`. Removal
/// (`DELETE`) is keyed by [provider] + [subsId]. [isMovie] is client-set.
@freezed
abstract class BazarrBlacklistItem with _$BazarrBlacklistItem {
  const factory BazarrBlacklistItem({
    @JsonKey(name: 'seriesTitle') @Default('') String seriesTitle,
    @Default('') String title,
    @JsonKey(name: 'episode_number') @Default('') String episodeNumber,
    @Default('') String provider,
    @JsonKey(name: 'subs_id') @Default('') String subsId,
    @Default('') String timestamp,
    @JsonKey(name: 'parsed_timestamp') @Default('') String parsedTimestamp,
    BazarrSubtitle? language,
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(false)
    bool isMovie,
  }) = _BazarrBlacklistItem;

  factory BazarrBlacklistItem.fromJson(Map<String, dynamic> json) =>
      _$BazarrBlacklistItemFromJson(json);
}

/// `GET /system/status`.
@freezed
abstract class BazarrSystemStatus with _$BazarrSystemStatus {
  const factory BazarrSystemStatus({
    @JsonKey(name: 'bazarr_version') @Default('') String bazarrVersion,
    @JsonKey(name: 'package_version') @Default('') String packageVersion,
    @JsonKey(name: 'sonarr_version') @Default('') String sonarrVersion,
    @JsonKey(name: 'radarr_version') @Default('') String radarrVersion,
    @JsonKey(name: 'operating_system') @Default('') String operatingSystem,
    @JsonKey(name: 'python_version') @Default('') String pythonVersion,
    @JsonKey(name: 'database_engine') @Default('') String databaseEngine,
    @JsonKey(name: 'database_migration') @Default('') String databaseMigration,
    @Default('') String timezone,
    @JsonKey(name: 'cpu_cores') int? cpuCores,
    @JsonKey(name: 'start_time') double? startTime,
  }) = _BazarrSystemStatus;

  factory BazarrSystemStatus.fromJson(Map<String, dynamic> json) =>
      _$BazarrSystemStatusFromJson(json);
}

/// One entry from `GET /system/health` (the list is empty when healthy).
@freezed
abstract class BazarrHealthItem with _$BazarrHealthItem {
  const factory BazarrHealthItem({
    @Default('') String object,
    @Default('') String issue,
  }) = _BazarrHealthItem;

  factory BazarrHealthItem.fromJson(Map<String, dynamic> json) =>
      _$BazarrHealthItemFromJson(json);
}

/// One scheduled task from `GET /system/tasks`. Run via `POST ?taskid=[jobId]`.
@freezed
abstract class BazarrSystemTask with _$BazarrSystemTask {
  const factory BazarrSystemTask({
    @JsonKey(name: 'job_id') @Default('') String jobId,
    @Default('') String name,
    @Default('') String interval,
    @JsonKey(name: 'job_running') @Default(false) bool jobRunning,
    @JsonKey(name: 'next_run_in') @Default('') String nextRunIn,
  }) = _BazarrSystemTask;

  factory BazarrSystemTask.fromJson(Map<String, dynamic> json) =>
      _$BazarrSystemTaskFromJson(json);
}

/// One subtitle provider's status from `GET /providers`. [status] is "Good" or
/// a throttle reason; [retry] is "-" or a retry time.
@freezed
abstract class BazarrProviderStatus with _$BazarrProviderStatus {
  const factory BazarrProviderStatus({
    @Default('') String name,
    @Default('') String status,
    @Default('') String retry,
  }) = _BazarrProviderStatus;

  factory BazarrProviderStatus.fromJson(Map<String, dynamic> json) =>
      _$BazarrProviderStatusFromJson(json);
}

/// One backup from `GET /system/backups`. Delete via `DELETE ?filename=`.
@freezed
abstract class BazarrBackup with _$BazarrBackup {
  const factory BazarrBackup({
    @Default('') String type,
    @Default('') String filename,
    @Default('') String date,
  }) = _BazarrBackup;

  factory BazarrBackup.fromJson(Map<String, dynamic> json) =>
      _$BazarrBackupFromJson(json);
}

/// One log line from `GET /system/logs`.
@freezed
abstract class BazarrLogEntry with _$BazarrLogEntry {
  const factory BazarrLogEntry({
    @Default('') String timestamp,
    @Default('') String type,
    @Default('') String message,
    String? exception,
  }) = _BazarrLogEntry;

  factory BazarrLogEntry.fromJson(Map<String, dynamic> json) =>
      _$BazarrLogEntryFromJson(json);
}

/// One subtitle language from `GET /system/languages` (all ~187; [enabled]
/// marks the active ones). [code2] is the value `languages-enabled` expects.
/// Also the shape of an item's `audio_language` entries, which carry no
/// `enabled` flag (it defaults to false).
@freezed
abstract class BazarrLanguage with _$BazarrLanguage {
  const factory BazarrLanguage({
    @Default('') String name,
    @Default('') String code2,
    @Default('') String code3,
    @Default(false) bool enabled,
  }) = _BazarrLanguage;

  factory BazarrLanguage.fromJson(Map<String, dynamic> json) =>
      _$BazarrLanguageFromJson(json);

  const BazarrLanguage._();

  /// The code to send in `languages-enabled` (code2, or code3 if no code2).
  String get code => code2.isNotEmpty ? code2 : code3;
}

/// One language entry inside a [BazarrLanguageProfile]. Bazarr stores the flags
/// as "True"/"False" strings.
///
/// [toJson] is hand-written so an unknown `audio_only_include` is left out
/// rather than sent as null (json_serializable's `includeIfNull: false` needs
/// a newer language version than this package targets).
@Freezed(toJson: false)
abstract class BazarrProfileItem with _$BazarrProfileItem {
  const factory BazarrProfileItem({
    @Default(0) int id,
    @Default('') String language,
    @Default('False') String hi,
    @Default('False') String forced,
    @JsonKey(name: 'audio_exclude') @Default('False') String audioExclude,

    /// "True"/"False" on Bazarr versions that know the field; null (and left
    /// out of [toJson], which `setProfiles` round-trips) on older ones.
    @JsonKey(name: 'audio_only_include') String? audioOnlyInclude,
  }) = _BazarrProfileItem;

  factory BazarrProfileItem.fromJson(Map<String, dynamic> json) =>
      _$BazarrProfileItemFromJson(json);

  const BazarrProfileItem._();

  /// The shape Bazarr expects back in `languages-profiles`.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'language': language,
        'hi': hi,
        'forced': forced,
        'audio_exclude': audioExclude,
        if (audioOnlyInclude != null) 'audio_only_include': audioOnlyInclude,
      };
}

/// A language profile from `GET /system/languages/profiles`. Saved (full list)
/// via the `languages-profiles` JSON string in the settings POST. The model's
/// `toJson` round-trips the exact shape Bazarr expects.
@freezed
abstract class BazarrLanguageProfile with _$BazarrLanguageProfile {
  const factory BazarrLanguageProfile({
    @Default(0) int profileId,
    @Default('') String name,
    @Default(<BazarrProfileItem>[]) List<BazarrProfileItem> items,
    int? cutoff,
    @Default(<String>[]) List<String> mustContain,
    @Default(<String>[]) List<String> mustNotContain,
    int? originalFormat,
    String? tag,
  }) = _BazarrLanguageProfile;

  factory BazarrLanguageProfile.fromJson(Map<String, dynamic> json) =>
      _$BazarrLanguageProfileFromJson(json);
}

/// One background job from `GET /system/jobs` (Bazarr 1.5.6+).
@freezed
abstract class BazarrJob with _$BazarrJob {
  const factory BazarrJob({
    @JsonKey(name: 'job_id') @Default(0) int jobId,
    @JsonKey(name: 'job_name') @Default('') String jobName,
    @Default('') String status,
    @JsonKey(name: 'progress_value') int? progressValue,
    @JsonKey(name: 'progress_max') int? progressMax,
    @JsonKey(name: 'progress_message') String? progressMessage,
  }) = _BazarrJob;

  factory BazarrJob.fromJson(Map<String, dynamic> json) =>
      _$BazarrJobFromJson(json);
}

/// One page of `GET /movies/history` or `/episodes/history`: the entries and
/// the stream's total length (for paging).
class BazarrHistoryPage {
  const BazarrHistoryPage({required this.items, required this.total});

  final List<BazarrHistoryItem> items;
  final int total;
}

/// Bazarr returns `year` as a string ("2026") for series and movies; parse it
/// leniently to an int so the UI can treat it as a number (null if blank).
int? _yearFromJson(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}
