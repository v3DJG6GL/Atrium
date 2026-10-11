import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitle_providers.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitles_bridge.dart';
import 'package:service_bazarr/src/subtitles/ui/series_coverage_card.dart';

import '../support/fake_scheduler.dart';
import 'subtitle_test_support.dart';

const BazarrSubtitlesBridge bridge = BazarrSubtitlesBridge();

SeriesSubtitlesRef seriesRef() => SeriesSubtitlesRef(
      seriesId: 9,
      title: 'Show',
      originalLanguage: 'English',
      episodeInfo: (int id) => id == 201
          ? const EpisodeSubtitlesInfo(
              episodeId: 201,
              season: 2,
              episode: 1,
              title: 'Pilot',
              mediaLine: '1080p · x265',
              audioLanguages: 'eng/ger',
            )
          : null,
    );

void main() {
  late FakeSubtitlesApi api;
  late FakeScheduler scheduler;

  setUp(() {
    api = FakeSubtitlesApi();
    scheduler = FakeScheduler();
  });

  group('bazarrSeriesSubtitlesProvider', () {
    ProviderContainer container(List<Override> overrides) {
      final ProviderContainer c = ProviderContainer(
        overrides: overrides,
        retry: (int _, Object __) => null,
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<SeriesSubtitles> read(
      ProviderContainer c, {
      String sonarrId = 's1',
    }) async {
      final ProviderSubscription<SeriesSubtitles> sub = c.listen(
        bazarrSeriesSubtitlesProvider((sonarrId, 9)),
        (SeriesSubtitles? _, SeriesSubtitles __) {},
      );
      addTearDown(sub.close);
      for (int i = 0; i < 5; i++) {
        await flush();
      }
      return sub.read();
    }

    test('Off when no Bazarr serves the Sonarr', () async {
      final ProviderContainer c = container(
        subtitleOverrides(api: api, scheduler: scheduler, linked: false),
      );
      expect(await read(c), const SeriesSubtitlesOff());
    });

    test('Off for an unknown Sonarr', () async {
      final ProviderContainer c =
          container(subtitleOverrides(api: api, scheduler: scheduler));
      expect(await read(c, sonarrId: 'gone'), const SeriesSubtitlesOff());
    });

    test('Pending while episodes load', () async {
      final ProviderContainer c = container(
        subtitleOverrides(api: api, scheduler: scheduler, episodes: never),
      );
      expect(await read(c), const SeriesSubtitlesPending());
    });

    test('Pending when Bazarr does not list the series', () async {
      final ProviderContainer c = container(
        subtitleOverrides(api: api, scheduler: scheduler, series: () => null),
      );
      expect(await read(c), const SeriesSubtitlesPending());
    });

    test('Pending when Bazarr is unreachable', () async {
      final ProviderContainer c = container(
        subtitleOverrides(
          api: api,
          scheduler: scheduler,
          episodes: () => throw StateError('offline'),
        ),
      );
      expect(await read(c), const SeriesSubtitlesPending());
    });

    test('Ready with tags and gaps per season', () async {
      final ProviderContainer c =
          container(subtitleOverrides(api: api, scheduler: scheduler));
      final SeriesSubtitles s = await read(c);
      expect(s, isA<SeriesSubtitlesReady>());
      final SeriesSubtitlesReady ready = s as SeriesSubtitlesReady;
      expect(ready.gapsBySeason, <int, int>{1: 1, 2: 2});
      expect(ready.seriesGaps, 3);
      expect(ready.episodes.keys, <int>{101, 102, 201, 202, 203});
      expect(
        ready.episodes[101]!.chips.single.state,
        SubtitleState.present,
      );
      expect(
        ready.episodes[102]!.chips.single.state,
        SubtitleState.missing,
      );
    });
  });

  group('coverage section', () {
    Future<void> showSection(WidgetTester tester) async {
      await pumpPage(
        tester,
        bridge.seriesSection(sonarr: sonarr, series: seriesRef()),
        overrides: subtitleOverrides(
          api: api,
          scheduler: scheduler,
          profiles: () => seriesProfiles,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders nothing when not linked', (WidgetTester tester) async {
      await pumpPage(
        tester,
        bridge.seriesSection(sonarr: sonarr, series: seriesRef()),
        overrides:
            subtitleOverrides(api: api, scheduler: scheduler, linked: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subtitles'), findsNothing);
    });

    testWidgets('says when Bazarr does not list the series',
        (WidgetTester tester) async {
      await pumpPage(
        tester,
        bridge.seriesSection(sonarr: sonarr, series: seriesRef()),
        overrides: subtitleOverrides(
          api: api,
          scheduler: scheduler,
          series: () => null,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Bazarr doesn't list this series yet. It picks up new Sonarr "
          'series on its next sync.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('collapsed: progress per profile language',
        (WidgetTester tester) async {
      await showSection(tester);
      expect(find.text('Subtitles'), findsOneWidget);
      // en wanted in all 5 episodes, present in 2.
      expect(find.text('2/5'), findsOneWidget);
      expect(find.text('Language profile'), findsNothing);
    });

    testWidgets(
        'opens on the newest season with gaps; a cell opens its '
        'episode', (WidgetTester tester) async {
      await showSection(tester);
      await tester.tap(find.bySemanticsLabel('Subtitle coverage'));
      await tester.pumpAndSettle();

      final SegmentedButton<int> seasons = tester.widget<SegmentedButton<int>>(
        find.byType(SegmentedButton<int>),
      );
      expect(seasons.selected, <int>{2});
      expect(find.text('Search 2 episodes'), findsOneWidget);
      // The grid paints its cells; their semantics come from the painter.
      expect(find.semantics.byLabel('Episode 1, EN: missing'), findsOne);
      expect(find.semantics.byLabel('Episode 2, EN: subtitle file'), findsOne);

      final Offset origin = tester
          .getTopLeft(find.byKey(const ValueKey<String>('coverage-grid')));
      await tester.tapAt(
        origin +
            const Offset(
              CoverageGridMetrics.cell / 2,
              CoverageGridMetrics.rowsTop + CoverageGridMetrics.cell / 2,
            ),
      );
      await tester.pumpAndSettle();
      expect(find.text('S02E01 subtitles'), findsOneWidget);
      expect(find.text('Pilot · 1080p · x265'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('S1'));
      await tester.pumpAndSettle();
      expect(find.text('Search 1 episode'), findsOneWidget);
    });
  });

  group('episode sheet', () {
    Future<void> openSheet(WidgetTester tester, {int episodeId = 201}) async {
      await pumpPage(
        tester,
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => bridge.openEpisode(
              context,
              sonarr: sonarr,
              series: seriesRef(),
              episodeId: episodeId,
            ),
            child: const Text('open'),
          ),
        ),
        overrides: subtitleOverrides(
          api: api,
          scheduler: scheduler,
          profiles: () => seriesProfiles,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('steps through the episodes with gaps',
        (WidgetTester tester) async {
      await openSheet(tester);
      expect(find.text('S02E01 subtitles'), findsOneWidget);
      expect(
        find.text('English · original'),
        findsNothing,
        reason: 'two audio tracks',
      );
      expect(
        find.bySemanticsLabel('Audio: English (original), German'),
        findsOneWidget,
      );
      expect(find.text('S01E02'), findsOneWidget);
      expect(find.text('S02E03'), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel('Next episode with missing subtitles'),
      );
      await tester.pumpAndSettle();
      expect(find.text('S02E03 subtitles'), findsOneWidget);
      expect(find.text('No later gaps'), findsOneWidget);
      expect(find.text('S02E01'), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel('Previous episode with missing subtitles'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel('Previous episode with missing subtitles'),
      );
      await tester.pumpAndSettle();
      expect(find.text('S01E02 subtitles'), findsOneWidget);
      expect(find.text('No earlier gaps'), findsOneWidget);
    });

    testWidgets('confirmations show inside the sheet',
        (WidgetTester tester) async {
      await openSheet(tester);
      await tester.tap(find.bySemanticsLabel('Search English subtitles'));
      await settle(tester);
      expect(api.calls, <String>['search e201 en']);
      expect(find.text('Searching English subtitles…'), findsOneWidget);
      expect(find.text('S02E01 subtitles'), findsOneWidget);
    });
  });

  group('bulk searches', () {
    Future<BuildContext> host(WidgetTester tester) async {
      late BuildContext captured;
      await pumpPage(
        tester,
        Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
        overrides: subtitleOverrides(api: api, scheduler: scheduler),
      );
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('a season searches each missing language of its episodes',
        (WidgetTester tester) async {
      final BuildContext context = await host(tester);
      await bridge.searchSeasonMissing(
        context,
        sonarr: sonarr,
        seriesId: 9,
        season: 2,
      );
      await settle(tester);
      expect(api.calls, <String>['search e201 en', 'search e203 en']);
      expect(find.text('Searching subtitles for 2 episodes…'), findsOneWidget);
    });

    testWidgets('a series search blocks a season search while it runs',
        (WidgetTester tester) async {
      api.answer = never;
      final BuildContext context = await host(tester);
      final Future<void> series = bridge.searchSeriesMissing(
        context,
        sonarr: sonarr,
        series: seriesRef(),
      );
      await tester.pump();
      await bridge.searchSeasonMissing(
        context,
        sonarr: sonarr,
        seriesId: 9,
        season: 1,
      );
      await settle(tester);
      expect(api.calls, <String>['search-missing s9']);
      expect(find.text('That search is still running'), findsOneWidget);
      expect(series, isA<Future<void>>());
    });

    testWidgets('a failed series search says so', (WidgetTester tester) async {
      api.answer = () async => throw StateError('offline');
      final BuildContext context = await host(tester);
      await bridge.searchSeriesMissing(
        context,
        sonarr: sonarr,
        series: seriesRef(),
      );
      await settle(tester);
      expect(find.text("Couldn't start the search"), findsOneWidget);
    });

    testWidgets('a series search names the show', (WidgetTester tester) async {
      final BuildContext context = await host(tester);
      await bridge.searchSeriesMissing(
        context,
        sonarr: sonarr,
        series: seriesRef(),
      );
      await settle(tester);
      expect(
        find.text('Searching missing subtitles for Show…'),
        findsOneWidget,
      );
    });
  });

  group('refresh', () {
    test('refetches the movie of the asking Radarr', () async {
      int fetches = 0;
      final ProviderContainer c = ProviderContainer(
        overrides: subtitleOverrides(
          api: api,
          scheduler: scheduler,
          overrideItems: false,
        ),
        retry: (int _, Object __) => null,
      );
      addTearDown(c.dispose);
      api.onGetMovie = () => fetches++;
      final ProviderSubscription<AsyncValue<BazarrMovie?>> sub = c.listen(
        bazarrMovieItemProvider((bazarr, 42)),
        (AsyncValue<BazarrMovie?>? _, AsyncValue<BazarrMovie?> __) {},
      );
      addTearDown(sub.close);
      await c.read(bazarrMovieItemProvider((bazarr, 42)).future);
      expect(fetches, 1);

      bridge.refresh(radarr, 7);
      await flush();
      expect(fetches, 1, reason: 'another movie');

      bridge.refresh(radarr, 42);
      await c.read(bazarrMovieItemProvider((bazarr, 42)).future);
      expect(fetches, 2);
    });
  });
}
