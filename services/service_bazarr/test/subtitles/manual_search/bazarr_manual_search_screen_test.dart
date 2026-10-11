import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_profile/core_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/bazarr_api.dart';
import 'package:service_bazarr/src/bazarr_providers.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';
import 'package:service_bazarr/src/subtitles/bazarr_activity.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitle_params.dart';
import 'package:service_bazarr/src/subtitles/manual_search/bazarr_manual_search_screen.dart';
import 'package:service_bazarr/src/subtitles/manual_search/manual_search_result_card.dart';
import 'package:service_bazarr/src/subtitles/manual_search/open_manual_search.dart';

import '../../support/fake_scheduler.dart';

const Instance bazarr = Instance(
  id: 'bazarr-1',
  name: 'Bazarr',
  kind: ServiceKind.bazarr,
  localUrl: 'http://localhost:6767',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'key'),
);

const SubtitleTarget target = MovieTarget(42);

class FakeBazarrApi extends BazarrApi {
  FakeBazarrApi() : super(Dio(BaseOptions()));

  final List<Completer<List<BazarrSubtitleSearchResult>>> searches =
      <Completer<List<BazarrSubtitleSearchResult>>>[];
  final List<CancelToken?> tokens = <CancelToken?>[];
  final List<(SubtitleTarget, BazarrSubtitleSearchResult)> downloads =
      <(SubtitleTarget, BazarrSubtitleSearchResult)>[];
  Object? downloadError;

  int get searchCalls => searches.length;

  @override
  Future<List<BazarrSubtitleSearchResult>> manualSearch(
    SubtitleTarget target, {
    CancelToken? cancelToken,
  }) {
    tokens.add(cancelToken);
    final Completer<List<BazarrSubtitleSearchResult>> c =
        Completer<List<BazarrSubtitleSearchResult>>();
    searches.add(c);
    return c.future;
  }

  @override
  Future<void> downloadResult(
    SubtitleTarget target,
    BazarrSubtitleSearchResult result,
  ) async {
    downloads.add((target, result));
    final Object? error = downloadError;
    if (error != null) {
      throw error;
    }
  }
}

BazarrSubtitleSearchResult result(
  String language,
  String provider,
  num score, {
  List<String> releases = const <String>['Movie.2024.1080p.WEB-DL-GRP'],
}) =>
    BazarrSubtitleSearchResult(
      language: language,
      provider: provider,
      score: score,
      subtitle: '$provider-$language-$score',
      releaseInfo: releases,
      matches: const <String>['release_group', 'resolution', 'year'],
      dontMatches: const <String>['source'],
      uploader: 'someone',
      url: 'https://example.com/sub/1',
    );

final List<BazarrSubtitleSearchResult> fiveResults =
    <BazarrSubtitleSearchResult>[
  result('en', 'opensubtitles', 95),
  result(
    'de',
    'addic7ed',
    92,
    releases: <String>['Movie.2024.German.1080p-GRP', 'Movie.2024.720p-GRP'],
  ),
  result('en', 'subscene', 71),
  result('de', 'opensubtitles', 40),
  result('fr', 'podnapisi', 66),
];

