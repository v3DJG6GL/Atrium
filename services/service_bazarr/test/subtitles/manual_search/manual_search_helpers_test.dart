import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';
import 'package:service_bazarr/src/subtitles/manual_search/manual_search_helpers.dart';

BazarrSubtitleSearchResult r(
  String language,
  String provider,
  num score, {
  String forced = 'False',
  String hi = 'False',
}) =>
    BazarrSubtitleSearchResult(
      language: language,
      provider: provider,
      score: score,
      forced: forced,
      hearingImpaired: hi,
      subtitle: '$provider-$language-$score',
    );

void main() {
  final List<BazarrSubtitleSearchResult> results = <BazarrSubtitleSearchResult>[
    r('de', 'opensubtitles', 80),
    r('en', 'addic7ed', 95),
    r('de', 'Addic7ed', 60),
    r('en', 'subscene', 95),
    r('pb', 'opensubtitles', 99),
  ];

  group('filterAndSortResults', () {
    test('best match orders by score, ties keep Bazarr order', () {
      final List<BazarrSubtitleSearchResult> sorted = filterAndSortResults(
        results,
        language: allLanguages,
        sort: ManualSearchSort.best,
      );
      expect(
        sorted.map((BazarrSubtitleSearchResult e) => e.subtitle),
        <String>[
          'opensubtitles-pb-99',
          'addic7ed-en-95',
          'subscene-en-95',
          'opensubtitles-de-80',
          'Addic7ed-de-60',
        ],
      );
    });

    test('provider orders by name (any case), then score', () {
      final List<BazarrSubtitleSearchResult> sorted = filterAndSortResults(
        results,
        language: allLanguages,
        sort: ManualSearchSort.provider,
      );
      expect(
        sorted.map((BazarrSubtitleSearchResult e) => e.subtitle),
        <String>[
          'addic7ed-en-95',
          'Addic7ed-de-60',
          'opensubtitles-pb-99',
          'opensubtitles-de-80',
          'subscene-en-95',
        ],
      );
    });

    test('filters by the raw language value', () {
      final List<BazarrSubtitleSearchResult> de = filterAndSortResults(
        results,
        language: 'de',
        sort: ManualSearchSort.best,
      );
      expect(de.map((BazarrSubtitleSearchResult e) => e.score), <num>[80, 60]);
      expect(
        filterAndSortResults(
          results,
          language: 'fr',
          sort: ManualSearchSort.best,
        ),
        isEmpty,
      );
    });
  });

  test('languageCounts keeps first appearance order', () {
    expect(languageCounts(results), const <LanguageCount>[
      LanguageCount('de', 'German', 2),
      LanguageCount('en', 'English', 2),
      LanguageCount('pb', 'Portuguese (Brazil)', 1),
    ]);
    expect(languageCounts(const <BazarrSubtitleSearchResult>[]), isEmpty);
  });

  test('scoreBand', () {
    expect(scoreBand(100), ScoreBand.high);
    expect(scoreBand(90), ScoreBand.high);
    expect(scoreBand(89.9), ScoreBand.mid);
    expect(scoreBand(70), ScoreBand.mid);
    expect(scoreBand(69), ScoreBand.low);
    expect(scoreBand(0), ScoreBand.low);
    expect(scoreLabel(87.6), '88%');
  });

  test('humanizeMatchKey', () {
    expect(humanizeMatchKey('release_group'), 'Release group');
    expect(humanizeMatchKey('hearing_impaired'), 'Hearing impaired');
    expect(humanizeMatchKey('year'), 'Year');
    expect(humanizeMatchKey(''), '');
  });

  test('relativeTimeLabel', () {
    final DateTime at = DateTime(2026, 1, 1, 12);
    String after(Duration d) => relativeTimeLabel(at, at.add(d));
    expect(after(Duration.zero), 'just now');
    expect(after(const Duration(seconds: 9)), 'just now');
    expect(after(const Duration(seconds: 12)), '12s ago');
    expect(after(const Duration(seconds: 59)), '59s ago');
    expect(after(const Duration(minutes: 3, seconds: 40)), '3m ago');
    expect(after(const Duration(minutes: 59, seconds: 59)), '59m ago');
    expect(after(const Duration(hours: 1, minutes: 30)), '1h ago');
    expect(after(const Duration(seconds: -5)), 'just now');
  });

  test('resultLanguage and the language line', () {
    final ResultLanguage de = resultLanguage('de');
    expect((de.code2, de.name), ('de', 'German'));
    final ResultLanguage unknown = resultLanguage('xx');
    expect((unknown.code2, unknown.name), ('xx', 'xx'));
    expect(languageFilterName(allLanguages), 'All languages');
    expect(languageFilterName('en'), 'English');
    expect(resultLanguageLine(r('de', 'p', 1)), 'German');
    expect(
      resultLanguageLine(r('de', 'p', 1, forced: 'True', hi: 'True')),
      'German, forced, hearing impaired',
    );
  });

  test('resultCountLabel', () {
    expect(resultCountLabel(5, 5), '5 results');
    expect(resultCountLabel(2, 5), '2 of 5 results');
    expect(resultCountLabel(1, 1), '1 result');
    expect(resultCountLabel(0, 0), '0 results');
  });
}
