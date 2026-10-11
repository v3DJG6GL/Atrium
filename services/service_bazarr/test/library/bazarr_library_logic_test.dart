import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/library/bazarr_library_logic.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';

// Ported from Dashboarr's lib/bazarr-library.test.ts.

BazarrSubtitle _miss(String code2) =>
    BazarrSubtitle(name: code2, code2: code2, code3: code2);

BazarrSubtitle _sub(String code2) => BazarrSubtitle(
      name: code2,
      code2: code2,
      code3: code2,
      path: '/m/Film.$code2.srt',
    );

BazarrMovie movie(
  int? profileId, [
  List<String> missing = const <String>[],
  List<String> has = const <String>[],
  List<String> audio = const <String>['en'],
]) =>
    BazarrMovie(
      profileId: profileId,
      missingSubtitles: missing.map(_miss).toList(),
      subtitles: has.map(_sub).toList(),
      audioLanguage: <BazarrLanguage>[
        for (final String code2 in audio)
          BazarrLanguage(name: code2, code2: code2, code3: code2),
      ],
    );

BazarrLanguageProfile profile(
  int profileId,
  List<String> langs, [
  List<String> audioExclude = const <String>[],
]) =>
    BazarrLanguageProfile(
      profileId: profileId,
      name: langs.join('+'),
      items: <BazarrProfileItem>[
        for (int id = 0; id < langs.length; id++)
          BazarrProfileItem(
            id: id,
            language: langs[id],
            audioExclude: audioExclude.contains(langs[id]) ? 'True' : 'False',
          ),
      ],
    );

BazarrSeries series({
  int? profileId = 1,
  int missing = 0,
  int files = 0,
}) =>
    BazarrSeries(
      profileId: profileId,
      episodeMissingCount: missing,
      episodeFileCount: files,
    );

LanguageCoverage cov(String code2, int have, int missing, int total) =>
    LanguageCoverage(code2: code2, have: have, missing: missing, total: total);