void main() {
  late FakeBazarrApi api;

  setUp(() => api = FakeBazarrApi());

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeScheduler scheduler = FakeScheduler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeInstancesProvider.overrideWithValue(const <Instance>[bazarr]),
          bazarrApiProvider.overrideWith((Ref ref, Instance _) async => api),
          bazarrJobWatchConfigProvider.overrideWithValue(
            JobWatchConfig(
              schedule: scheduler.schedule,
              now: () => scheduler.now,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TextButton(
                  onPressed: () => openBazarrManualSearch(
                    context,
                    bazarr: bazarr,
                    target: target,
                    title: 'Movie',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The searching state animates forever, so pumpAndSettle can't be used
  // until results are in.
  Future<void> frames(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await frames(tester);
  }

  Future<void> answer(
    WidgetTester tester,
    List<BazarrSubtitleSearchResult> results,
  ) async {
    api.searches.last.complete(results);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    final NavigatorState nav = tester.state(find.byType(Navigator).first);
    nav.pop();
    await frames(tester);
  }

  testWidgets('searches on open and shows the searching state',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);

    expect(find.text('Subtitles · Movie'), findsOneWidget);
    expect(find.text('Searching providers…'), findsOneWidget);
    expect(find.text('Restart search'), findsNothing);
    expect(api.searchCalls, 1);
  });

  testWidgets('offers a restart after 30 s that searches again',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);

    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Restart search'), findsOneWidget);

    await tester.tap(find.text('Restart search'));
    await frames(tester);
    expect(api.searchCalls, 2);
    expect(api.tokens.first!.isCancelled, isTrue);
    expect(find.text('Searching providers…'), findsOneWidget);
    expect(find.text('Restart search'), findsNothing);
  });

  testWidgets('a timed-out search shows the error and retries',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);

    api.searches.last.completeError(
      const NetworkTimeoutException('Server took too long to respond.'),
    );
    await frames(tester);
    expect(find.text('Search failed'), findsOneWidget);
    expect(
      find.text('The search timed out. Providers may be slow or '
          'rate-limited. Try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await frames(tester);
    expect(api.searchCalls, 2);
    expect(find.text('Searching providers…'), findsOneWidget);
  });

  testWidgets('renders result cards with score badges',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);
    await answer(tester, fiveResults);

    expect(find.byType(ManualSearchResultCard), findsNWidgets(5));
    expect(find.byType(ScoreBadge), findsNWidgets(5));
    expect(find.text('95%'), findsOneWidget);
    expect(find.text('5 results'), findsOneWidget);
    expect(find.text('· just now'), findsOneWidget);
    expect(find.text('All languages · Best match'), findsOneWidget);
    // " +1" marks the extra release name.
    expect(
      find.textContaining('Movie.2024.German.1080p-GRP +1', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('shows the empty state', (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);
    await answer(tester, const <BazarrSubtitleSearchResult>[]);

    expect(find.text('No subtitles found'), findsOneWidget);
    expect(find.text('0 results'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('the filter sheet narrows to one language',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);
    await answer(tester, fiveResults);

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    expect(find.text('Filter & sort subtitles'), findsOneWidget);
    expect(find.text('All languages (5)'), findsOneWidget);
    expect(find.text('English (2)'), findsOneWidget);
    expect(find.text('French (1)'), findsOneWidget);

    await tester.tap(find.text('German (2)'));
    await tester.tap(find.text('Provider'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Filter & sort subtitles'), findsNothing);
    expect(find.text('2 of 5 results'), findsOneWidget);
    expect(find.text('German · Provider'), findsOneWidget);
    expect(find.byType(ManualSearchResultCard), findsNWidgets(2));
    // Provider order: addic7ed before opensubtitles.
    final List<ManualSearchResultCard> cards = tester
        .widgetList<ManualSearchResultCard>(find.byType(ManualSearchResultCard))
        .toList();
    expect(cards.map((ManualSearchResultCard c) => c.result.provider), <String>[
      'addic7ed',
      'opensubtitles',
    ]);
  });

  testWidgets('a card opens its details', (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);
    await answer(tester, fiveResults);

    await tester.tap(find.byType(ManualSearchResultCard).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Subtitle details'), findsOneWidget);
    expect(find.text('addic7ed · someone'), findsOneWidget);
    expect(find.text('Movie.2024.720p-GRP'), findsOneWidget);
    expect(find.text('German'), findsOneWidget);
    expect(find.text('Matched'), findsOneWidget);
    expect(find.text('Release group'), findsOneWidget);
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text("Didn't match"), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Converted to SRT'), findsOneWidget);
    expect(find.text('https://example.com/sub/1'), findsOneWidget);
  });

  testWidgets('Download hands the result to Bazarr and leaves the search',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);
    await answer(tester, fiveResults);

    await tester.tap(find.byType(ManualSearchResultCard).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(api.downloads, hasLength(1));
    expect(api.downloads.single.$1, target);
    expect(api.downloads.single.$2, fiveResults[1]);
    expect(find.byType(BazarrManualSearchScreen), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Downloading German subtitle…'), findsOneWidget);
  });

  testWidgets('a failed download keeps the sheet open with the error',
      (WidgetTester tester) async {
    api.downloadError = const NetworkServerException('boom', status: 500);
    await pumpHome(tester);
    await open(tester);
    await answer(tester, fiveResults);

    await tester.tap(find.byType(ManualSearchResultCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't download the subtitle"), findsOneWidget);
    expect(find.text('Subtitle details'), findsOneWidget);
    expect(find.byType(BazarrManualSearchScreen), findsOneWidget);
  });

  testWidgets('leaving the screen cancels the search',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);
    expect(api.tokens.single!.isCancelled, isFalse);

    await back(tester);
    await tester.pumpAndSettle();
    expect(find.byType(BazarrManualSearchScreen), findsNothing);
    expect(api.tokens.single!.isCancelled, isTrue);
  });

  testWidgets('results are reused for 60 s after leaving',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await open(tester);
    await answer(tester, fiveResults);
    await back(tester);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 30));
    await open(tester);
    await tester.pumpAndSettle();
    expect(api.searchCalls, 1);
    expect(find.byType(ManualSearchResultCard), findsNWidgets(5));

    await back(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 61));
    await open(tester);
    expect(api.searchCalls, 2);
    expect(find.text('Searching providers…'), findsOneWidget);
  });
}
