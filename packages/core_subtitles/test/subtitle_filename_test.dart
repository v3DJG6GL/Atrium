import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasSubtitleExtension', () {
    test('accepts subtitle formats in any case', () {
      expect(hasSubtitleExtension('Film.de.SRT'), isTrue);
      expect(hasSubtitleExtension('Film.ass'), isTrue);
      expect(hasSubtitleExtension('Film.vtt'), isTrue);
    });

    test('rejects other files', () {
      expect(hasSubtitleExtension('Film.mkv'), isFalse);
      expect(hasSubtitleExtension('notes'), isFalse);
    });
  });

  group('parseSubtitleFilename', () {
    const cases = <(String, ({String? code2, bool forced, bool hi}))>[
      ('Film (2023).de.forced.srt', (code2: 'de', forced: true, hi: false)),
      ('Show.S01E02.en.sdh.srt', (code2: 'en', forced: false, hi: true)),
      ('Show.S01E02.en.hi.srt', (code2: 'en', forced: false, hi: true)),
      ('Film.fre.srt', (code2: 'fr', forced: false, hi: false)),
      ('Film.pt-BR.srt', (code2: 'pb', forced: false, hi: false)),
      ('Film.hi.srt', (code2: 'hi', forced: false, hi: false)),
      ('Film.hi.sdh.srt', (code2: 'hi', forced: false, hi: true)),
      ('Film.hi.hi.srt', (code2: 'hi', forced: false, hi: true)),
      ('Film.srt', (code2: null, forced: false, hi: false)),
      ('Film.2023.1080p.srt', (code2: null, forced: false, hi: false)),
      ('Film.2023.1080p.de.srt', (code2: 'de', forced: false, hi: false)),
      ('Spider-Man.No.Way.Home.srt', (code2: null, forced: false, hi: false)),
      ('Film.Japanese.srt', (code2: 'ja', forced: false, hi: false)),
      ('A.Foreign.Affair.de.srt', (code2: 'de', forced: false, hi: false)),
      ('Say.Hi.to.Me.en.srt', (code2: 'en', forced: false, hi: false)),
      ('Film.forced.de.srt', (code2: 'de', forced: true, hi: false)),
    ];
    for (final (name, expected) in cases) {
      test('reads $name', () {
        expect(parseSubtitleFilename(name), expected);
      });
    }

    // Atrium extras.
    test('a name without an extension has no tags', () {
      expect(
        parseSubtitleFilename('notes'),
        (code2: null, forced: false, hi: false),
      );
    });

    test('lists the extensions Bazarr accepts', () {
      expect(subtitleExtensions, [
        '.srt',
        '.sub',
        '.smi',
        '.txt',
        '.ssa',
        '.ass',
        '.mpl',
        '.vtt',
      ]);
    });
  });
}
