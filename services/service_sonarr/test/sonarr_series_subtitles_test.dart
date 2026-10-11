import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_sonarr/service_sonarr.dart';

/// A bridge serving fixed subtitle data and recording what the page asks.
class _FakeBridge extends SubtitlesBridge {
  _FakeBridge(this.state);

  final SeriesSubtitles state;
  late final Provider<SeriesSubtitles> _provider =
      Provider<SeriesSubtitles>((ref) => state);

  SeriesSubtitlesRef? lastRef;
  final List<int> openedEpisodes = [];
  final List<int> seasonSearches = [];
  int seriesSearches = 0;
  final List<int> refreshes = [];

  @override
  Widget seriesSection({
    required Instance sonarr,
    required SeriesSubtitlesRef series,
  }) {
    lastRef = series;
    return const Text('fake-coverage');
  }

  @override
  ProviderListenable<SeriesSubtitles> series(Instance sonarr, int seriesId) =>
      _provider;

  @override
  Future<void> openEpisode(
    BuildContext context, {
    required Instance sonarr,
    required SeriesSubtitlesRef series,
    required int episodeId,
  }) async =>
      openedEpisodes.add(episodeId);

  @override
  Future<void> searchSeasonMissing(
    BuildContext context, {
    required Instance sonarr,
    required int seriesId,
    required int season,
  }) async =>
      seasonSearches.add(season);

  @override
  Future<void> searchSeriesMissing(
    BuildContext context, {
    required Instance sonarr,
    required SeriesSubtitlesRef series,
  }) async =>
      seriesSearches++;

  @override
  void refresh(Instance arr, int itemId) => refreshes.add(itemId);
}

/// A [_FakeBridge] whose series data can change while the page is open.
class _LiveBridge extends _FakeBridge {
  _LiveBridge(this.live) : super(live.value);

  final ValueNotifier<SeriesSubtitles> live;
  late final Provider<SeriesSubtitles> _live = Provider<SeriesSubtitles>((ref) {
    void changed() => ref.invalidateSelf();
    live.addListener(changed);
    ref.onDispose(() => live.removeListener(changed));
    return live.value;
  });

  @override
  ProviderListenable<SeriesSubtitles> series(Instance sonarr, int seriesId) =>
      _live;
}

const _instance = Instance(
  id: 'sonarr-1',
  name: 'Sonarr Test',
  kind: ServiceKind.sonarr,
  localUrl: 'http://localhost:8989',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'dummy-api-key'),
);

const _series = SonarrSeries(
  id: 1,
  title: 'The Show',
  path: '/tv/The Show',
  originalLanguage: SonarrLanguage(id: 1, name: 'English'),
  seasons: [
    SonarrSeason(seasonNumber: 1, monitored: true),
    SonarrSeason(seasonNumber: 2, monitored: true),
  ],
);

Map<String, dynamic> _file(int id) => <String, dynamic>{
      'id': id,
      'size': 1000000,
      'relativePath': 'Season 1/The Show - S01E0$id.mkv',
      'mediaInfo': <String, dynamic>{
        'audioLanguages': 'English/German',
        'audioCodec': 'EAC3',
        'audioChannels': 5.1,
        'videoCodec': 'x264',
        'videoFps': 25,
        'resolution': '1920x1080',
      },
    };

final _episodes = <SonarrEpisode>[
  SonarrEpisode(
    id: 101,
    seriesId: 1,
    seasonNumber: 1,
    episodeNumber: 1,
    title: 'Pilot',
    hasFile: true,
    episodeFileId: 1,
    episodeFile: _file(1),
  ),
  SonarrEpisode(
    id: 102,
    seriesId: 1,
    seasonNumber: 1,
    episodeNumber: 2,
    title: 'Second',
    hasFile: true,
    episodeFileId: 2,
    episodeFile: _file(2),
  ),
  const SonarrEpisode(
    id: 103,
    seriesId: 1,
    seasonNumber: 1,
    episodeNumber: 3,
    title: 'Unaired',
  ),
  SonarrEpisode(
    id: 201,
    seriesId: 1,
    seasonNumber: 2,
    episodeNumber: 1,
    title: 'Return',
    hasFile: true,
    episodeFileId: 3,
    episodeFile: _file(3),
  ),
];

const _tags = EpisodeSubtitleTags(
  chips: [
    SubtitleChip(
      key: 'en|',
      code2: 'en',
      forced: false,
      hi: false,
      state: SubtitleState.present,
    ),
    SubtitleChip(
      key: 'de|',
      code2: 'de',
      forced: false,
      hi: false,
      state: SubtitleState.missing,
    ),
  ],
);

