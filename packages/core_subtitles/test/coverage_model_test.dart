import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

SubtitleTrack sub(String code2, String? path, {bool hi = false}) =>
    SubtitleTrack(
      code2: code2,
      name: code2.toUpperCase(),
      code3: code2,
      path: path,
      hi: hi,
    );

SubtitleTrack miss(String code2, {bool forced = false, bool hi = false}) =>
    SubtitleTrack(
      code2: code2,
      name: code2.toUpperCase(),
      code3: code2,
      forced: forced,
      hi: hi,
    );

CoverageEpisode ep(
  int season,
  int episode,
  List<SubtitleTrack> subtitles,
  List<SubtitleTrack> missing,
) =>
    CoverageEpisode(
      episodeId: season * 100 + episode,
      season: season,
      episode: episode,
      subtitles: subtitles,
      missing: missing,
    );

const missing = CoverageCell.missing;
const present = CoverageCell.present;
const embedded = CoverageCell.embedded;
const unwanted = CoverageCell.unwanted;

void main() {
  group('buildCoverageGrid', () {
    final episodes = [
      ep(1, 2, [sub('en', '/a.en.srt')], [miss('de')]),
      ep(1, 1, [sub('en', null), sub('de', '/a.de.srt')], []),
      ep(2, 1, [], [miss('en'), miss('de')]),
    ];

    test("uses the profile's languages as columns", () {
      final grid = buildCoverageGrid(
        episodes,
        profileColumns: [
          CoverageLanguage.of('en'),
          CoverageLanguage.of('de'),
          CoverageLanguage.of('fr'),
        ],
      );
      expect(grid.languages.map((l) => l.code2).toList(), ['en', 'de', 'fr']);
      expect(grid.seasons.map((s) => s.season).toList(), [2, 1]);
      final s1 = grid.seasons[1];
      expect(s1.episodes.map((e) => e.cells).toList(), [
        [embedded, present, unwanted],
        [present, missing, unwanted],
      ]);
      expect(s1.gaps, 1);
      expect(grid.seasons[0].gaps, 1);
    });

    test('keeps plain and HI columns of one language apart', () {
      final grid = buildCoverageGrid([
        ep(1, 1, [sub('en', '/a.en.srt')], [miss('en', hi: true)]),
        ep(1, 2, [sub('en', '/b.en.hi.srt', hi: true)], []),
      ]);
      expect(grid.languages.map((l) => l.key).toList(), ['en|', 'en|h']);
      expect(grid.seasons[0].episodes.map((e) => e.cells).toList(), [
        [present, missing],
        [present, present],
      ]);
    });

    test('falls back to the languages episodes have without a profile', () {
      expect(
        buildCoverageGrid(episodes).languages.map((l) => l.code2).toList(),
        ['de', 'en'],
      );
    });

    // Atrium extra.
    test('sorts episodes ascending within a season', () {
      final grid = buildCoverageGrid(episodes);
      expect(
        grid.seasons[1].episodes.map((e) => e.episodeId).toList(),
        [101, 102],
      );
    });
  });

  group('seasonMissingEpisodes / seasonGapCount', () {
    final episodes = [
      ep(1, 1, [], [miss('de')]),
      ep(1, 2, [], []),
      ep(2, 1, [], [miss('en')]),
    ];

    test("lists only that season's episodes with missing languages", () {
      final targets = seasonMissingEpisodes(episodes, 1);
      expect(targets.map((t) => t.episode).toList(), [1]);
      expect(targets.first.missing.map((l) => l.code2).toList(), ['de']);
      expect(seasonGapCount(episodes, 1), 1);
      expect(seasonGapCount(episodes, 3), 0);
    });
  });

  group('buildEpisodeLanguages', () {
    // Sonarr episode ids match ep()'s season * 100 + episode.
    const sonarr = [
      (id: 101, episodeFileId: 11),
      (id: 102, episodeFileId: 12),
      (id: 103, episodeFileId: 0),
    ];
    const files = {11: 'eng', 12: 'ger'};

    test("keeps the file's audio for episodes Bazarr doesn't list", () {
      final map = buildEpisodeLanguages(
        episodes: sonarr,
        fileAudio: files,
        bazarrEpisodes: [
          ep(1, 1, [sub('en', '/a.srt')], []),
        ],
        originalLanguage: 'English',
      );
      expect(map[101]?.chips?.map((c) => c.code2).toList(), ['en']);
      expect(
        map[102],
        const EpisodeLanguages(
          audio: [AudioTag(code2: 'de', name: 'German')],
        ),
      );
    });

    test("keeps the file's audio without Bazarr's list", () {
      final map = buildEpisodeLanguages(episodes: sonarr, fileAudio: files);
      expect(map.keys.toList(), [101, 102]);
      expect(map[101]?.chips, isNull);
    });

    test('skips episodes without a file, or with nothing to show', () {
      expect(
        buildEpisodeLanguages(episodes: sonarr, fileAudio: const {11: 'und'}),
        isEmpty,
      );
    });

    // Atrium extra.
    test("falls back to Bazarr's audio for an untagged file", () {
      final map = buildEpisodeLanguages(
        episodes: sonarr,
        fileAudio: const {11: 'und'},
        bazarrEpisodes: const [
          CoverageEpisode(
            episodeId: 101,
            season: 1,
            episode: 1,
            audio: [Language(code2: 'fr', code3: 'fre', name: 'French')],
          ),
        ],
        originalLanguage: 'French',
      );
      expect(map[101]?.audio, [
        const AudioTag(code2: 'fr', name: 'French', original: true),
      ]);
      expect(map[101]?.chips, isEmpty);
    });
  });
}
