import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/bazarr_api.dart';
import 'package:service_bazarr/src/bazarr_history_tab.dart';
import 'package:service_bazarr/src/bazarr_open.dart';
import 'package:service_bazarr/src/bazarr_providers.dart';
import 'package:service_bazarr/src/history/bazarr_history_providers.dart';
import 'package:service_bazarr/src/link/bazarr_link_providers.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';
import 'package:service_bazarr/src/subtitles/bazarr_activity.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitle_params.dart';

import '../support/fake_scheduler.dart';

const Instance bazarr = Instance(
  id: 'bazarr-1',
  name: 'Bazarr Test',
  kind: ServiceKind.bazarr,
  localUrl: 'http://localhost:6767',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'dummy-api-key'),
);

const Instance sonarr = Instance(
  id: 'sonarr-1',
  name: 'Sonarr Test',
  kind: ServiceKind.sonarr,
  localUrl: 'http://localhost:8989',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'dummy-api-key'),
);

/// "Now" for the tab's day groups: 2026-10-12 12:00 local.
final DateTime now = DateTime(2026, 10, 12, 12);

const BazarrSubtitle english =
    BazarrSubtitle(name: 'English', code2: 'en', code3: 'eng');

/// A download of "Dune" today, eligible for the blacklist.
const BazarrHistoryItem duneDownload = BazarrHistoryItem(
  title: 'Dune',
  action: 1,
  parsedTimestamp: '10/12/26 10:00:00',
  provider: 'opensubtitles',
  score: '93%',
  language: english,
  radarrId: 4,
  subsId: 'abc',
  subtitlesPath: '/movies/Dune/Dune.en.srt',
  description: 'English subtitles downloaded from opensubtitles.',
  matches: <String>['release_group', 'year'],
  dontMatches: <String>['video_codec'],
);

/// A sync of an undated movie: not eligible.
const BazarrHistoryItem oldSync = BazarrHistoryItem(
  title: 'Old Movie',
  action: 5,
  parsedTimestamp: 'sometime',
  language: english,
  radarrId: 5,
);

/// An episode download today.
const BazarrHistoryItem episodeDownload = BazarrHistoryItem(
  seriesTitle: 'Severance',
  episodeNumber: '1x02',
  episodeTitle: 'Half Loop',
  action: 1,
  parsedTimestamp: '10/12/26 09:00:00',
  provider: 'addic7ed',
  score: '88%',
  language: english,
  sonarrSeriesId: 2,
  sonarrEpisodeId: 9,
  subsId: 'xyz',
  subtitlesPath: '/tv/Severance/S01E02.en.srt',
);

class FakeBazarrApi extends BazarrApi {
  FakeBazarrApi({required this.movies, required this.episodes}) : super(Dio());

  List<BazarrHistoryItem> movies;
  List<BazarrHistoryItem> episodes;

  /// Every history request: (movies?, start).
  final List<(bool, int)> requests = <(bool, int)>[];

  /// Every blacklist request: (target, provider, subsId).
  final List<(SubtitleTarget, String, String)> blacklists =
      <(SubtitleTarget, String, String)>[];

  /// Streams (movies?) whose requests fail.
  final Set<bool> failing = <bool>{};

  /// What [blacklistSubtitle] awaits; null answers at once.
  Completer<void>? blacklistResult;

  @override
  Future<BazarrHistoryPage> getHistoryPage({
    required bool movies,
    int start = 0,
    int length = 50,
  }) async {
    requests.add((movies, start));
    if (failing.contains(movies)) {
      throw StateError('history down');
    }
    final List<BazarrHistoryItem> all = movies ? this.movies : episodes;
    final int end = (start + length).clamp(0, all.length);
    return BazarrHistoryPage(
      items: start >= all.length
          ? const <BazarrHistoryItem>[]
          : all.sublist(start, end),
      total: all.length,
    );
  }

  @override
  Future<void> blacklistSubtitle(
    SubtitleTarget target, {
    required String provider,
    required String subsId,
    required String language,
    required String subtitlesPath,
  }) async {
    blacklists.add((target, provider, subsId));
    await blacklistResult?.future;
  }

  @override
  Future<List<int>?> getActiveJobIds() async => <int>[];
}

class FakeArrTargets extends ArrTargets {
  final List<(Instance, int, int?)> seriesOpened = <(Instance, int, int?)>[];
  final List<(Instance, int)> moviesOpened = <(Instance, int)>[];

  @override
  Future<void> openRadarrMovie(
    BuildContext context, {
    required Instance radarr,
    required int movieId,
  }) async =>
      moviesOpened.add((radarr, movieId));