const _ready = SeriesSubtitlesReady(
  episodes: {101: _tags, 102: _tags, 201: _tags},
  gapsBySeason: {1: 2, 2: 1},
  seriesGaps: 3,
);

Future<void> _pump(
  WidgetTester tester, {
  SubtitlesBridge? bridge,
  int? openEpisodeSubtitles,
}) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Never resolves: nothing here should reach the network.
        sonarrApiProvider(_instance)
            .overrideWith((ref) => Completer<SonarrApi>().future),
        sonarrSeriesByIdProvider((_instance, 1))
            .overrideWith((ref) async => _series),
        sonarrEpisodesProvider((_instance, 1))
            .overrideWith((ref) async => _episodes),
        sonarrQueueProvider(_instance)
            .overrideWith((ref) async => <SonarrQueueItem>[]),
        if (bridge != null) subtitlesBridgeProvider.overrideWithValue(bridge),
      ],
      child: MaterialApp(
        home: SeriesDetailScreen(
          instance: _instance,
          series: _series,
          openEpisodeSubtitles: openEpisodeSubtitles,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expandSeason1(WidgetTester tester) async {
  // The last match is the season card's header (the first is its chip).
  await tester.tap(find.text('Season 1').last);
  await tester.pumpAndSettle();
}

Future<void> _openOverflow(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
}

Future<void> _openEpisodeSheet(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  expect(find.text('Overview'), findsOneWidget);
}

void main() {
  group('with the default bridge', () {
    testWidgets('nothing about subtitles appears', (tester) async {
      await _pump(tester);

      expect(find.text('fake-coverage'), findsNothing);
      expect(find.byType(SeasonGapBadge), findsNothing);

      await _expandSeason1(tester);
      expect(find.text('Pilot'), findsOneWidget);
      expect(find.byType(LanguageLines), findsNothing);

      await _openOverflow(tester);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Search missing subtitles'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await _openEpisodeSheet(tester, 'Pilot');
      expect(find.text('Subtitles'), findsNothing);
    });
  });

  group('with a Bazarr serving the series', () {
    testWidgets('shows the coverage section between info and seasons',
        (tester) async {
      final bridge = _FakeBridge(_ready);
      await _pump(tester, bridge: bridge);

      final double pathY = tester.getTopLeft(find.text('Path')).dy;
      final double coverageY = tester.getTopLeft(find.text('fake-coverage')).dy;
      final double seasonsY =
          tester.getTopLeft(find.text('Seasons & Episodes')).dy;
      expect(coverageY, greaterThan(pathY));
      expect(coverageY, lessThan(seasonsY));

      final SeriesSubtitlesRef ref = bridge.lastRef!;
      expect(ref.seriesId, 1);
      expect(ref.title, 'The Show');
      expect(ref.originalLanguage, 'English');
      expect(
        ref.episodeInfo!(102),
        const EpisodeSubtitlesInfo(
          episodeId: 102,
          season: 1,
          episode: 2,
          title: 'Second',
          mediaLine: '1080p · x264 · EAC3 5.1',
          audioLanguages: 'English/German',
          videoFps: 25,
        ),
      );
      expect(ref.episodeInfo!(103)?.mediaLine, isNull);
      expect(ref.episodeInfo!(999), isNull);
    });

    testWidgets('each season header shows its gap count', (tester) async {
      final bridge = _FakeBridge(_ready);
      await _pump(tester, bridge: bridge);

      final season1Card = find.ancestor(
        of: find.text('Season 1').last,
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(
          of: season1Card.first,
          matching: find.byWidgetPredicate(
            (w) => w is SeasonGapBadge && w.gaps == 2,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SeasonGapBadge),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      // Tapping the badge opens its menu, not the season.
      await tester.tap(
        find
            .ancestor(
              of: find.byWidgetPredicate(
                (w) => w is SeasonGapBadge && w.gaps == 2,
              ),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Pilot'), findsNothing);
      expect(find.text('Search missing subtitles'), findsOneWidget);
      expect(find.text('2 episodes missing a language'), findsOneWidget);

      await tester.tap(find.text('Search missing subtitles'));
      await tester.pumpAndSettle();
      expect(bridge.seasonSearches, [1]);
    });

    testWidgets('episode rows show their languages and open the subtitles',
        (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final bridge = _FakeBridge(_ready);
      await _pump(tester, bridge: bridge);
      await _expandSeason1(tester);

      // Two downloaded episodes in season 1; the third has no file.
      expect(find.byType(LanguageLines), findsNWidgets(2));
      expect(find.bySemanticsLabel('S01E02 subtitles'), findsOneWidget);
      expect(find.byType(AudioPill), findsWidgets);

      await tester.tap(find.bySemanticsLabel('S01E02 subtitles'));
      await tester.pumpAndSettle();
      expect(bridge.openedEpisodes, [102]);
      // The row's own sheet stayed closed.
      expect(find.text('Overview'), findsNothing);
      semantics.dispose();
    });

    testWidgets('the overflow menu searches the whole series', (tester) async {
      final bridge = _FakeBridge(_ready);
      await _pump(tester, bridge: bridge);

      await _openOverflow(tester);
      expect(find.text('Search missing subtitles'), findsOneWidget);
      expect(find.text('3 episodes missing a language'), findsOneWidget);

      await tester.tap(find.text('Search missing subtitles'));
      await tester.pumpAndSettle();
      expect(bridge.seriesSearches, 1);
    });

    testWidgets('the episode sheet opens the episode subtitles',
        (tester) async {
      final bridge = _FakeBridge(_ready);
      await _pump(tester, bridge: bridge);
      await _expandSeason1(tester);

      await _openEpisodeSheet(tester, 'Pilot');
      expect(find.text('Subtitles'), findsOneWidget);

      await tester.tap(find.text('Subtitles'));
      await tester.pumpAndSettle();
      expect(bridge.openedEpisodes, [101]);
      expect(find.text('Overview'), findsNothing);
    });

    testWidgets('the episode sheet skips episodes Bazarr does not list',
        (tester) async {
      final bridge = _FakeBridge(_ready);
      await _pump(tester, bridge: bridge);
      await _expandSeason1(tester);

      await _openEpisodeSheet(tester, 'Unaired');
      expect(find.text('Subtitles'), findsNothing);
    });

    testWidgets('while pending, the overflow item is disabled', (tester) async {
      final bridge = _FakeBridge(const SeriesSubtitlesPending());
      await _pump(tester, bridge: bridge);

      expect(find.byType(SeasonGapBadge), findsNothing);

      await _openOverflow(tester);
      expect(find.text('Search missing subtitles'), findsOneWidget);
      expect(find.text('Nothing missing'), findsOneWidget);
      final item = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('Search missing subtitles'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(item.enabled, isFalse);
    });
  });

  group('when no Bazarr serves the Sonarr', () {
    testWidgets('no subtitle UI appears', (tester) async {
      final bridge = _FakeBridge(const SeriesSubtitlesOff());
      await _pump(tester, bridge: bridge);

      expect(find.byType(SeasonGapBadge), findsNothing);

      await _expandSeason1(tester);
      expect(find.byType(LanguageLines), findsNothing);

      await _openOverflow(tester);
      expect(find.text('Search missing subtitles'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await _openEpisodeSheet(tester, 'Pilot');
      expect(find.text('Subtitles'), findsNothing);
    });
  });

  group('openEpisodeSubtitles', () {
    testWidgets('opens the episode sheet once the data lists the episode',
        (tester) async {
      final bridge = _FakeBridge(_ready);
      await _pump(tester, bridge: bridge, openEpisodeSubtitles: 102);

      expect(bridge.openedEpisodes, [102]);
    });

    testWidgets('does nothing when no Bazarr serves the Sonarr',
        (tester) async {
      final bridge = _FakeBridge(const SeriesSubtitlesOff());
      await _pump(tester, bridge: bridge, openEpisodeSubtitles: 102);

      expect(bridge.openedEpisodes, isEmpty);
    });

    testWidgets('waits for the data, then opens only once across rebuilds',
        (tester) async {
      final live =
          ValueNotifier<SeriesSubtitles>(const SeriesSubtitlesPending());
      addTearDown(live.dispose);
      final bridge = _LiveBridge(live);
      await _pump(tester, bridge: bridge, openEpisodeSubtitles: 201);
      expect(bridge.openedEpisodes, isEmpty);

      live.value = _ready;
      await tester.pumpAndSettle();
      expect(bridge.openedEpisodes, [201]);

      // Fresher data rebuilds the page; the sheet doesn't open again.
      live.value = const SeriesSubtitlesReady(
        episodes: {101: _tags, 102: _tags, 201: _tags},
        gapsBySeason: {1: 1, 2: 1},
        seriesGaps: 2,
      );
      await tester.pumpAndSettle();
      await _expandSeason1(tester);
      expect(bridge.openedEpisodes, [201]);
    });
  });
}
