import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/bazarr_movie_detail_screen.dart';
import 'package:service_bazarr/src/bazarr_open.dart';
import 'package:service_bazarr/src/bazarr_providers.dart';
import 'package:service_bazarr/src/library/bazarr_library_tab.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';

import '../subtitles/subtitle_test_support.dart';
import '../support/fake_scheduler.dart';

const BazarrLanguage _en = BazarrLanguage(name: 'English', code2: 'en');

BazarrSubtitle _s(String code2, {String? path}) => BazarrSubtitle(
      name: code2 == 'en' ? 'English' : 'German',
      code2: code2,
      code3: code2 == 'en' ? 'eng' : 'ger',
      path: path,
    );

BazarrMovie _movie(
  int id,
  String title, {
  int? profileId = 1,
  List<String> missing = const <String>[],
  List<String> has = const <String>[],
}) =>
    BazarrMovie(
      radarrId: id,
      title: title,
      year: 2000 + id,
      profileId: profileId,
      missingSubtitles: <BazarrSubtitle>[for (final String c in missing) _s(c)],
      subtitles: <BazarrSubtitle>[
        for (final String c in has) _s(c, path: '/m/$title.$c.srt'),
      ],
      audioLanguage: const <BazarrLanguage>[_en],
    );

/// Profile 1 wants English and German.
const List<BazarrLanguageProfile> _profiles = <BazarrLanguageProfile>[
  BazarrLanguageProfile(
    profileId: 1,
    name: 'Default',
    items: <BazarrProfileItem>[
      BazarrProfileItem(id: 1, language: 'en'),
      BazarrProfileItem(id: 2, language: 'de'),
    ],
  ),
];

/// en: 2 have (Alpha, Bravo), 1 missing (Delta) of 4 wanting it (Echo
/// neither); de: 2 have (Bravo, Echo), 2 missing (Alpha, Delta).
final List<BazarrMovie> _movies = <BazarrMovie>[
  _movie(1, 'Alpha', missing: <String>['de'], has: <String>['en']),
  _movie(2, 'Bravo', has: <String>['en', 'de']),
  _movie(3, 'Charlie', profileId: null, has: <String>['en']),
  _movie(4, 'Delta', missing: <String>['en', 'de']),
  _movie(5, 'Echo', has: <String>['de']),
];

final List<BazarrSeries> _series = <BazarrSeries>[
  const BazarrSeries(
    sonarrSeriesId: 9,
    title: 'Show',
    profileId: 1,
    episodeFileCount: 5,
    episodeMissingCount: 3,
  ),
  const BazarrSeries(
    sonarrSeriesId: 10,
    title: 'Done Show',
    profileId: 1,
    episodeFileCount: 4,
  ),
];

class FakeLibraryApi extends FakeSubtitlesApi {
  @override
  Future<void> searchWanted({required bool movies}) {
    calls.add('search-wanted ${movies ? 'movies' : 'series'}');
    return answer();
  }
}

class _FakeTargets extends ArrTargets {
  final List<String> opened = <String>[];

  @override
  Future<void> openRadarrMovie(
    BuildContext context, {
    required Instance radarr,
    required int movieId,
  }) async {
    opened.add('radarr ${radarr.id} $movieId');
  }

  @override
  Future<void> openSonarrSeries(
    BuildContext context, {
    required Instance sonarr,
    required int seriesId,
    int? episodeId,
  }) async {
    opened.add('sonarr ${sonarr.id} $seriesId');
  }

  @override
  String? Function(int itemId)? posterResolver(
    WidgetRef ref,
    Instance arr, {
    int width = 250,
  }) =>
      null;
}

late FakeLibraryApi api;
late FakeScheduler scheduler;