void main() {
  group('classify', () {
    test('puts no profile first, then missing, else complete', () {
      expect(
        classifyMovie(movie(null, <String>['en'])),
        LibraryItemState.noProfile,
      );
      expect(
        classifyMovie(movie(1, <String>['en'])),
        LibraryItemState.missing,
      );
      expect(classifyMovie(movie(1)), LibraryItemState.complete);
      expect(
        classifySeries(series(missing: 3, files: 5)),
        LibraryItemState.missing,
      );
      expect(
        classifySeries(series(profileId: null, missing: 3, files: 5)),
        LibraryItemState.noProfile,
      );
      expect(classifySeries(series(files: 5)), LibraryItemState.complete);
    });

    test('puts a series without episode files under All only', () {
      final BazarrSeries empty = series();
      expect(classifySeries(empty), LibraryItemState.noFiles);
      expect(
        classifySeries(series(profileId: null)),
        LibraryItemState.noProfile,
      );
      // Bazarr still listing an episode as missing keeps it searchable.
      expect(classifySeries(series(missing: 1)), LibraryItemState.missing);
      final List<BazarrSeries> list = <BazarrSeries>[
        empty,
        series(files: 4),
      ];
      expect(
        filterCounts(list, classifySeries),
        const LibraryCounts(all: 2, complete: 1),
      );
      expect(
        filterSeries(list, LibraryFilter.complete),
        <BazarrSeries>[list[1]],
      );
      expect(filterSeries(list, LibraryFilter.all), hasLength(2));
    });

    test('counts every chip', () {
      expect(
        filterCounts(
          <BazarrMovie>[
            movie(1, <String>['en']),
            movie(1),
            movie(null),
            movie(2, <String>['de']),
          ],
          classifyMovie,
        ),
        const LibraryCounts(all: 4, missing: 2, complete: 1, noProfile: 1),
      );
    });
  });

  group('computeLanguageCoverage', () {
    test('counts movies wanting each language, having it and missing it', () {
      final List<LanguageCoverage> coverage = computeLanguageCoverage(
        <BazarrMovie>[
          movie(1, <String>[], <String>['en', 'de']),
          movie(1, <String>['de'], <String>['en']),
          movie(2, <String>['en']),
          movie(null, <String>[], <String>['en']),
        ],
        profileLanguageMap(<BazarrLanguageProfile>[
          profile(1, <String>['en', 'de']),
          profile(2, <String>['en']),
        ]),
      );
      expect(coverage, <LanguageCoverage>[
        cov('en', 2, 1, 3),
        cov('de', 1, 1, 2),
      ]);
    });

    test("doesn't count a language as had just because Bazarr stopped looking",
        () {
      // Cutoff met on English: German is neither had nor listed as missing.
      final List<LanguageCoverage> coverage = computeLanguageCoverage(
        <BazarrMovie>[
          movie(1, <String>[], <String>['en']),
        ],
        profileLanguageMap(<BazarrLanguageProfile>[
          profile(1, <String>['en', 'de']),
        ]),
      );
      expect(
        coverage.firstWhere((LanguageCoverage c) => c.code2 == 'en'),
        cov('en', 1, 0, 1),
      );
      expect(
        coverage.firstWhere((LanguageCoverage c) => c.code2 == 'de'),
        cov('de', 0, 0, 1),
      );
    });

    test("doesn't count a language Bazarr still lists as missing as had", () {
      // Only a forced English track: Bazarr keeps English as missing.
      expect(
        computeLanguageCoverage(
          <BazarrMovie>[
            movie(1, <String>['en'], <String>['en']),
          ],
          profileLanguageMap(<BazarrLanguageProfile>[
            profile(1, <String>['en']),
          ]),
        ),
        <LanguageCoverage>[cov('en', 0, 1, 1)],
      );
    });

    test("doesn't count a language the profile excludes for the movie's audio",
        () {
      // German excluded when the audio is German: the German-audio movie
      // doesn't want it, the English-audio one does.
      final ProfileLanguages langs = profileLanguageMap(
        <BazarrLanguageProfile>[
          profile(1, <String>['en', 'de'], <String>['de']),
        ],
      );
      final List<LanguageCoverage> coverage = computeLanguageCoverage(
        <BazarrMovie>[
          movie(1, <String>[], <String>['en'], <String>['de']),
          movie(1, <String>['de'], <String>['en'], <String>['en']),
        ],
        langs,
      );
      expect(
        coverage.firstWhere((LanguageCoverage c) => c.code2 == 'de'),
        cov('de', 0, 1, 1),
      );
      expect(
        filterMovies(
          <BazarrMovie>[
            movie(1, <String>[], <String>['de'], <String>['de']),
          ],
          LibraryFilter.all,
          language: const LanguageFilter('de', LanguageShow.have),
          profileLanguages: langs,
        ),
        isEmpty,
      );
    });

    test('only counts an only-if-matching-audio language for movies in that '
        'audio', () {
      const BazarrLanguageProfile p = BazarrLanguageProfile(
        profileId: 1,
        name: 'de',
        items: <BazarrProfileItem>[
          BazarrProfileItem(id: 1, language: 'de', audioOnlyInclude: 'True'),
        ],
      );
      expect(
        computeLanguageCoverage(
          <BazarrMovie>[
            movie(1, <String>[], <String>['de'], <String>['de']),
            movie(1, <String>[], <String>[], <String>['en']),
          ],
          profileLanguageMap(<BazarrLanguageProfile>[p]),
        ),
        <LanguageCoverage>[cov('de', 1, 0, 1)],
      );
    });

    test("still wants a language another profile item doesn't exclude", () {
      const BazarrLanguageProfile p = BazarrLanguageProfile(
        profileId: 1,
        name: 'de',
        items: <BazarrProfileItem>[
          BazarrProfileItem(id: 1, language: 'de', audioExclude: 'True'),
          BazarrProfileItem(id: 2, language: 'de', forced: 'True'),
        ],
      );
      expect(
        computeLanguageCoverage(
          <BazarrMovie>[
            movie(1, <String>[], <String>['de'], <String>['de']),
          ],
          profileLanguageMap(<BazarrLanguageProfile>[p]),
        ),
        <LanguageCoverage>[cov('de', 1, 0, 1)],
      );
    });

    test('counts a language listed twice in a profile once', () {
      const BazarrLanguageProfile p = BazarrLanguageProfile(
        profileId: 1,
        name: 'en',
        items: <BazarrProfileItem>[
          BazarrProfileItem(id: 1, language: 'en'),
          BazarrProfileItem(id: 2, language: 'en', forced: 'True'),
        ],
      );
      expect(
        computeLanguageCoverage(
          <BazarrMovie>[
            movie(1, <String>[], <String>['en']),
          ],
          profileLanguageMap(<BazarrLanguageProfile>[p]),
        ),
        <LanguageCoverage>[cov('en', 1, 0, 1)],
      );
    });
  });

  group('filters', () {
    final List<BazarrMovie> movies = <BazarrMovie>[
      movie(1, <String>['de'], <String>['en']),
      movie(1, <String>[], <String>['en', 'de']),
      movie(null, <String>[], <String>['en']),
      movie(1, <String>['en', 'de']),
      // Cutoff met on German: English neither had nor missing.
      movie(1, <String>[], <String>['de']),
    ];
    final ProfileLanguages langs = profileLanguageMap(<BazarrLanguageProfile>[
      profile(1, <String>['en', 'de']),
    ]);
    LanguageCoverage coverageOf(String code2) =>
        computeLanguageCoverage(movies, langs)
            .firstWhere((LanguageCoverage c) => c.code2 == code2);

    test('filters by chip', () {
      expect(filterMovies(movies, LibraryFilter.missing), hasLength(2));
      expect(filterMovies(movies, LibraryFilter.all), hasLength(5));
    });

    test('narrows to movies missing a language, counted like the bar', () {
      final List<BazarrMovie> en = filterMovies(
        movies,
        LibraryFilter.all,
        language: const LanguageFilter('en', LanguageShow.missing),
        profileLanguages: langs,
      );
      expect(en, <BazarrMovie>[movies[3]]);
      expect(en, hasLength(coverageOf('en').missing));
      expect(
        filterMovies(
          movies,
          LibraryFilter.missing,
          language: const LanguageFilter('de', LanguageShow.missing),
          profileLanguages: langs,
        ),
        hasLength(2),
      );
    });

    test("only lists a missing language the movie's profile still wants", () {
      // Profile 1 exists but asks for English and German only.
      expect(
        filterMovies(
          <BazarrMovie>[
            movie(1, <String>['fr']),
          ],
          LibraryFilter.all,
          language: const LanguageFilter('fr', LanguageShow.missing),
          profileLanguages: langs,
        ),
        isEmpty,
      );
    });

    test('narrows to movies that have a language, counted like the bar', () {
      final List<BazarrMovie> have = filterMovies(
        movies,
        LibraryFilter.all,
        language: const LanguageFilter('en', LanguageShow.have),
        profileLanguages: langs,
      );
      // The no-profile movie doesn't want English, and the cutoff movie
      // doesn't have it, so neither is counted.
      expect(have, <BazarrMovie>[movies[0], movies[1]]);
      expect(have, hasLength(coverageOf('en').have));
    });

    test('cycles a coverage bar off → missing → have → off', () {
      final LanguageFilter? missing = nextLanguageFilter(null, 'en');
      expect(missing, const LanguageFilter('en', LanguageShow.missing));
      final LanguageFilter? have = nextLanguageFilter(missing, 'en');
      expect(have, const LanguageFilter('en', LanguageShow.have));
      expect(nextLanguageFilter(have, 'en'), isNull);
      // Another language starts over at missing.
      expect(
        nextLanguageFilter(have, 'de'),
        const LanguageFilter('de', LanguageShow.missing),
      );
    });

    test('filters series', () {
      expect(
        filterSeries(
          <BazarrSeries>[
            series(files: 4),
            series(missing: 2, files: 4),
          ],
          LibraryFilter.complete,
        ),
        hasLength(1),
      );
    });
  });

  group('seriesCoverage', () {
    test('is the share of episodes with every wanted subtitle', () {
      expect(
        seriesCoverage(series(files: 10, missing: 3)),
        closeTo(0.7, 1e-9),
      );
      expect(seriesCoverage(series()), 0);
    });

    test('never counts below zero subtitled episodes', () {
      expect(seriesSubtitledCount(series(files: 2, missing: 5)), 0);
      expect(seriesCoverage(series(files: 2, missing: 5)), 0);
    });
  });

  group('coveragePercent', () {
    test('is 0 only when none and 100 only when all', () {
      expect(coveragePercent(0, 200), 0);
      expect(coveragePercent(0, 0), 0);
      expect(coveragePercent(5, 0), 0);
      expect(coveragePercent(200, 200), 100);
      expect(coveragePercent(3, 2), 100);
    });

    test('clamps everything in between to 1–99', () {
      expect(coveragePercent(1, 200), 1);
      expect(coveragePercent(199, 200), 99);
      expect(coveragePercent(1, 2), 50);
      expect(coveragePercent(2, 3), 67);
    });
  });
}
