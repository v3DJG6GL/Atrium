import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/service_bazarr.dart';

import 'support/fake_http_client_adapter.dart';

const RawBody emptyJson204 = RawBody('', contentType: Headers.jsonContentType);

void main() {
  late FakeHttpClientAdapter adapter;

  BazarrApi apiWith(ResponseFactory factory) {
    adapter = FakeHttpClientAdapter(factory);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://bazarr.test/'));
    dio.httpClientAdapter = adapter;
    return BazarrApi(dio);
  }

  BazarrApi noContent() =>
      apiWith((RequestOptions _) => (status: 204, data: emptyJson204));

  RequestOptions single() => adapter.requests.single;

  String decodedQuery(RequestOptions r) =>
      Uri.decodeQueryComponent(r.uri.query);

  const SubtitleTarget movie = MovieTarget(12);
  const SubtitleTarget episode = EpisodeTarget(3, 99);
  const BazarrSubtitle external = BazarrSubtitle(
    code2: 'de',
    code3: 'ger',
    forced: true,
    path: '/movies/Film/Film.de.forced.srt',
    id: 501,
  );

  group('items', () {
    test('getMovie sends the literal radarrid[] key and returns the first',
        () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (
          status: 200,
          data: <String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{'radarrId': 7, 'title': 'Film'},
            ],
            'total': 1,
          },
        ),
      );
      final BazarrMovie? m = await api.getMovie(7);
      expect(m?.title, 'Film');
      expect(single().method, 'GET');
      expect(single().path, 'api/movies');
      expect(single().queryParameters, <String, dynamic>{'radarrid[]': 7});
      expect(decodedQuery(single()), 'radarrid[]=7');
    });

    test('getMovie returns null for an unknown movie or an empty body',
        () async {
      BazarrApi api = apiWith(
        (RequestOptions _) =>
            (status: 200, data: <String, dynamic>{'data': <dynamic>[]}),
      );
      expect(await api.getMovie(7), isNull);
      api = noContent();
      expect(await api.getMovie(7), isNull);
    });

    test('getSeriesItem sends seriesid[]', () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (
          status: 200,
          data: <String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{'sonarrSeriesId': 3, 'title': 'Show'},
            ],
          },
        ),
      );
      final BazarrSeries? s = await api.getSeriesItem(3);
      expect(s?.title, 'Show');
      expect(single().path, 'api/series');
      expect(decodedQuery(single()), 'seriesid[]=3');
    });

    test('getEpisodesByIds repeats episodeid[]', () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (
          status: 200,
          data: <String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{'sonarrEpisodeId': 1},
              <String, dynamic>{'sonarrEpisodeId': 2},
            ],
          },
        ),
      );
      final List<BazarrEpisode> eps = await api.getEpisodesByIds(<int>[1, 2]);
      expect(eps, hasLength(2));
      expect(single().path, 'api/episodes');
      expect(decodedQuery(single()), 'episodeid[]=1&episodeid[]=2');
    });

    test('getEnabledLanguages keeps only enabled ones', () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (
          status: 200,
          data: <dynamic>[
            <String, dynamic>{
              'name': 'English',
              'code2': 'en',
              'enabled': true,
            },
            <String, dynamic>{
              'name': 'French',
              'code2': 'fr',
              'enabled': false,
            },
          ],
        ),
      );
      final List<BazarrLanguage> langs = await api.getEnabledLanguages();
      expect(langs.map((BazarrLanguage l) => l.code2), <String>['en']);
      expect(single().path, 'api/system/languages');
    });
  });

  group('getActiveJobIds', () {
    test('merges pending and running job ids', () async {
      final BazarrApi api = apiWith((RequestOptions o) {
        final bool pending = o.queryParameters['status'] == 'pending';
        return (
          status: 200,
          data: <String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{
                'job_id': pending ? 4 : 9,
                'job_name': 'x',
                'status': o.queryParameters['status'],
              },
            ],
          },
        );
      });
      expect(await api.getActiveJobIds(), unorderedEquals(<int>[4, 9]));
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.map((RequestOptions r) => r.path).toSet(),
        <String>{'api/system/jobs'},
      );
      expect(
        adapter.requests.map((RequestOptions r) => r.queryParameters['status']),
        unorderedEquals(<String>['pending', 'running']),
      );
    });

    test('an empty queue is an empty list', () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) =>
            (status: 200, data: <String, dynamic>{'data': <dynamic>[]}),
      );
      expect(await api.getActiveJobIds(), isEmpty);
    });

    test('is null on 404 and 405 (no job queue)', () async {
      BazarrApi api = apiWith(
        (RequestOptions _) =>
            (status: 404, data: <String, dynamic>{'message': 'Not found'}),
      );
      expect(await api.getActiveJobIds(), isNull);
      api = apiWith((RequestOptions _) => (status: 405, data: null));
      expect(await api.getActiveJobIds(), isNull);
    });

    test('is null when an old Bazarr answers its HTML web UI', () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (
          status: 200,
          data: const RawBody(
            '<!DOCTYPE html><html><body>Bazarr</body></html>',
            contentType: 'text/html; charset=utf-8',
          ),
        ),
      );
      expect(await api.getActiveJobIds(), isNull);
    });

    test('throws a NetworkException on other errors', () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) =>
            (status: 500, data: <String, dynamic>{'message': 'boom'}),
      );
      await expectLater(
        api.getActiveJobIds(),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('actions', () {
    test('searchLanguage PATCHes query params with True/False', () async {
      final BazarrApi api = noContent();
      await api.searchLanguage(
        episode,
        const LanguageChoice(code2: 'fr', hi: true),
      );
      final RequestOptions r = single();
      expect(r.method, 'PATCH');
      expect(r.path, 'api/episodes/subtitles');
      expect(r.queryParameters, <String, dynamic>{
        'seriesid': 3,
        'episodeid': 99,
        'language': 'fr',
        'forced': 'False',
        'hi': 'True',
      });
      expect(r.data, isNull);
      expect(r.receiveTimeout, const Duration(seconds: 90));
    });

    test('an empty 204 labelled JSON is a success', () async {
      final BazarrApi api = noContent();
      await expectLater(
        api.searchLanguage(movie, const LanguageChoice(code2: 'en')),
        completes,
      );
      expect(single().path, 'api/movies/subtitles');
    });

    test('searchMissingMovie and searchMissingSeries send a JSON body',
        () async {
      BazarrApi api = noContent();
      await api.searchMissingMovie(42);
      RequestOptions r = single();
      expect(r.method, 'PATCH');
      expect(r.path, 'api/movies');
      expect(r.data, <String, Object>{
        'radarrid': 42,
        'action': 'search-missing',
      });
      expect(r.queryParameters, isEmpty);
      expect(r.contentType, startsWith(Headers.jsonContentType));
      expect(r.receiveTimeout, const Duration(seconds: 90));

      api = noContent();
      await api.searchMissingSeries(17);
      r = single();
      expect(r.path, 'api/series');
      expect(r.data, <String, Object>{
        'seriesid': 17,
        'action': 'search-missing',
      });
    });

    test('searchWanted sends search-wanted to movies or series', () async {
      BazarrApi api = noContent();
      await api.searchWanted(movies: true);
      expect(single().path, 'api/movies');
      expect(single().method, 'PATCH');
      expect(single().data, <String, Object>{'action': 'search-wanted'});

      api = noContent();
      await api.searchWanted(movies: false);
      expect(single().path, 'api/series');
    });

    test('uploadSubtitle posts multipart with lowercase flags and a file',
        () async {
      final BazarrApi api = noContent();
      await api.uploadSubtitle(
        movie,
        const LanguageChoice(code2: 'de', forced: true),
        MultipartFile.fromString(
          '1\n00:00:01,000 --> 00:00:02,000\nHi\n',
          filename: 'Film.de.forced.srt',
        ),
      );
      final RequestOptions r = single();
      expect(r.method, 'POST');
      expect(r.path, 'api/movies/subtitles');
      expect(r.queryParameters, isEmpty);
      expect(r.receiveTimeout, const Duration(seconds: 90));
      final FormData form = r.data as FormData;
      expect(
        Map<String, String>.fromEntries(form.fields),
        <String, String>{
          'radarrid': '12',
          'language': 'de',
          'forced': 'true',
          'hi': 'false',
        },
      );
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'Film.de.forced.srt');
    });

    test('deleteSubtitle sends a DELETE with query params', () async {
      final BazarrApi api = noContent();
      await api.deleteSubtitle(episode, external);
      final RequestOptions r = single();
      expect(r.method, 'DELETE');
      expect(r.path, 'api/episodes/subtitles');
      expect(r.queryParameters, <String, dynamic>{
        'seriesid': 3,
        'episodeid': 99,
        'language': 'de',
        'forced': 'True',
        'hi': 'False',
        'path': '/movies/Film/Film.de.forced.srt',
      });
    });

    test('the old delete methods delegate', () async {
      final BazarrApi api = noContent();
      await api.deleteMovieSubtitle(radarrId: 12, subtitle: external);
      expect(single().method, 'DELETE');
      expect(single().path, 'api/movies/subtitles');
      expect(single().queryParameters['radarrid'], 12);
    });

    test('runSubtitleTool PATCHes api/subtitles with query params', () async {
      final BazarrApi api = noContent();
      await api.runSubtitleTool(
        movie,
        external,
        const SubtitleToolAction.shift(1500),
      );
      final RequestOptions r = single();
      expect(r.method, 'PATCH');
      expect(r.path, 'api/subtitles');
      expect(r.queryParameters, <String, dynamic>{
        'action': 'shift_offset(h=0,m=0,s=1,ms=500)',
        'language': 'de',
        'type': 'movie',
        'id': 12,
        'forced': 'True',
        'hi': 'False',
        'path': '/movies/Film/Film.de.forced.srt',
      });
      expect(r.receiveTimeout, const Duration(seconds: 90));
    });

    test('setLanguageProfile sends profileid, empty for none', () async {
      BazarrApi api = noContent();
      await api.setLanguageProfile(radarrId: 12, profileId: 3);
      RequestOptions r = single();
      expect(r.method, 'POST');
      expect(r.path, 'api/movies');
      expect(r.queryParameters, <String, dynamic>{
        'radarrid': 12,
        'profileid': '3',
      });

      api = noContent();
      await api.setLanguageProfile(seriesId: 17);
      r = single();
      expect(r.path, 'api/series');
      expect(r.queryParameters, <String, dynamic>{
        'seriesid': 17,
        'profileid': '',
      });
      expect(decodedQuery(r), contains('profileid='));
      expect(decodedQuery(r), isNot(contains('none')));
    });

    test('blacklistSubtitle POSTs query params', () async {
      final BazarrApi api = noContent();
      await api.blacklistSubtitle(
        episode,
        provider: 'opensubtitlescom',
        subsId: 'abc',
        language: 'en',
        subtitlesPath: '/tv/Show/S01E01.en.srt',
      );
      final RequestOptions r = single();
      expect(r.method, 'POST');
      expect(r.path, 'api/episodes/blacklist');
      expect(r.queryParameters, <String, dynamic>{
        'seriesid': 3,
        'episodeid': 99,
        'provider': 'opensubtitlescom',
        'subs_id': 'abc',
        'language': 'en',
        'subtitles_path': '/tv/Show/S01E01.en.srt',
      });
    });
  });

  group('manual search', () {
    test('episodes take only episodeid, with a long timeout and cancel token',
        () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (
          status: 200,
          data: <String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{
                'provider': 'opensubtitlescom',
                'score': 91.5,
                'subtitle': 'token',
              },
            ],
          },
        ),
      );
      final CancelToken token = CancelToken();
      final List<BazarrSubtitleSearchResult> results =
          await api.manualSearch(episode, cancelToken: token);
      expect(results.single.score, 91.5);
      final RequestOptions r = single();
      expect(r.method, 'GET');
      expect(r.path, 'api/providers/episodes');
      expect(r.queryParameters, <String, dynamic>{'episodeid': 99});
      expect(r.receiveTimeout, const Duration(seconds: 180));
      expect(r.cancelToken, same(token));
    });

    test('movies take radarrid', () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (status: 200, data: <dynamic>[]),
      );
      expect(await api.manualSearch(movie), isEmpty);
      expect(single().path, 'api/providers/movies');
      expect(single().queryParameters, <String, dynamic>{'radarrid': 12});
    });

    test('downloadResult sends a JSON body and no query', () async {
      final BazarrApi api = noContent();
      await api.downloadResult(
        episode,
        const BazarrSubtitleSearchResult(
          provider: 'opensubtitlescom',
          subtitle: 'opaque-token',
          hearingImpaired: 'True',
        ),
      );
      final RequestOptions r = single();
      expect(r.method, 'POST');
      expect(r.path, 'api/providers/episodes');
      expect(r.queryParameters, isEmpty);
      expect(r.contentType, startsWith(Headers.jsonContentType));
      expect(r.data, <String, Object>{
        'seriesid': 3,
        'episodeid': 99,
        'provider': 'opensubtitlescom',
        'subtitle': 'opaque-token',
        'hi': 'True',
        'forced': 'False',
        'original_format': 'False',
      });
      expect(r.receiveTimeout, const Duration(seconds: 90));
    });

    test('the old download method delegates to the JSON body', () async {
      final BazarrApi api = noContent();
      await api.downloadMovieSubtitle(
        radarrId: 12,
        result: const BazarrSubtitleSearchResult(provider: 'p', subtitle: 's'),
      );
      expect(single().path, 'api/providers/movies');
      expect(single().queryParameters, isEmpty);
      expect((single().data as Map<String, Object>)['radarrid'], 12);
    });
  });

  group('history', () {
    test('getHistoryPage sends start/length and reads data and total',
        () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (
          status: 200,
          data: <String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{'action': 1, 'radarrId': 7, 'subs_id': 'a'},
            ],
            'total': 120,
          },
        ),
      );
      final BazarrHistoryPage page =
          await api.getHistoryPage(movies: true, start: 50, length: 25);
      expect(page.total, 120);
      expect(page.items.single.radarrId, 7);
      expect(page.items.single.isMovie, isTrue);
      expect(single().path, 'api/movies/history');
      expect(single().queryParameters, <String, dynamic>{
        'start': 50,
        'length': 25,
      });
    });

    test('episode history defaults to the first 50', () async {
      final BazarrApi api = apiWith(
        (RequestOptions _) => (
          status: 200,
          data: <String, dynamic>{'data': <dynamic>[], 'total': 0},
        ),
      );
      final List<BazarrHistoryItem> items = await api.getEpisodeHistory();
      expect(items, isEmpty);
      expect(single().path, 'api/episodes/history');
      expect(single().queryParameters, <String, dynamic>{
        'start': 0,
        'length': 50,
      });
    });
  });
}
