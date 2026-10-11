import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

SubtitleTrack sub(
  String code2,
  String? path, {
  bool forced = false,
  bool hi = false,
  int? embeddedTrackId,
}) =>
    SubtitleTrack(
      code2: code2,
      name: code2.toUpperCase(),
      code3: code2,
      path: path,
      forced: forced,
      hi: hi,
      embeddedTrackId: embeddedTrackId,
    );

SubtitleTrack miss(String code2, {bool forced = false, bool hi = false}) =>
    SubtitleTrack(
      code2: code2,
      name: code2.toUpperCase(),
      code3: code2,
      forced: forced,
      hi: hi,
    );

void main() {
  group('buildSubtitleRows', () {
    final rows = buildSubtitleRows(
      subtitles: [
        sub('en', null, embeddedTrackId: 2),
        sub('de', '/m/Film.de.srt'),
        sub('de', '/m/Film.de.forced.srt', forced: true),
      ],
      missing: [miss('fr')],
    );

    test('orders missing, then files, then embedded', () {
      expect(rows.map((r) => '${r.code2}:${r.state.name}').toList(), [
        'fr:missing',
        'de:present',
        'de:present',
        'en:embedded',
      ]);
    });

    test('gives every row a distinct, stable key', () {
      expect(rows.map((r) => r.key).toSet().length, rows.length);
      expect(
        rows.firstWhere((r) => r.forced).key,
        'de|f|/m/Film.de.forced.srt',
      );
    });

    test(
        'keeps keys distinct for embedded tracks without ids '
        '(before Bazarr 1.6)', () {
      final keys = buildSubtitleRows(
        subtitles: [sub('en', null), sub('en', null)],
        missing: const [],
      ).map((r) => r.key).toList();
      expect(keys, ['en||track', 'en||track#1']);
    });

    test('handles a missing or null list', () {
      expect(buildSubtitleRows(), isEmpty);
    });

    // Atrium extras.
    test('keys embedded tracks by id and missing rows by flags', () {
      final keys = buildSubtitleRows(
        subtitles: [
          sub('en', null, embeddedTrackId: 3),
          const SubtitleTrack(code2: 'de', name: 'German', id: 7),
        ],
        missing: [miss('fr', forced: true, hi: true)],
      ).map((r) => r.key).toList();
      expect(keys, ['fr|fh|missing', 'en||track3', 'de||track7']);
    });

    test('an empty path is an embedded track', () {
      final rows = buildSubtitleRows(subtitles: [sub('en', '')]);
      expect(rows.single.state, SubtitleState.embedded);
    });

    test('sorts each group by name, ignoring case', () {
      final rows = buildSubtitleRows(
        missing: const [
          SubtitleTrack(code2: 'fr', name: 'french'),
          SubtitleTrack(code2: 'de', name: 'German'),
          SubtitleTrack(code2: 'en', name: 'English'),
        ],
      );
      expect(rows.map((r) => r.code2).toList(), ['en', 'fr', 'de']);
    });
  });

  group('buildSubtitleChips / subtitleCoverage', () {
    test('keeps one chip per language and flags, preferring the best state',
        () {
      final chips = buildSubtitleChips(
        buildSubtitleRows(
          subtitles: [
            sub('en', null),
            sub('en', '/m/f.en.srt'),
            sub('de', '/m/f.de.srt', forced: true),
          ],
          missing: [miss('fr'), miss('de')],
        ),
      );
      expect(
        chips
            .map((c) => '${c.code2}${c.forced ? 'F' : ''}:${c.state.name}')
            .toList(),
        ['deF:present', 'en:present', 'de:missing', 'fr:missing'],
      );
      expect(subtitleCoverage(chips), (have: 2, total: 4));
    });
  });

  group('audio tags', () {
    test('dedupes arr audio tracks and marks the original language', () {
      expect(audioTagsFromArr('eng/eng/ger', originalLanguage: 'English'), [
        const AudioTag(code2: 'en', name: 'English', original: true),
        const AudioTag(code2: 'de', name: 'German'),
      ]);
    });

    test("accepts Bazarr's audio_language list", () {
      expect(
        audioTagsFromLanguages(
          const [
            Language(code2: 'fr', code3: 'fre', name: 'French'),
            Language(code2: 'fr', code3: 'fre', name: 'French'),
          ],
          originalLanguage: 'French',
        ),
        [const AudioTag(code2: 'fr', name: 'French', original: true)],
      );
    });

    test(
        'marks a base-language track original for a regional original '
        'language', () {
      expect(
        audioTagsFromArr('por/eng', originalLanguage: 'Portuguese (Brazil)'),
        [
          const AudioTag(code2: 'pt', name: 'Portuguese', original: true),
          const AudioTag(code2: 'en', name: 'English'),
        ],
      );
    });

    test('marks a Bokmål track original for a Norwegian production', () {
      expect(
        audioTagsFromArr('nob', originalLanguage: 'Norwegian').first.original,
        isTrue,
      );
    });

    test("prefers an exact original over a regional variant's base", () {
      expect(
        audioTagsFromLanguages(
          const [
            Language(code2: 'es', code3: 'spa', name: 'Spanish'),
            Language(code2: 'ea', code3: 'spl', name: 'Spanish (Latino)'),
          ],
          originalLanguage: 'Spanish',
        ).map((t) => t.original).toList(),
        [true, false],
      );
    });

    test("keeps a Bazarr audio language the code table doesn't know", () {
      expect(
        audioTagsFromLanguages(
          const [Language(code2: 'ps', code3: 'pus', name: 'Pashto')],
        ),
        [const AudioTag(code2: 'ps', name: 'Pashto')],
      );
    });

    test('is empty without audio info', () {
      expect(audioTagsFromArr(null), isEmpty);
    });
  });

  group('mediaAudioTags', () {
    const bazarr = [Language(code2: 'fr', code3: 'fre', name: 'French')];

    test("prefers the file's audio languages", () {
      expect(mediaAudioTags('eng/ger', bazarr, originalLanguage: 'English'), [
        const AudioTag(code2: 'en', name: 'English', original: true),
        const AudioTag(code2: 'de', name: 'German'),
      ]);
    });

    test('falls back to Bazarr when the file has only untagged tracks', () {
      expect(mediaAudioTags('und/und', bazarr, originalLanguage: 'French'), [
        const AudioTag(code2: 'fr', name: 'French', original: true),
      ]);
    });

    test('falls back to Bazarr without file audio info', () {
      expect(
        mediaAudioTags(null, bazarr).map((t) => t.code2).toList(),
        ['fr'],
      );
    });

    test('is empty with neither', () {
      expect(mediaAudioTags(null, null), isEmpty);
      expect(mediaAudioTags('', null), isEmpty);
    });
  });

  group('fitChips', () {
    // chip 30, gap 4, "+N" 30
    int fit(int count, double available) => fitChips(
          count: count,
          available: available,
          chipWidth: 30,
          gap: 4,
          plusWidth: 30,
        );

    test('shows everything that fits', () {
      expect(fit(3, 98), 3);
    });

    test("leaves room for the +N chip when it doesn't", () {
      // 4 chips need 132; with +N: n*(34) + 30 <= 120 → n = 2
      expect(fit(4, 120), 2);
    });

    test(
        "shows every chip on an exact fit instead of a +1 in the last one's "
        'place', () {
      expect(fit(2, 64), 2);
      expect(fit(2, 63), 0);
    });

    test('handles no room and no chips', () {
      expect(fit(5, 20), 0);
      expect(fit(0, 200), 0);
    });
  });
}