  @override
  Future<void> openSonarrSeries(
    BuildContext context, {
    required Instance sonarr,
    required int seriesId,
    int? episodeId,
  }) async =>
      seriesOpened.add((sonarr, seriesId, episodeId));

  @override
  String? Function(int itemId)? posterResolver(
    WidgetRef ref,
    Instance arr, {
    int width = 250,
  }) =>
      null;
}

void main() {
  late FakeScheduler scheduler;

  setUp(() => scheduler = FakeScheduler());

  Future<FakeBazarrApi> pump(
    WidgetTester tester, {
    List<BazarrHistoryItem> movies = const <BazarrHistoryItem>[
      duneDownload,
      oldSync,
    ],
    List<BazarrHistoryItem> episodes = const <BazarrHistoryItem>[
      episodeDownload,
    ],
    ArrTargets? targets,
    Set<bool> failing = const <bool>{},
  }) async {
    final FakeBazarrApi api = FakeBazarrApi(movies: movies, episodes: episodes)
      ..failing.addAll(failing);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeInstancesProvider.overrideWith(
            (Ref ref) => const <Instance>[bazarr, sonarr],
          ),
          bazarrApiProvider.overrideWith((Ref ref, Instance _) async => api),
          bazarrSystemStatusProvider.overrideWith(
            (Ref ref, Instance _) async =>
                const BazarrSystemStatus(bazarrVersion: '1.6.2'),
          ),
          bazarrJobWatchConfigProvider.overrideWithValue(
            JobWatchConfig(
              schedule: scheduler.schedule,
              now: () => scheduler.now,
            ),
          ),
          bazarrHistoryClockProvider.overrideWithValue(() => now),
          if (targets != null) ...[
            bazarrArrTargetsProvider.overrideWithValue(targets),
            bazarrItemsArrProvider.overrideWith(
              (Ref ref, ({String bazarrId, ServiceKind kind}) arg) =>
                  arg.kind == ServiceKind.sonarr ? sonarr : null,
            ),
          ],
        ],
        child: const MaterialApp(
          home: Scaffold(body: BazarrHistoryTab(instance: bazarr)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('groups entries under Today and Earlier', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Severance · 1x02 · Half Loop'), findsOneWidget);
    expect(find.text('Old Movie'), findsOneWidget);
    expect(find.text('Downloaded · opensubtitles · 93%'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    // Today's rows come before the undated one.
    expect(
      tester.getTopLeft(find.text('Today')).dy,
      lessThan(tester.getTopLeft(find.text('Earlier')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Severance · 1x02 · Half Loop')).dy,
      lessThan(tester.getTopLeft(find.text('Earlier')).dy),
    );
  });

  testWidgets('the Movies filter shows only movies', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Movies'));
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Old Movie'), findsOneWidget);
    expect(find.text('Severance · 1x02 · Half Loop'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Episodes'));
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsNothing);
    expect(find.text('Severance · 1x02 · Half Loop'), findsOneWidget);
  });

  testWidgets('shows the empty state', (WidgetTester tester) async {
    await pump(
      tester,
      movies: const <BazarrHistoryItem>[],
      episodes: const <BazarrHistoryItem>[],
    );

    expect(find.text('No subtitle activity yet'), findsOneWidget);
    expect(
      find.text('Downloads, uploads and changes show up here.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the error when no history could load', (
    WidgetTester tester,
  ) async {
    final FakeBazarrApi api = await pump(tester, failing: <bool>{true, false});

    expect(find.text("Couldn't load history"), findsOneWidget);

    api.failing.clear();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load history"), findsNothing);
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('a failed stream shows a banner above the rows it has', (
    WidgetTester tester,
  ) async {
    await pump(tester, failing: <bool>{false});

    expect(find.text("Some history couldn't load"), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Severance · 1x02 · Half Loop'), findsNothing);
  });

  testWidgets('scrolling to the end loads the next page', (
    WidgetTester tester,
  ) async {
    final List<BazarrHistoryItem> many = <BazarrHistoryItem>[
      for (int i = 0; i < 120; i++)
        BazarrHistoryItem(
          title: 'Movie $i',
          action: 1,
          radarrId: i + 1,
          parsedTimestamp:
              '10/12/26 ${(11 - i ~/ 60).toString().padLeft(2, '0')}:'
              '${(59 - i % 60).toString().padLeft(2, '0')}:00',
        ),
    ];
    final FakeBazarrApi api = await pump(
      tester,
      movies: many,
      episodes: const <BazarrHistoryItem>[],
    );

    expect(api.requests, <(bool, int)>[(true, 0), (false, 0)]);
    expect(find.text('Movie 0'), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -6000),
      4000,
    );
    await tester.pumpAndSettle();

    expect(api.requests, contains((true, 50)));
    expect(api.requests.where(((bool, int) r) => !r.$1), hasLength(1));

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -6000),
      4000,
    );
    await tester.pumpAndSettle();

    expect(api.requests, contains((true, 100)));
    expect(find.text('Movie 119'), findsOneWidget);
  });

  testWidgets(
      'the detail sheet shows the stats, and Blacklist only when eligible', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();

    expect(find.text('Downloaded · Oct 12, 2026 10:00'), findsOneWidget);
    for (final String label in <String>[
      'Language',
      'Score',
      'Provider',
      'When',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('English'), findsOneWidget);
    expect(find.text('93%'), findsOneWidget);
    expect(find.text('opensubtitles'), findsOneWidget);
    expect(
      find.text('English subtitles downloaded from opensubtitles.'),
      findsOneWidget,
    );
    expect(find.text('Matched'), findsOneWidget);
    expect(find.text('Release group'), findsOneWidget);
    expect(find.text("Didn't match"), findsOneWidget);
    expect(find.text('Video codec'), findsOneWidget);
    expect(find.text('/movies/Dune/Dune.en.srt'), findsOneWidget);
    expect(find.text('Open movie'), findsOneWidget);
    expect(find.text("On Bazarr's page"), findsOneWidget);
    expect(find.text('Blacklist and search again'), findsOneWidget);

    // Close it and open the sync, which has nothing to blacklist.
    Navigator.of(tester.element(find.text('Language'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Movie'));
    await tester.pumpAndSettle();

    expect(find.text('Synced · sometime'), findsOneWidget);
    expect(find.text('Open movie'), findsOneWidget);
    expect(find.text('Blacklist and search again'), findsNothing);
  });

  testWidgets('confirming the blacklist marks the row at once', (
    WidgetTester tester,
  ) async {
    final FakeBazarrApi api = await pump(tester);
    api.blacklistResult = Completer<void>();

    expect(
      find.byKey(const ValueKey<String>('history-blacklisted')),
      findsNothing,
    );
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blacklist and search again'));
    await tester.pumpAndSettle();

    expect(find.text('Blacklist subtitle'), findsOneWidget);
    expect(
      find.text(
        'Delete the English subtitle from opensubtitles for Dune, block it '
        'from future searches, and look for a replacement?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Blacklist'));
    await tester.pump();

    expect(api.blacklists, hasLength(1));
    final (SubtitleTarget target, String provider, String subsId) =
        api.blacklists.single;
    expect(target, const MovieTarget(4));
    expect(provider, 'opensubtitles');
    expect(subsId, 'abc');
    expect(
      find.byKey(const ValueKey<String>('history-blacklisted')),
      findsOneWidget,
    );

    api.blacklistResult!.complete();
    await tester.pumpAndSettle();

    expect(
      find.text('Blacklisted. Bazarr is looking for another subtitle…'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('history-blacklisted')),
      findsOneWidget,
    );

    // The sheet no longer offers it.
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    expect(find.text('Blacklist and search again'), findsNothing);
  });

  testWidgets('a failing blacklist rolls the mark back', (
    WidgetTester tester,
  ) async {
    final FakeBazarrApi api = await pump(tester);
    api.blacklistResult = Completer<void>();

    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blacklist and search again'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Blacklist'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('history-blacklisted')),
      findsOneWidget,
    );

    api.blacklistResult!.completeError(StateError('refused'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('history-blacklisted')),
      findsNothing,
    );
    expect(find.text("Couldn't blacklist the subtitle"), findsOneWidget);
  });

  testWidgets('Open episode opens the Sonarr series on the episode', (
    WidgetTester tester,
  ) async {
    final FakeArrTargets targets = FakeArrTargets();
    await pump(tester, targets: targets);

    await tester.tap(find.text('Severance · 1x02 · Half Loop'));
    await tester.pumpAndSettle();

    expect(find.text('Open episode'), findsOneWidget);
    expect(
      find.text('Its Subtitles section on the Radarr or Sonarr page'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open episode'));
    await tester.pumpAndSettle();

    // The sheet closed first.
    expect(find.text('Open episode'), findsNothing);
    expect(targets.seriesOpened, <(Instance, int, int?)>[(sonarr, 2, 9)]);
  });
}
