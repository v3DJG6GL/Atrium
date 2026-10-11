import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/service_bazarr.dart';

void main() {
  group('BazarrSubtitle', () {
    test('parses id, embedded track id and file size', () {
      final BazarrSubtitle sub = BazarrSubtitle.fromJson(<String, dynamic>{
        'name': 'English',
        'code2': 'en',
        'code3': 'eng',
        'path': null,
        'forced': false,
        'hi': true,
        'id': 502,
        'embedded_track_id': 3,
        'file_size': 12345,
      });
      expect(sub.id, 502);
      expect(sub.embeddedTrackId, 3);
      expect(sub.fileSize, 12345);
      expect(sub.path, isNull);
    });

    test('leaves the new fields null when absent', () {
      final BazarrSubtitle sub =
          BazarrSubtitle.fromJson(<String, dynamic>{'code2': 'de'});
      expect(sub.id, isNull);
      expect(sub.embeddedTrackId, isNull);
      expect(sub.fileSize, isNull);
    });
  });

  const Map<String, dynamic> audio = <String, dynamic>{
    'name': 'Japanese',
    'code2': 'ja',
    'code3': 'jpn',
  };

  test('BazarrMovie parses audio languages without an enabled flag', () {
    final BazarrMovie movie = BazarrMovie.fromJson(<String, dynamic>{
      'radarrId': 7,
      'title': 'Film',
      'year': '2023',
      'audio_language': <dynamic>[audio],
      'path': '/movies/Film (2023)/Film.mkv',
      'sceneName': 'Film.2023.1080p',
    });
    expect(movie.audioLanguage, hasLength(1));
    expect(movie.audioLanguage.single.code2, 'ja');
    expect(movie.audioLanguage.single.enabled, isFalse);
    expect(movie.path, '/movies/Film (2023)/Film.mkv');
    expect(movie.sceneName, 'Film.2023.1080p');
    expect(movie.year, 2023);
  });

  test('BazarrEpisode parses audio, path and scene name', () {
    final BazarrEpisode episode = BazarrEpisode.fromJson(<String, dynamic>{
      'sonarrEpisodeId': 99,
      'sonarrSeriesId': 3,
      'audio_language': <dynamic>[audio],
      'path': '/tv/Show/S01E01.mkv',
      'sceneName': null,
    });
    expect(episode.audioLanguage.single.name, 'Japanese');
    expect(episode.path, '/tv/Show/S01E01.mkv');
    expect(episode.sceneName, isNull);
  });

  test('BazarrSeries parses audio, path and ended; audio defaults empty', () {
    final BazarrSeries series = BazarrSeries.fromJson(<String, dynamic>{
      'sonarrSeriesId': 3,
      'audio_language': <dynamic>[audio],
      'path': '/tv/Show',
      'ended': true,
    });
    expect(series.audioLanguage.single.code3, 'jpn');
    expect(series.path, '/tv/Show');
    expect(series.ended, isTrue);

    final BazarrSeries bare =
        BazarrSeries.fromJson(<String, dynamic>{'sonarrSeriesId': 4});
    expect(bare.audioLanguage, isEmpty);
    expect(bare.ended, isNull);
  });

  group('BazarrProfileItem', () {
    test('omits audio_only_include from toJson when unknown', () {
      final BazarrProfileItem item = BazarrProfileItem.fromJson(
        <String, dynamic>{
          'id': 1,
          'language': 'en',
          'hi': 'False',
          'forced': 'False',
          'audio_exclude': 'False',
        },
      );
      expect(item.audioOnlyInclude, isNull);
      expect(item.toJson(), <String, dynamic>{
        'id': 1,
        'language': 'en',
        'hi': 'False',
        'forced': 'False',
        'audio_exclude': 'False',
      });
    });

    test('round-trips audio_only_include when present', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'id': 2,
        'language': 'fr',
        'hi': 'True',
        'forced': 'False',
        'audio_exclude': 'False',
        'audio_only_include': 'True',
      };
      final BazarrProfileItem item = BazarrProfileItem.fromJson(json);
      expect(item.audioOnlyInclude, 'True');
      expect(item.toJson(), json);
    });

    test('a profile encodes its items without a null audio_only_include', () {
      const BazarrLanguageProfile profile = BazarrLanguageProfile(
        profileId: 1,
        name: 'Default',
        items: <BazarrProfileItem>[BazarrProfileItem(id: 1, language: 'en')],
      );
      final Map<String, dynamic> decoded =
          jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>;
      final Map<String, dynamic> item =
          (decoded['items'] as List<dynamic>).single as Map<String, dynamic>;
      expect(item.containsKey('audio_only_include'), isFalse);
      expect(item['language'], 'en');
    });
  });

  test('BazarrHistoryItem parses ids, paths, matches and upgradable', () {
    final BazarrHistoryItem item = BazarrHistoryItem.fromJson(
      <String, dynamic>{
        'action': 2,
        'title': 'Film',
        'radarrId': 7,
        'sonarrSeriesId': null,
        'subs_id': 'abc123',
        'subtitles_path': '/movies/Film.en.srt',
        'matches': <String>['title', 'year'],
        'dont_matches': <String>['hash'],
        'upgradable': true,
        'provider': 'opensubtitlescom',
        'score': '87.5%',
      },
    );
    expect(item.action, 2);
    expect(item.radarrId, 7);
    expect(item.sonarrSeriesId, isNull);
    expect(item.sonarrEpisodeId, isNull);
    expect(item.subsId, 'abc123');
    expect(item.subtitlesPath, '/movies/Film.en.srt');
    expect(item.matches, <String>['title', 'year']);
    expect(item.dontMatches, <String>['hash']);
    expect(item.upgradable, isTrue);

    final BazarrHistoryItem episode = BazarrHistoryItem.fromJson(
      <String, dynamic>{'sonarrSeriesId': 3, 'sonarrEpisodeId': 99},
    );
    expect(episode.sonarrSeriesId, 3);
    expect(episode.sonarrEpisodeId, 99);
    expect(episode.matches, isEmpty);
    expect(episode.dontMatches, isEmpty);
    expect(episode.upgradable, isFalse);
  });

  test('BazarrSubtitleSearchResult parses scores as numbers and matches', () {
    final BazarrSubtitleSearchResult result =
        BazarrSubtitleSearchResult.fromJson(<String, dynamic>{
      'provider': 'opensubtitlescom',
      'score': 92.5,
      'orig_score': 360,
      'score_without_hash': 88,
      'matches': <String>['title'],
      'dont_matches': <String>['release_group'],
      'hearing_impaired': 'True',
      'forced': 'False',
      'original_format': 'False',
      'subtitle': 'token',
    });
    expect(result.score, 92.5);
    expect(result.origScore, 360);
    expect(result.scoreWithoutHash, 88);
    expect(result.matches, <String>['title']);
    expect(result.dontMatches, <String>['release_group']);

    final BazarrSubtitleSearchResult integer =
        BazarrSubtitleSearchResult.fromJson(<String, dynamic>{'score': 70});
    expect(integer.score, 70);
    expect(integer.origScore, isNull);
  });

  test('BazarrJob parses a queue entry', () {
    final BazarrJob job = BazarrJob.fromJson(<String, dynamic>{
      'job_id': 12,
      'job_name': 'Searching subtitles',
      'status': 'running',
      'last_run_time': '',
      'is_progress': true,
      'progress_value': 3,
      'progress_max': 10,
      'progress_message': 'Film',
    });
    expect(job.jobId, 12);
    expect(job.jobName, 'Searching subtitles');
    expect(job.status, 'running');
    expect(job.progressValue, 3);
    expect(job.progressMax, 10);
    expect(job.progressMessage, 'Film');
  });
}
