import 'dart:convert';

import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/bazarr_models.dart';
import 'subtitles/bazarr_subtitle_params.dart';

/// Thin client over the Bazarr API.
///
/// Auth is an API-key header (added by `core_networking`'s [AuthInterceptor]),
/// so this rides the shared `instanceDioProvider` Dio.
class BazarrApi {
  BazarrApi(this._dio);

  final Dio _dio;

  /// Receive timeout for subtitle actions. Before 1.5.6 Bazarr answers a
  /// search, download or tool request only once the work is done.
  static const Duration actionTimeout = Duration(seconds: 90);

  /// Receive timeout for a manual search: every enabled provider is asked,
  /// synchronously.
  static const Duration manualSearchTimeout = Duration(seconds: 180);

  static Options get _actionOptions => Options(receiveTimeout: actionTimeout);

  Future<BazarrBadges> getBadges() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('api/badges');
      return BazarrBadges.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<BazarrWantedEpisode>> getWantedEpisodes() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/episodes/wanted',
        queryParameters: <String, dynamic>{'start': 0, 'length': -1},
      );
      return BazarrWantedEpisodes.fromJson(resp.data as Map<String, dynamic>)
          .data;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<BazarrWantedMovie>> getWantedMovies() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/movies/wanted',
        queryParameters: <String, dynamic>{'start': 0, 'length': -1},
      );
      return BazarrWantedMovies.fromJson(resp.data as Map<String, dynamic>)
          .data;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// All series (Sonarr-backed) with subtitle status. `length=-1` returns the
  /// whole list; Bazarr's series rows are lightweight (no episodes).
  Future<List<BazarrSeries>> getSeries() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/series',
        queryParameters: <String, dynamic>{'start': 0, 'length': -1},
      );
      final List<dynamic> data =
          (resp.data as Map<String, dynamic>)['data'] as List<dynamic>;
      return data
          .map((dynamic e) => BazarrSeries.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// All movies (Radarr-backed) with their present/missing subtitle lists.
  Future<List<BazarrMovie>> getMovies() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/movies',
        queryParameters: <String, dynamic>{'start': 0, 'length': -1},
      );
      final List<dynamic> data =
          (resp.data as Map<String, dynamic>)['data'] as List<dynamic>;
      return data
          .map((dynamic e) => BazarrMovie.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Episodes for one series (`seriesid[]=`), each with subtitle status.
  Future<List<BazarrEpisode>> getEpisodes(int seriesId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/episodes',
        queryParameters: <String, dynamic>{'seriesid[]': seriesId},
      );
      final List<dynamic> data =
          (resp.data as Map<String, dynamic>)['data'] as List<dynamic>;
      return data
          .map((dynamic e) => BazarrEpisode.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Manual subtitle search for one episode (`GET /providers/episodes`). The
  /// route reads only the episode id, so the series id is a placeholder.
  Future<List<BazarrSubtitleSearchResult>> searchEpisodeSubtitles(
    int episodeId,
  ) =>
      manualSearch(EpisodeTarget(0, episodeId));

  /// Manual subtitle search for one movie (`GET /providers/movies`).
  Future<List<BazarrSubtitleSearchResult>> searchMovieSubtitles(
    int radarrId,
  ) =>
      manualSearch(MovieTarget(radarrId));

  /// Downloads a chosen manual-search result for an episode
  /// (`POST /providers/episodes`). Round-trips the result's provider/token/flags.
  Future<void> downloadEpisodeSubtitle({
    required int seriesId,
    required int episodeId,
    required BazarrSubtitleSearchResult result,
  }) =>
      downloadResult(EpisodeTarget(seriesId, episodeId), result);

  /// Downloads a chosen manual-search result for a movie
  /// (`POST /providers/movies`).
  Future<void> downloadMovieSubtitle({
    required int radarrId,
    required BazarrSubtitleSearchResult result,
  }) =>
      downloadResult(MovieTarget(radarrId), result);

  /// Deletes a downloaded subtitle from an episode (`DELETE /episodes/subtitles`).
  Future<void> deleteEpisodeSubtitle({
    required int seriesId,
    required int episodeId,
    required BazarrSubtitle subtitle,
  }) =>
      deleteSubtitle(EpisodeTarget(seriesId, episodeId), subtitle);

  /// Deletes a downloaded subtitle from a movie (`DELETE /movies/subtitles`).
  Future<void> deleteMovieSubtitle({
    required int radarrId,
    required BazarrSubtitle subtitle,
  }) =>
      deleteSubtitle(MovieTarget(radarrId), subtitle);

  /// Episode subtitle history (`GET /episodes/history`), newest first.
  Future<List<BazarrHistoryItem>> getEpisodeHistory({int length = 50}) async =>
      (await getHistoryPage(movies: false, length: length)).items;

  /// Movie subtitle history (`GET /movies/history`), newest first.
  Future<List<BazarrHistoryItem>> getMovieHistory({int length = 50}) async =>
      (await getHistoryPage(movies: true, length: length)).items;

  /// One page of the movie or episode history (`GET /{movies,episodes}/
  /// history?start=&length=`), newest first, with the stream's total.
  Future<BazarrHistoryPage> getHistoryPage({
    required bool movies,
    int start = 0,
    int length = 50,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        movies ? 'api/movies/history' : 'api/episodes/history',
        queryParameters: <String, dynamic>{'start': start, 'length': length},
      );
      final dynamic data = resp.data;
      final List<BazarrHistoryItem> items = _maybeListFrom(data)
          .map(
            (dynamic e) => BazarrHistoryItem.fromJson(e as Map<String, dynamic>)
                .copyWith(isMovie: movies),
          )
          .toList();
      final Object? total = data is Map<String, dynamic> ? data['total'] : null;
      return BazarrHistoryPage(
        items: items,
        total: total is num ? total.toInt() : items.length,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Blacklisted episode subtitles (`GET /episodes/blacklist`). No paging params
  /// are sent: Bazarr 500s on an empty movies blacklist when they are present.
  Future<List<BazarrBlacklistItem>> getEpisodeBlacklist() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/episodes/blacklist');
      return _parseBlacklist(resp.data, isMovie: false);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Blacklisted movie subtitles (`GET /movies/blacklist`).
  Future<List<BazarrBlacklistItem>> getMovieBlacklist() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/movies/blacklist');
      return _parseBlacklist(resp.data, isMovie: true);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  List<BazarrBlacklistItem> _parseBlacklist(
    dynamic data, {
    required bool isMovie,
  }) {
    final List<dynamic> list = data is Map<String, dynamic>
        ? ((data['data'] as List<dynamic>?) ?? const <dynamic>[])
        : (data as List<dynamic>);
    return list
        .map(
          (dynamic e) => BazarrBlacklistItem.fromJson(e as Map<String, dynamic>)
              .copyWith(isMovie: isMovie),
        )
        .toList();
  }

  /// Removes a blacklisted episode subtitle (`DELETE /episodes/blacklist`).
  Future<void> removeEpisodeBlacklist({
    required String provider,
    required String subsId,
  }) async {
    try {
      await _dio.delete<dynamic>(
        'api/episodes/blacklist',
        queryParameters: <String, dynamic>{
          'provider': provider,
          'subs_id': subsId,
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Removes a blacklisted movie subtitle (`DELETE /movies/blacklist`).
  Future<void> removeMovieBlacklist({
    required String provider,
    required String subsId,
  }) async {
    try {
      await _dio.delete<dynamic>(
        'api/movies/blacklist',
        queryParameters: <String, dynamic>{
          'provider': provider,
          'subs_id': subsId,
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  // --- System ---

  /// System status (versions, OS, database, uptime).
  Future<BazarrSystemStatus> getSystemStatus() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/system/status');
      final dynamic data = resp.data;
      final Map<String, dynamic> obj = data is Map<String, dynamic>
          ? ((data['data'] as Map<String, dynamic>?) ?? data)
          : <String, dynamic>{};
      return BazarrSystemStatus.fromJson(obj);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Active health issues (`GET /system/health`); empty when healthy.
  Future<List<BazarrHealthItem>> getSystemHealth() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/system/health');
      return _listFrom(resp.data)
          .map(
            (dynamic e) => BazarrHealthItem.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Scheduled tasks (`GET /system/tasks`).
  Future<List<BazarrSystemTask>> getSystemTasks() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/system/tasks');
      return _listFrom(resp.data)
          .map(
            (dynamic e) => BazarrSystemTask.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Runs a scheduled task now (`POST /system/tasks?taskid=`).
  Future<void> runTask(String taskId) async {
    try {
      await _dio.post<dynamic>(
        'api/system/tasks',
        queryParameters: <String, dynamic>{'taskid': taskId},
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Subtitle provider statuses (`GET /providers`).
  Future<List<BazarrProviderStatus>> getProviderStatuses() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('api/providers');
      return _listFrom(resp.data)
          .map(
            (dynamic e) =>
                BazarrProviderStatus.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Resets throttled providers (`POST /providers?action=reset`).
  Future<void> resetProviders() async {
    try {
      await _dio.post<dynamic>(
        'api/providers',
        queryParameters: <String, dynamic>{'action': 'reset'},
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Existing backups (`GET /system/backups`).
  Future<List<BazarrBackup>> getBackups() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/system/backups');
      return _listFrom(resp.data)
          .map((dynamic e) => BazarrBackup.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Creates a backup now (`POST /system/backups`).
  Future<void> createBackup() async {
    try {
      await _dio.post<dynamic>('api/system/backups');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Deletes a backup (`DELETE /system/backups?filename=`).
  Future<void> deleteBackup(String filename) async {
    try {
      await _dio.delete<dynamic>(
        'api/system/backups',
        queryParameters: <String, dynamic>{'filename': filename},
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Recent log lines (`GET /system/logs`), newest first.
  Future<List<BazarrLogEntry>> getLogs() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('api/system/logs');
      return _listFrom(resp.data)
          .map(
            (dynamic e) => BazarrLogEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Clears the logs (`DELETE /system/logs`).
  Future<void> clearLogs() async {
    try {
      await _dio.delete<dynamic>('api/system/logs');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  // --- Settings: languages ---

  /// All subtitle languages (`GET /system/languages`) with their enabled flag.
  Future<List<BazarrLanguage>> getLanguages() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/system/languages');
      return _listFrom(resp.data)
          .map(
            (dynamic e) => BazarrLanguage.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Sets the full set of enabled languages (`POST /system/settings`,
  /// form-urlencoded, `languages-enabled` repeated for each code). A partial
  /// POST: only this field changes, the rest of the config is untouched.
  Future<void> setEnabledLanguages(List<String> codes) async {
    try {
      await _dio.post<dynamic>(
        'api/system/settings',
        data: <String, dynamic>{'languages-enabled': codes},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          listFormat: ListFormat.multi,
        ),
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  // --- Settings: providers ---

  /// The full settings object (`GET /system/settings`). Used for
  /// `general.enabled_providers` and per-provider config sections.
  Future<Map<String, dynamic>> getBazarrSettings() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/system/settings');
      final dynamic data = resp.data;
      if (data is Map<String, dynamic>) {
        return (data['data'] as Map<String, dynamic>?) ?? data;
      }
      return <String, dynamic>{};
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Sets the full set of enabled providers (`settings-general-enabled_providers`
  /// repeated, form-urlencoded). Partial POST: only this field changes.
  Future<void> setEnabledProviders(List<String> keys) async {
    try {
      await _dio.post<dynamic>(
        'api/system/settings',
        data: <String, dynamic>{'settings-general-enabled_providers': keys},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          listFormat: ListFormat.multi,
        ),
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Saves one provider's config: each [fields] entry is posted as
  /// `settings-<provider>-<key>` (form-urlencoded).
  Future<void> setProviderConfig(
    String provider,
    Map<String, String> fields,
  ) async {
    try {
      final Map<String, String> body = <String, String>{
        for (final MapEntry<String, String> e in fields.entries)
          'settings-$provider-${e.key}': e.value,
      };
      await _dio.post<dynamic>(
        'api/system/settings',
        data: body,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  // --- Settings: language profiles ---

  /// All language profiles (`GET /system/languages/profiles`).
  Future<List<BazarrLanguageProfile>> getProfiles() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('api/system/languages/profiles');
      return _listFrom(resp.data)
          .map(
            (dynamic e) =>
                BazarrLanguageProfile.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Saves the full set of profiles (`languages-profiles` JSON in the settings
  /// POST). NOTE: Bazarr persists the profiles but returns 500 from a post-save
  /// hook, so a 500 here is treated as success (other failures rethrow).
  Future<void> setProfiles(List<BazarrLanguageProfile> profiles) async {
    final String json = jsonEncode(
      profiles.map((BazarrLanguageProfile p) => p.toJson()).toList(),
    );
    try {
      await _dio.post<dynamic>(
        'api/system/settings',
        data: <String, dynamic>{'languages-profiles': json},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 500) {
        return; // saved despite the post-save hook error
      }
      throw NetworkException.fromDio(e);
    }
  }

  // --- Subtitles: items ---

  /// Bazarr's view of one Radarr movie (`GET /movies?radarrid[]=`), or null
  /// when Bazarr doesn't know it.
  Future<BazarrMovie?> getMovie(int radarrId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/movies',
        queryParameters: <String, dynamic>{'radarrid[]': radarrId},
      );
      final List<dynamic> list = _maybeListFrom(resp.data);
      return list.isEmpty
          ? null
          : BazarrMovie.fromJson(list.first as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Bazarr's view of one Sonarr series (`GET /series?seriesid[]=`), or null
  /// when Bazarr doesn't know it.
  Future<BazarrSeries?> getSeriesItem(int seriesId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/series',
        queryParameters: <String, dynamic>{'seriesid[]': seriesId},
      );
      final List<dynamic> list = _maybeListFrom(resp.data);
      return list.isEmpty
          ? null
          : BazarrSeries.fromJson(list.first as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Specific episodes by Sonarr episode id (`GET /episodes?episodeid[]=…`,
  /// the key repeated per id).
  Future<List<BazarrEpisode>> getEpisodesByIds(List<int> episodeIds) async {
    if (episodeIds.isEmpty) {
      return const <BazarrEpisode>[];
    }
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/episodes',
        queryParameters: <String, dynamic>{'episodeid[]': episodeIds},
        options: Options(listFormat: ListFormat.multi),
      );
      return _maybeListFrom(resp.data)
          .map((dynamic e) => BazarrEpisode.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// The languages enabled in Bazarr's settings (what profiles can use).
  Future<List<BazarrLanguage>> getEnabledLanguages() async {
    final List<BazarrLanguage> all = await getLanguages();
    return all.where((BazarrLanguage l) => l.enabled).toList();
  }

  // --- Subtitles: background jobs ---

  /// Ids of the background jobs still pending or running (`GET /system/jobs`
  /// with `status=pending` and `status=running`), or null when this Bazarr
  /// has no job queue: before 1.5.6 the route answers 404/405, or falls
  /// through to the web UI (an HTML 200).
  Future<List<int>?> getActiveJobIds() async {
    try {
      final List<Response<dynamic>> responses =
          await Future.wait(<Future<Response<dynamic>>>[
        for (final String status in const <String>['pending', 'running'])
          _dio.get<dynamic>(
            'api/system/jobs',
            queryParameters: <String, dynamic>{'status': status},
          ),
      ]);
      final List<int> ids = <int>[];
      for (final Response<dynamic> resp in responses) {
        final dynamic data = resp.data;
        if (data is! Map<String, dynamic>) {
          return null;
        }
        final Object? jobs = data['data'];
        if (jobs is! List<dynamic>) {
          continue;
        }
        for (final dynamic job in jobs) {
          if (job is Map<String, dynamic>) {
            final Object? id = job['job_id'];
            if (id is num) {
              ids.add(id.toInt());
            }
          }
        }
      }
      return ids;
    } on DioException catch (e) {
      final int? status = e.response?.statusCode;
      if (status == 404 || status == 405) {
        return null;
      }
      throw NetworkException.fromDio(e);
    }
  }

  // --- Subtitles: actions ---
  //
  // Since Bazarr 1.5.6 these return 204 at once and run as background jobs;
  // callers refresh through the job watcher. Before 1.5.6 they block until
  // the work is done, hence [actionTimeout].

  /// Searches one language automatically (`PATCH /{movies,episodes}/
  /// subtitles`, all query params).
  Future<void> searchLanguage(
    SubtitleTarget target,
    LanguageChoice language,
  ) async {
    try {
      await _dio.patch<dynamic>(
        subtitlesRoute(target),
        queryParameters: searchParams(target, language),
        options: _actionOptions,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Searches every missing language of one movie (`PATCH /movies`, JSON).
  Future<void> searchMissingMovie(int radarrId) => _patchAction(
        'api/movies',
        <String, Object>{'radarrid': radarrId, 'action': 'search-missing'},
      );

  /// Searches every missing language of one series (`PATCH /series`, JSON).
  Future<void> searchMissingSeries(int seriesId) => _patchAction(
        'api/series',
        <String, Object>{'seriesid': seriesId, 'action': 'search-missing'},
      );

  /// Searches every wanted subtitle of every movie or every series.
  Future<void> searchWanted({required bool movies}) => _patchAction(
        movies ? 'api/movies' : 'api/series',
        const <String, Object>{'action': 'search-wanted'},
      );

  Future<void> _patchAction(String path, Map<String, Object> body) async {
    try {
      await _dio.patch<dynamic>(
        path,
        data: body,
        options: Options(
          contentType: Headers.jsonContentType,
          receiveTimeout: actionTimeout,
        ),
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Uploads a subtitle file for one language (`POST /{movies,episodes}/
  /// subtitles`, multipart, `forced`/`hi` as lowercase "true"/"false").
  Future<void> uploadSubtitle(
    SubtitleTarget target,
    LanguageChoice language,
    MultipartFile file,
  ) async {
    try {
      final FormData form = FormData.fromMap(<String, dynamic>{
        for (final MapEntry<String, Object> e
            in uploadFields(target, language).entries)
          e.key: e.value.toString(),
        'file': file,
      });
      await _dio.post<dynamic>(
        subtitlesRoute(target),
        data: form,
        options: _actionOptions,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Deletes an external subtitle file (`DELETE /{movies,episodes}/
  /// subtitles`, query; `path` exactly as Bazarr reported it).
  Future<void> deleteSubtitle(
    SubtitleTarget target,
    BazarrSubtitle subtitle,
  ) async {
    try {
      await _dio.delete<dynamic>(
        subtitlesRoute(target),
        queryParameters: deleteParams(target, subtitle),
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Manual search (`GET /providers/{movies,episodes}`): every enabled
  /// provider's candidates for every language in the item's profile. Slow and
  /// synchronous, so it takes a [cancelToken] and [manualSearchTimeout].
  Future<List<BazarrSubtitleSearchResult>> manualSearch(
    SubtitleTarget target, {
    CancelToken? cancelToken,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        providersRoute(target),
        queryParameters: manualSearchParams(target),
        cancelToken: cancelToken,
        options: Options(receiveTimeout: manualSearchTimeout),
      );
      return _maybeListFrom(resp.data)
          .map(
            (dynamic e) =>
                BazarrSubtitleSearchResult.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Downloads one manual-search result (`POST /providers/{movies,
  /// episodes}`). The fields go in a JSON body: `subtitle` is Bazarr's
  /// serialized result, often several KB, which a reverse proxy's URL limit
  /// would reject as a query string.
  Future<void> downloadResult(
    SubtitleTarget target,
    BazarrSubtitleSearchResult result,
  ) async {
    try {
      await _dio.post<dynamic>(
        providersRoute(target),
        data: downloadResultParams(target, result),
        options: Options(
          contentType: Headers.jsonContentType,
          receiveTimeout: actionTimeout,
        ),
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Sync, translate, extract, retime or clean up one subtitle
  /// (`PATCH /subtitles`, query).
  Future<void> runSubtitleTool(
    SubtitleTarget target,
    BazarrSubtitle subtitle,
    SubtitleToolAction action,
  ) async {
    try {
      await _dio.patch<dynamic>(
        'api/subtitles',
        queryParameters: toolParams(target, subtitle, action),
        options: _actionOptions,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Changes the language profile of a movie ([radarrId]) or a series
  /// ([seriesId]); a null [profileId] removes it. Bazarr reads only "" as
  /// "none" ("none" itself answers 404).
  Future<void> setLanguageProfile({
    int? radarrId,
    int? seriesId,
    int? profileId,
  }) async {
    assert(
      (radarrId == null) != (seriesId == null),
      'Pass exactly one of radarrId and seriesId',
    );
    try {
      await _dio.post<dynamic>(
        radarrId != null ? 'api/movies' : 'api/series',
        queryParameters: <String, dynamic>{
          if (radarrId != null) 'radarrid': radarrId else 'seriesid': seriesId,
          'profileid': profileId?.toString() ?? '',
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Blacklists a downloaded subtitle (`POST /{movies,episodes}/blacklist`,
  /// query): Bazarr deletes the file, blocks that provider result and
  /// searches the language again, all in this one call.
  Future<void> blacklistSubtitle(
    SubtitleTarget target, {
    required String provider,
    required String subsId,
    required String language,
    required String subtitlesPath,
  }) async {
    try {
      await _dio.post<dynamic>(
        blacklistRoute(target),
        queryParameters: <String, dynamic>{
          ...targetParams(target),
          'provider': provider,
          'subs_id': subsId,
          'language': language,
          'subtitles_path': subtitlesPath,
        },
        options: _actionOptions,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// The `data` list of an envelope (or a bare list); empty for anything
  /// else, including the null body of an empty 204.
  List<dynamic> _maybeListFrom(dynamic data) {
    if (data is Map<String, dynamic>) {
      final Object? list = data['data'];
      return list is List<dynamic> ? list : const <dynamic>[];
    }
    return data is List<dynamic> ? data : const <dynamic>[];
  }

  List<dynamic> _listFrom(dynamic data) => data is Map<String, dynamic>
      ? ((data['data'] as List<dynamic>?) ?? const <dynamic>[])
      : (data as List<dynamic>);
}