Future<void> pumpLibrary(
  WidgetTester tester, {
  FutureOr<List<BazarrMovie>> Function()? movies,
  FutureOr<List<BazarrSeries>> Function()? series,
  ArrTargets? targets,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final List<Override> overrides = <Override>[
    ...subtitleOverrides(
      api: api,
      scheduler: scheduler,
      profiles: () => _profiles,
    ),
    bazarrMoviesProvider.overrideWith(
      (Ref ref, Instance _) async => (movies ?? () => _movies)(),
    ),
    bazarrSeriesProvider.overrideWith(
      (Ref ref, Instance _) async => (series ?? () => _series)(),
    ),
    bazarrArrTargetsProvider.overrideWithValue(targets),
  ];
  await tester.pumpWidget(
    ProviderScope(
      retry: (int _, Object __) => null,
      overrides: overrides,
      child: const MaterialApp(
        home: Scaffold(body: BazarrLibraryTab(instance: bazarr)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The movie rows (by title) on screen, in order.
List<String> shownTitles(WidgetTester tester) => <String>[
      for (final String t in <String>[
        'Alpha',
        'Bravo',
        'Charlie',
        'Delta',
        'Echo',
      ])
        if (find.text(t).evaluate().isNotEmpty) t,
    ];

Future<void> tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilterChip, label));
  await tester.pump();
}

void main() {
  setUp(() {
    api = FakeLibraryApi();
    scheduler = FakeScheduler();
  });

  testWidgets('the chips count the movies in each state', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);

    expect(find.widgetWithText(FilterChip, 'All'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Missing 2'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Complete 2'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'No profile 1'), findsOneWidget);
    expect(shownTitles(tester), hasLength(5));

    await tapChip(tester, 'Missing 2');
    expect(shownTitles(tester), <String>['Alpha', 'Delta']);
    await tapChip(tester, 'No profile 1');
    expect(shownTitles(tester), <String>['Charlie']);
  });

  testWidgets('a coverage bar cycles missing → available → off and its count '
      'matches the list', (WidgetTester tester) async {
    await pumpLibrary(tester);
    final Finder en = find.byKey(const ValueKey<String>('coverage-en'));
    // en: 2 of 4; de: 2 of 4.
    expect(find.text('50%'), findsNWidgets(2));
    expect(
      find.bySemanticsLabel(
        RegExp(r'^English: 2 of 4 movies have it, 1 missing\. Tap to show'),
      ),
      findsOneWidget,
    );

    await tester.tap(en);
    await tester.pump();
    expect(find.text('1 missing'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(shownTitles(tester), <String>['Delta']);

    await tester.tap(en);
    await tester.pump();
    expect(find.text('2 available'), findsOneWidget);
    expect(shownTitles(tester), <String>['Alpha', 'Bravo']);

    await tester.tap(en);
    await tester.pump();
    expect(find.text('50%'), findsNWidgets(2));
    expect(shownTitles(tester), hasLength(5));

    // Another language starts at missing.
    await tester.tap(en);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('coverage-de')));
    await tester.pump();
    expect(find.text('2 missing'), findsOneWidget);
    expect(shownTitles(tester), <String>['Alpha', 'Delta']);
  });

  testWidgets('"Search all missing" confirms, then searches every movie', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);
    expect(find.textContaining('Search all'), findsNothing);

    await tapChip(tester, 'Missing 2');
    await tester.tap(find.text('Search all 2 missing'));
    await settle(tester);
    expect(find.text('Search Missing Subtitles'), findsOneWidget);
    expect(
      find.text('Bazarr will search every missing movie subtitle in your '
          'library. This can queue a lot of searches at once.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await settle(tester);
    expect(api.calls, <String>['search-wanted movies']);
    expect(find.text('Searching every missing movie subtitle…'), findsOneWidget);
    // Busy until Bazarr's queue drains.
    expect(find.text('Searching…'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation searches nothing', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);
    await tapChip(tester, 'Missing 2');
    await tester.tap(find.text('Search all 2 missing'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(api.calls, isEmpty);
    expect(find.text('Search all 2 missing'), findsOneWidget);
  });

  testWidgets('a movie row searches its missing languages with a spinner', (
    WidgetTester tester,
  ) async {
    api.answer = never;
    await pumpLibrary(tester);
    // No search buttons outside the Missing filters.
    expect(find.byTooltip('Search missing subtitles for Alpha'), findsNothing);

    await tapChip(tester, 'Missing 2');
    final Finder search = find.byTooltip('Search missing subtitles for Alpha');
    expect(search, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(search);
    await tester.pump();
    expect(api.calls, <String>['search-missing m1']);
    expect(
      find.descendant(
        of: search,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    // Only that row is busy.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a coverage bar on missing shows the rows\' search buttons', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);
    await tester.tap(find.byKey(const ValueKey<String>('coverage-de')));
    await tester.pump();
    expect(find.byTooltip('Search missing subtitles for Alpha'), findsOneWidget);
    expect(find.byTooltip('Search missing subtitles for Delta'), findsOneWidget);
  });

  testWidgets('switching the kind keeps each kind\'s chip and clears the '
      'language filter', (WidgetTester tester) async {
    await pumpLibrary(tester);
    await tapChip(tester, 'Missing 2');
    await tester.tap(find.byKey(const ValueKey<String>('coverage-en')));
    await tester.pump();
    expect(shownTitles(tester), <String>['Delta']);

    await tester.tap(find.text('Series'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Search series'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('coverage-en')), findsNothing);
    // The series' chip is its own: still All.
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Done Show'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Missing 1'), findsOneWidget);

    await tester.tap(find.text('Movies'));
    await tester.pump();
    await tester.pump();
    // Missing is still on; the language filter is gone.
    expect(find.text('1 missing'), findsNothing);
    expect(shownTitles(tester), <String>['Alpha', 'Delta']);
  });

  testWidgets('a row opens the movie on its Radarr page', (
    WidgetTester tester,
  ) async {
    final _FakeTargets targets = _FakeTargets();
    await pumpLibrary(tester, targets: targets);
    await tester.tap(find.text('Bravo'));
    await tester.pump();
    expect(targets.opened, <String>['radarr r1 2']);
  });

  testWidgets("without Radarr a row opens Bazarr's own movie page", (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('Bravo'));
    await settle(tester);
    expect(find.byType(BazarrMovieDetailScreen), findsOneWidget);
  });

  testWidgets('a series row opens the series on its Sonarr page', (
    WidgetTester tester,
  ) async {
    final _FakeTargets targets = _FakeTargets();
    await pumpLibrary(tester, targets: targets);
    await tester.tap(find.text('Series'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(targets.opened, <String>['sonarr s1 9']);
  });

  testWidgets('under Missing a series row expands to its missing episodes', (
    WidgetTester tester,
  ) async {
    api.answer = never;
    await pumpLibrary(tester);
    await tester.tap(find.text('Series'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Show missing episodes'), findsNothing);

    await tapChip(tester, 'Missing 1');
    await tester.tap(find.byTooltip('Show missing episodes'));
    await tester.pump();
    await tester.pump();
    // Newest first.
    final List<String> codes = <String>[
      for (final Element e in find.textContaining(' — ').evaluate())
        (e.widget as Text).data!,
    ];
    expect(codes, <String>[
      'S02E03 — Episode 3',
      'S02E01 — Episode 1',
      'S01E02 — Episode 2',
    ]);

    await tester.tap(find.byTooltip('Search subtitles for S02E03'));
    await tester.pump();
    expect(api.calls, <String>['search e203 en']);
    expect(
      find.descendant(
        of: find.byTooltip('Search subtitles for S02E03'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Hide missing episodes'));
    await tester.pump();
    expect(find.textContaining(' — '), findsNothing);
  });

  testWidgets('Bazarr without movies says so', (WidgetTester tester) async {
    await pumpLibrary(tester, movies: () => const <BazarrMovie>[]);
    expect(find.text('Bazarr has no movies yet'), findsOneWidget);
    expect(
      find.text('They appear once Bazarr syncs with Radarr and Sonarr.'),
      findsOneWidget,
    );
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('a search without a match offers to clear the filters', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);
    await tester.enterText(find.byType(SearchBar), 'zzz');
    await tester.pump();
    // Debounced: nothing narrows yet.
    expect(shownTitles(tester), hasLength(5));
    await tester.pump(librarySearchDebounce);
    expect(find.text('No movies match'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    await tester.pump();
    expect(shownTitles(tester), hasLength(5));
    expect(find.text('zzz'), findsNothing);
  });

  testWidgets('the search ignores accents', (WidgetTester tester) async {
    await pumpLibrary(
      tester,
      movies: () => <BazarrMovie>[
        _movie(1, 'Amélie'),
        _movie(2, 'Bravo'),
      ],
    );
    await tester.enterText(find.byType(SearchBar), 'amelie');
    await tester.pump(librarySearchDebounce);
    await tester.pump();
    expect(find.text('Amélie'), findsOneWidget);
    expect(find.text('Bravo'), findsNothing);
  });

  testWidgets('a failed first load says what failed', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(
      tester,
      movies: () => Future<List<BazarrMovie>>.error(StateError('down')),
    );
    await tester.pump();
    expect(find.text("Couldn't load Bazarr's movies"), findsOneWidget);
  });

  testWidgets('posters show the movies in a grid', (WidgetTester tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.byTooltip('Show posters'));
    await tester.pump();
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byTooltip('Show list'), findsOneWidget);

    // The layout is per kind.
    await tester.tap(find.text('Series'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SliverGrid), findsNothing);
    expect(find.byTooltip('Show posters'), findsOneWidget);
  });
}
