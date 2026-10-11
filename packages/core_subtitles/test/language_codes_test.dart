import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeLanguage', () {
    const cases = [
      ('en', 'en'),
      ('eng', 'en'),
      ('English', 'en'),
      ('ger', 'de'),
      ('deu', 'de'),
      ('German', 'de'),
      ('fre', 'fr'),
      ('fra', 'fr'),
      ('dut', 'nl'),
      ('Flemish', 'nl'),
      ('chi', 'zh'),
      ('zho', 'zh'),
      ('cze', 'cs'),
      ('ces', 'cs'),
      ('gre', 'el'),
      ('rum', 'ro'),
      ('slo', 'sk'),
      ('per', 'fa'),
      ('ice', 'is'),
    ];
    for (final (input, code2) in cases) {
      test('reads $input as $code2', () {
        expect(normalizeLanguage(input)?.code2, code2);
      });
    }

    test("knows Bazarr's regional pseudo-codes and the arr names for them", () {
      expect(normalizeLanguage('pb')?.name, 'Portuguese (Brazil)');
      expect(normalizeLanguage('Portuguese (Brazil)')?.code2, 'pb');
      expect(normalizeLanguage('zt')?.code2, 'zt');
      expect(normalizeLanguage('ea')?.code2, 'ea');
    });

    test('maps region tags to variants or their base language', () {
      expect(normalizeLanguage('pt-BR')?.code2, 'pb');
      expect(normalizeLanguage('zh_TW')?.code2, 'zt');
      expect(normalizeLanguage('es-419')?.code2, 'ea');
      expect(normalizeLanguage('en-US')?.code2, 'en');
      expect(normalizeLanguage('de-CH')?.code2, 'de');
    });

    test('returns the ISO 639-2/B code3', () {
      expect(normalizeLanguage('deu')?.code3, 'ger');
    });

    test('is null for empty, unknown and undetermined tags', () {
      expect(normalizeLanguage(''), isNull);
      expect(normalizeLanguage(null), isNull);
      expect(normalizeLanguage('und'), isNull);
      expect(normalizeLanguage('Klingon'), isNull);
    });

    test('ignores case and whitespace', () {
      expect(normalizeLanguage('  ENG ')?.code2, 'en');
    });

    // Atrium extras.
    test('is null for "unknown" and "zxx"', () {
      expect(normalizeLanguage('unknown'), isNull);
      expect(normalizeLanguage('zxx'), isNull);
    });

    test('the first row to claim a spelling wins', () {
      // "Norwegian Bokmål" is an alias of "no" before nb's own row.
      expect(normalizeLanguage('Norwegian Bokmål')?.code2, 'no');
      expect(normalizeLanguage('nob')?.code2, 'nb');
    });

    test('replaces only the first underscore', () {
      expect(normalizeLanguage('zh_hant')?.code2, 'zt');
      expect(normalizeLanguage('en_us_x')?.code2, 'en');
    });

    test('languages compare by code2', () {
      expect(
        normalizeLanguage('ger'),
        const Language(code2: 'de', code3: 'x', name: 'y'),
      );
    });
  });

  group('baseLanguageCode', () {
    test('maps variants to their base language', () {
      expect(baseLanguageCode('pb'), 'pt');
      expect(baseLanguageCode('zt'), 'zh');
      expect(baseLanguageCode('ea'), 'es');
      expect(baseLanguageCode('nb'), 'no');
      expect(baseLanguageCode('nn'), 'no');
      expect(baseLanguageCode('de'), 'de');
    });
  });

  group('parseLanguageList', () {
    List<String> codes(String? list) =>
        parseLanguageList(list).map((l) => l.code2).toList();

    test('dedupes tracks of the same language in first-seen order', () {
      expect(codes('English/English/German'), ['en', 'de']);
      expect(codes('ger/eng/deu'), ['de', 'en']);
    });

    test('drops unknown parts and handles empty input', () {
      expect(codes('eng/und/xx'), ['en']);
      expect(parseLanguageList(''), isEmpty);
      expect(parseLanguageList(null), isEmpty);
    });

    test('accepts commas', () {
      expect(codes('eng, fre'), ['en', 'fr']);
    });
  });
}
