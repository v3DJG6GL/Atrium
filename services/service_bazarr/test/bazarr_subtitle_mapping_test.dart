import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/service_bazarr.dart';

void main() {
  test('a subtitle with a path maps to a file, without one to a track', () {
    const BazarrSubtitle file = BazarrSubtitle(
      name: 'English',
      code2: 'en',
      code3: 'eng',
      hi: true,
      path: '/movies/Film.en.hi.srt',
      fileSize: 18600,
    );
    const BazarrSubtitle track =
        BazarrSubtitle(name: 'French', code2: 'fr', id: 7, embeddedTrackId: 3);

    expect(file.toTrack().isFile, isTrue);
    expect(file.toTrack().hi, isTrue);
    expect(file.toTrack().fileSize, 18600);
    expect(track.toTrack().isFile, isFalse);
    expect(track.toTrack().id, 7);
    expect(track.toTrack().code3, isNull);
  });

  test('a movie maps to rows with missing languages first', () {
    const BazarrMovie movie = BazarrMovie(
      radarrId: 1,
      title: 'Film',
      subtitles: <BazarrSubtitle>[
        BazarrSubtitle(name: 'English', code2: 'en', path: '/m/Film.en.srt'),
      ],
      missingSubtitles: <BazarrSubtitle>[
        BazarrSubtitle(name: 'German', code2: 'de'),
      ],
      audioLanguage: <BazarrLanguage>[
        BazarrLanguage(name: 'Japanese', code2: 'ja', code3: 'jpn'),
      ],
    );

    expect(
      movie.subtitleRows().map((SubtitleRow r) => (r.code2, r.state)),
      <(String, SubtitleState)>[
        ('de', SubtitleState.missing),
        ('en', SubtitleState.present),
      ],
    );
    expect(movie.audioLanguages().single.code2, 'ja');
  });

  test('an episode maps to a coverage input', () {
    const BazarrEpisode episode = BazarrEpisode(
      sonarrEpisodeId: 101,
      sonarrSeriesId: 1,
      season: 2,
      episode: 5,
      missingSubtitles: <BazarrSubtitle>[
        BazarrSubtitle(name: 'German', code2: 'de', hi: true),
      ],
    );

    final CoverageEpisode input = episode.toCoverageEpisode();

    expect(input.episodeId, 101);
    expect(input.season, 2);
    expect(input.episode, 5);
    expect(input.missing.single.hi, isTrue);
  });
}
