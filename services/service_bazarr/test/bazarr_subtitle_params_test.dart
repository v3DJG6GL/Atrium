import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/service_bazarr.dart';

void main() {
  const SubtitleTarget movie = MovieTarget(12);
  const SubtitleTarget episode = EpisodeTarget(3, 99);

  const BazarrSubtitle external = BazarrSubtitle(
    name: 'German',
    code2: 'de',
    code3: 'ger',
    path: '/movies/Film (2023)/Film.de.forced.srt',
    forced: true,
    id: 501,
  );
  const BazarrSubtitle embedded = BazarrSubtitle(
    name: 'English',
    code2: 'en',
    code3: 'eng',
    hi: true,
    embeddedTrackId: 3,
    id: 502,
  );

  group('SubtitleTarget', () {
    test('keys, type names and media ids', () {
      expect(movie.key, 'm12');
      expect(movie.typeName, 'movie');
      expect(movie.mediaId, 12);
      expect(episode.key, 'e99');
      expect(episode.typeName, 'episode');
      expect(episode.mediaId, 99);
    });

    test('compares by value', () {
      expect(const MovieTarget(12) == movie, isTrue);
      expect(const MovieTarget(12).hashCode, movie.hashCode);
      expect(const EpisodeTarget(3, 99) == episode, isTrue);
      expect(const EpisodeTarget(4, 99) == episode, isFalse);
      expect(const MovieTarget(99) == const EpisodeTarget(3, 99), isFalse);
    });

    test('target and manual-search params', () {
      expect(targetParams(movie), <String, Object>{'radarrid': 12});
      expect(
        targetParams(episode),
        <String, Object>{'seriesid': 3, 'episodeid': 99},
      );
      expect(manualSearchParams(episode), <String, Object>{'episodeid': 99});
      expect(manualSearchParams(movie), <String, Object>{'radarrid': 12});
    });
  });

  group('boolean encoding per route', () {
    test('search sends True/False', () {
      expect(
        searchParams(
          episode,
          const LanguageChoice(code2: 'fr', hi: true),
        ),
        <String, Object>{
          'seriesid': 3,
          'episodeid': 99,
          'language': 'fr',
          'forced': 'False',
          'hi': 'True',
        },
      );
    });

    test('upload sends lowercase true/false', () {
      expect(
        uploadFields(movie, const LanguageChoice(code2: 'de', forced: true)),
        <String, Object>{
          'radarrid': 12,
          'language': 'de',
          'forced': 'true',
          'hi': 'false',
        },
      );
    });

    test('tools send True/False', () {
      final Map<String, Object> p =
          toolParams(movie, external, const SubtitleToolAction.sync());
      expect(p['forced'], 'True');
      expect(p['hi'], 'False');
    });

    test("download echoes the search result's own strings", () {
      expect(
        downloadResultParams(
          movie,
          const BazarrSubtitleSearchResult(
            provider: 'opensubtitlescom',
            subtitle: 'opaque-token',
            hearingImpaired: 'True',
          ),
        ),
        <String, Object>{
          'radarrid': 12,
          'provider': 'opensubtitlescom',
          'subtitle': 'opaque-token',
          'hi': 'True',
          'forced': 'False',
          'original_format': 'False',
        },
      );
    });

    test('boolCap and boolLower', () {
      expect(boolCap(true), 'True');
      expect(boolCap(false), 'False');
      expect(boolLower(true), 'true');
      expect(boolLower(false), 'false');
    });
  });

  group('toolParams', () {
    test('addresses an external file by its exact path', () {
      expect(
        toolParams(
          episode,
          external,
          const SubtitleToolAction.mod('remove_HI'),
        ),
        <String, Object>{
          'action': 'remove_HI',
          'language': 'de',
          'type': 'episode',
          'id': 99,
          'forced': 'True',
          'hi': 'False',
          'path': '/movies/Film (2023)/Film.de.forced.srt',
        },
      );
    });

    test('addresses an embedded track by its subtitle id', () {
      final Map<String, Object> p =
          toolParams(movie, embedded, const SubtitleToolAction.extract());
      expect(p['action'], 'extract');
      expect(p['type'], 'movie');
      expect(p['id'], 12);
      expect(p['subtitles_id'], 502);
      expect(p.containsKey('path'), isFalse);
    });

    test('an embedded track without an id gets neither path nor id', () {
      final Map<String, Object> p = toolParams(
        movie,
        const BazarrSubtitle(code2: 'en', path: ''),
        const SubtitleToolAction.sync(),
      );
      expect(p.containsKey('path'), isFalse);
      expect(p.containsKey('subtitles_id'), isFalse);
    });

    test('sends the target language for translate', () {
      final Map<String, Object> p = toolParams(
        movie,
        external,
        const SubtitleToolAction.translate('fr'),
      );
      expect(p['action'], 'translate');
      expect(p['language'], 'fr');
    });

    test('shift and frame-rate actions carry their mod strings', () {
      expect(
        toolParams(
          movie,
          external,
          const SubtitleToolAction.shift(-1500),
        )['action'],
        'shift_offset(h=0,m=0,s=-1,ms=-500)',
      );
      expect(
        toolParams(movie, external, const SubtitleToolAction.fps(23.976, 25))[
            'action'],
        'change_FPS(from=23.976,to=25)',
      );
    });
  });

  group('deleteParams', () {
    test('names the file and its flags', () {
      expect(deleteParams(movie, external), <String, Object>{
        'radarrid': 12,
        'language': 'de',
        'forced': 'True',
        'hi': 'False',
        'path': '/movies/Film (2023)/Film.de.forced.srt',
      });
    });
  });

  group('buildShiftAction', () {
    test("splits an offset into Bazarr's components", () {
      expect(buildShiftAction(1500), 'shift_offset(h=0,m=0,s=1,ms=500)');
      expect(buildShiftAction(3723004), 'shift_offset(h=1,m=2,s=3,ms=4)');
    });

    test('negates every non-zero component for an earlier shift', () {
      expect(buildShiftAction(-61250), 'shift_offset(h=0,m=-1,s=-1,ms=-250)');
    });

    test('encodes zero', () {
      expect(buildShiftAction(0), 'shift_offset(h=0,m=0,s=0,ms=0)');
    });
  });

  group('buildFpsAction', () {
    test('formats the conversion', () {
      expect(buildFpsAction(23.976, 25), 'change_FPS(from=23.976,to=25)');
    });

    test('prints whole numbers without a fraction', () {
      expect(buildFpsAction(24.0, 25.0), 'change_FPS(from=24,to=25)');
      expect(buildFpsAction(29.97, 59.94), 'change_FPS(from=29.97,to=59.94)');
    });

    test('every frame rate formats like the picker shows it', () {
      expect(
        frameRates.map((num r) => buildFpsAction(r, r)).toList(),
        <String>[
          'change_FPS(from=23.976,to=23.976)',
          'change_FPS(from=24,to=24)',
          'change_FPS(from=25,to=25)',
          'change_FPS(from=29.97,to=29.97)',
          'change_FPS(from=30,to=30)',
          'change_FPS(from=50,to=50)',
          'change_FPS(from=59.94,to=59.94)',
          'change_FPS(from=60,to=60)',
        ],
      );
    });
  });

  group('isModifiable / isEmbedded', () {
    test('allows text tools on external .srt only', () {
      expect(isModifiable(external), isTrue);
      expect(isModifiable(external.copyWith(path: '/x/Film.de.SRT')), isTrue);
      expect(isModifiable(external.copyWith(path: '/x/Film.de.ass')), isFalse);
      expect(isModifiable(embedded), isFalse);
    });

    test('detects embedded tracks', () {
      expect(isEmbedded(embedded), isTrue);
      expect(isEmbedded(external), isFalse);
    });
  });

  test('clean-up mods are listed in Bazarr order', () {
    expect(
      cleanupMods.map((CleanupMod m) => m.id).toList(),
      <String>[
        'remove_HI',
        'remove_tags',
        'emoji',
        'OCR_fixes',
        'common',
        'fix_uppercase',
        'reverse_rtl',
      ],
    );
    expect(cleanupMods.first.label, 'Remove hearing-impaired tags');
    expect(cleanupMods.first.description, '[MUSIC], (laughs), speaker names');
  });
}
