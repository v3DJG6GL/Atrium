import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Ported from Dashboarr's lib/library-search.test.ts and
// hooks/use-library-search-filter.test.ts.

// The real library items carry dozens of fields the matcher never reads;
// these fixtures stay at the three that actually decide a match.
class _Movie {
  _Movie(this.title, {int? tmdbId, this.sortTitle, this.year})
      : tmdbId = tmdbId ?? title.length;

  final int tmdbId;
  final String title;
  final String? sortTitle;
  final int? year;
}

LibraryMatchFields _fields(_Movie m) =>
    LibraryMatchFields(title: m.title, sortTitle: m.sortTitle, year: m.year);

List<String> _titles(List<_Movie> items) =>
    items.map((_Movie m) => m.title).toList();

void main() {
  group('normalizeSearchText', () {
    test('lowercases and strips diacritics', () {
      expect(normalizeSearchText('Amélie'), 'amelie');
      expect(normalizeSearchText('PIÑATA'), 'pinata');
    });

    test('collapses punctuation and whitespace to single spaces', () {
      expect(normalizeSearchText("Marvel's Daredevil"), 'marvel s daredevil');
      expect(
        normalizeSearchText('Spider-Man:  No   Way Home'),
        'spider man no way home',
      );
    });

    test('keeps non-latin scripts instead of blanking them', () {
      expect(normalizeSearchText('君の名は。'), '君の名は。');
      expect(normalizeSearchText('Слово'), 'слово');
    });

    test('returns an empty string for empty or null input', () {
      expect(normalizeSearchText(''), '');
      expect(normalizeSearchText('   '), '');
      expect(() => normalizeSearchText(null), returnsNormally);
      expect(normalizeSearchText(null), '');
    });

    // Not in the TS suite: Dart has no String.normalize, so the fold table
    // stands in for NFD. Spot-check each block it covers.
    test('folds the Latin, Greek and decomposed forms NFD would', () {
      expect(normalizeSearchText('Ångström Œuvre'), 'angstrom œuvre');
      expect(normalizeSearchText('Łódź Šibenik'), 'łodz sibenik');
      expect(normalizeSearchText('Phở Nguyễn'), 'pho nguyen');
      expect(normalizeSearchText('Ἀθῆναι Άλφα'), 'αθηναι αλφα');
      expect(normalizeSearchText('Amélie'), 'amelie');
    });
  });

  group('parseLibraryQuery', () {
    test('splits a trailing year off the text', () {
      expect(
        parseLibraryQuery('inception 2010'),
        (text: 'inception', year: 2010),
      );
    });

    test("keeps a bare year as text so the movie '2012' is still findable", () {
      expect(parseLibraryQuery('2012'), (text: '2012', year: null));
    });

    test('ignores an implausible year', () {
      expect(
        parseLibraryQuery('blade runner 9999'),
        (text: 'blade runner 9999', year: null),
      );
    });

    test('normalizes the query text', () {
      expect(parseLibraryQuery('  Amélie  '), (text: 'amelie', year: null));
    });
  });

  group('matchLibraryItems', () {
    test('ranks exact over prefix over word-boundary over substring', () {
      final List<_Movie> library = <_Movie>[
        _Movie('Moonknight Saga'), // substring, mid-word
        _Movie('The Dark Knight Rises'), // word boundary
        _Movie('Knight of Cups'), // prefix
        _Movie('Knight'), // exact
      ];
      expect(
        _titles(matchLibraryItems(library, 'knight', _fields)),
        <String>[
          'Knight',
          'Knight of Cups',
          'The Dark Knight Rises',
          'Moonknight Saga',
        ],
      );
    });

    test("matches through sortTitle so leading articles don't have to be typed",
        () {
      final List<_Movie> library = <_Movie>[
        _Movie('The Office', sortTitle: 'Office'),
      ];
      expect(
        _titles(matchLibraryItems(library, 'office', _fields)),
        <String>['The Office'],
      );
    });

    test('matches diacritics typed without accents', () {
      expect(
        _titles(
          matchLibraryItems(<_Movie>[_Movie('Amélie')], 'amelie', _fields),
        ),
        <String>['Amélie'],
      );
    });

    test('falls back to out-of-order tokens for multi-word queries', () {
      final List<_Movie> library = <_Movie>[
        _Movie('Fear and Loathing in Las Vegas'),
      ];
      expect(
        _titles(matchLibraryItems(library, 'vegas fear', _fields)),
        <String>['Fear and Loathing in Las Vegas'],
      );
    });

    test('does not match a single token that is absent', () {
      expect(
        matchLibraryItems(<_Movie>[_Movie('Inception')], 'matrix', _fields),
        isEmpty,
      );
    });

    test('boosts the year that matches and demotes the one that does not', () {
      final List<_Movie> library = <_Movie>[
        _Movie('Dune', tmdbId: 1, year: 1984),
        _Movie('Dune', tmdbId: 2, year: 2021),
      ];
      final List<_Movie> out = matchLibraryItems(library, 'dune 1984', _fields);
      expect(out.map((_Movie m) => m.year), <int>[1984, 2021]);
    });

    test('breaks score ties with the shorter title first', () {
      final List<_Movie> library = <_Movie>[
        _Movie('Alien vs. Predator'),
        _Movie('Alien'),
      ];
      expect(
        _titles(matchLibraryItems(library, 'alien', _fields)),
        <String>['Alien', 'Alien vs. Predator'],
      );
    });

    test('caps the result count at the limit', () {
      final List<_Movie> library = <_Movie>[
        for (int i = 0; i < 30; i++) _Movie('Star Trek $i', tmdbId: i),
      ];
      expect(matchLibraryItems(library, 'star trek', _fields), hasLength(20));
      expect(
        matchLibraryItems(library, 'star trek', _fields, limit: 3),
        hasLength(3),
      );
      expect(
        matchLibraryItems(library, 'star trek', _fields, limit: 0),
        isEmpty,
      );
    });

    test('returns nothing for an empty library or empty query', () {
      expect(matchLibraryItems(<_Movie>[], 'dune', _fields), isEmpty);
      expect(matchLibraryItems<_Movie>(null, 'dune', _fields), isEmpty);
      expect(matchLibraryItems(<_Movie>[_Movie('Dune')], '', _fields), isEmpty);
      expect(
        matchLibraryItems(<_Movie>[_Movie('Dune')], '   ', _fields),
        isEmpty,
      );
    });

    test('does not throw on items with missing optional fields', () {
      expect(
        () => matchLibraryItems(
          <_Movie>[_Movie('Dune', tmdbId: 1)],
          'dune',
          _fields,
        ),
        returnsNormally,
      );
    });
  });

  group('buildLibraryIndex', () {
    test('pre-normalizes both haystacks', () {
      final LibraryIndex<_Movie> index = buildLibraryIndex(
        <_Movie>[_Movie('The Office', sortTitle: 'Office, The')],
        _fields,
      );
      final LibraryIndexEntry<_Movie> entry = index.entries.single;
      expect(entry.title, 'the office');
      expect(entry.sortTitle, 'office the');
    });

    test('returns an empty index for null data (cold cache)', () {
      expect(buildLibraryIndex<_Movie>(null, _fields).entries, isEmpty);
    });
  });

  group('mergeLibraryFirst', () {
    int libraryKey(_Movie m) => m.tmdbId;
    int lookupKey(int r) => r;

    Object? itemOf(MergedSearchRow<_Movie, int> row) => switch (row) {
          LibrarySearchRow<_Movie, int>(:final _Movie item) => item.tmdbId,
          LookupSearchRow<_Movie, int>(:final int item) => item,
        };

    test('puts library matches first and drops their duplicate lookup rows',
        () {
      final List<MergedSearchRow<_Movie, int>> rows = mergeLibraryFirst(
        libraryMatches: <_Movie>[_Movie('Dune', tmdbId: 1)],
        lookupResults: <int>[1, 2],
        libraryKey: libraryKey,
        lookupKey: lookupKey,
      );
      expect(rows[0], isA<LibrarySearchRow<_Movie, int>>());
      expect(rows[1], isA<LookupSearchRow<_Movie, int>>());
      expect(rows.map(itemOf), <int>[1, 2]);
    });

    test('keeps the lookup row for a library item cut by the match limit', () {
      final _Movie cut = _Movie('Dune Part Two', tmdbId: 2);
      final List<_Movie> shown = matchLibraryItems(
        <_Movie>[_Movie('Dune', tmdbId: 1), cut],
        'dune',
        _fields,
        limit: 1,
      );
      final List<MergedSearchRow<_Movie, int>> rows = mergeLibraryFirst(
        libraryMatches: shown,
        lookupResults: <int>[1, 2],
        libraryKey: libraryKey,
        lookupKey: lookupKey,
      );
      expect(rows, hasLength(2));
      expect(rows[0], isA<LibrarySearchRow<_Movie, int>>());
      expect(rows[1], isA<LookupSearchRow<_Movie, int>>());
      expect(itemOf(rows[1]), 2);
    });

    test('passes lookup results through untouched when nothing matched locally',
        () {
      final List<MergedSearchRow<_Movie, int>> rows = mergeLibraryFirst(
        libraryMatches: <_Movie>[],
        lookupResults: <int>[7],
        libraryKey: libraryKey,
        lookupKey: lookupKey,
      );
      expect(rows, hasLength(1));
      expect(rows.single, isA<LookupSearchRow<_Movie, int>>());
      expect(itemOf(rows.single), 7);
    });

    test('renders library matches while the lookup is still null', () {
      final List<MergedSearchRow<_Movie, int>> rows = mergeLibraryFirst(
        libraryMatches: <_Movie>[_Movie('Dune', tmdbId: 1)],
        lookupResults: null,
        libraryKey: libraryKey,
        lookupKey: lookupKey,
      );
      expect(rows, hasLength(1));
      expect(rows.single, isA<LibrarySearchRow<_Movie, int>>());
    });
  });

  group('filterLibraryIndex', () {
    final List<_Movie> items = <_Movie>[
      _Movie('The Matrix Reloaded', year: 2003),
      _Movie('Amélie', year: 2001),
      _Movie('The Matrix', year: 1999),
      _Movie('Dune', year: 2021),
    ];
    final LibraryIndex<_Movie> index = buildLibraryIndex(items, _fields);

    test("keeps the caller's order instead of ranking", () {
      expect(
        _titles(filterLibraryIndex(index, 'matrix')),
        <String>['The Matrix Reloaded', 'The Matrix'],
      );
    });

    test('ignores accents and keeps everything for an empty query', () {
      expect(_titles(filterLibraryIndex(index, 'amelie')), <String>['Amélie']);
      expect(filterLibraryIndex(index, '  '), hasLength(4));
    });

    test('keeps a title that ends in a number', () {
      final LibraryIndex<_Movie> idx = buildLibraryIndex(
        <_Movie>[
          _Movie('Blade Runner 2049', year: 2017),
          _Movie('Blade Runner', year: 1982),
        ],
        _fields,
      );
      expect(
        _titles(filterLibraryIndex(idx, 'blade runner 2049')),
        <String>['Blade Runner 2049'],
      );
    });

    test('requires a trailing year to match', () {
      expect(
        _titles(filterLibraryIndex(index, 'matrix 1999')),
        <String>['The Matrix'],
      );
    });
  });

  // use-library-search-filter.test.ts: the hook's index drops year 0
  // (LibraryMatchFields.arr) and its predicate is filterLibraryIndex.
  group('library search over *arr items', () {
    final List<_Movie> items = <_Movie>[
      _Movie('Dune', tmdbId: 1, year: 2021),
      _Movie('Dune', tmdbId: 2, year: 1984),
      _Movie('Foundation', tmdbId: 3, year: 0),
      _Movie('Andor', tmdbId: 4, year: 2022),
    ];
    final LibraryIndex<_Movie> index = buildLibraryIndex(
      items,
      (_Movie m) => LibraryMatchFields.arr(
        title: m.title,
        sortTitle: m.sortTitle,
        year: m.year,
      ),
    );
    List<int> ids(String query) =>
        filterLibraryIndex(index, query).map((_Movie m) => m.tmdbId).toList();

    test('keeps everything for an empty or blank query', () {
      expect(ids(''), <int>[1, 2, 3, 4]);
      expect(ids('   '), <int>[1, 2, 3, 4]);
    });

    test('matches every title containing the query', () {
      expect(ids('dune'), <int>[1, 2]);
    });

    test('narrows by a trailing year', () {
      expect(ids('dune 1984'), <int>[2]);
    });

    test("doesn't let a trailing year hide a title with no year yet (year 0)",
        () {
      expect(ids('foundation 2026'), <int>[3]);
    });
  });

  group('combineFilters', () {
    bool even(int n) => n.isEven;
    bool big(int n) => n > 5;

    test('is null with nothing active', () {
      expect(combineFilters<int>(<bool Function(int)?>[null, null]), isNull);
    });

    test('returns a lone predicate as-is, keeping its identity', () {
      final bool Function(int) predicate = even;
      expect(
        combineFilters<int>(<bool Function(int)?>[null, predicate]),
        same(predicate),
      );
    });

    test('ANDs several predicates', () {
      final bool Function(int) both =
          combineFilters<int>(<bool Function(int)?>[even, big])!;
      expect(<int>[4, 6, 7, 8].where(both), <int>[6, 8]);
    });
  });
}
