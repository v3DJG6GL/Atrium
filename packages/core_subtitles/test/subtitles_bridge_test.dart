import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const _sonarr = Instance(
  id: 'sonarr-1',
  name: 'Sonarr',
  kind: ServiceKind.sonarr,
  localUrl: 'http://sonarr.local:8989',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuth.apiKey(apiKey: 'k'),
);

const _radarr = Instance(
  id: 'radarr-1',
  name: 'Radarr',
  kind: ServiceKind.radarr,
  localUrl: 'http://radarr.local:7878',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuth.apiKey(apiKey: 'k'),
);

const _movie = MovieSubtitlesRef(radarrId: 7, title: 'Film');

const _ready = SeriesSubtitlesReady(
  episodes: {
    101: EpisodeSubtitleTags(
      chips: [
        SubtitleChip(
          key: 'en|',
          code2: 'en',
          forced: false,
          hi: false,
          state: SubtitleState.present,
        ),
      ],
    ),
  },
  gapsBySeason: {1: 0},
  seriesGaps: 0,
);

final _readyProvider = Provider<SeriesSubtitles>((ref) => _ready);

class _FakeBridge extends SubtitlesBridge {
  const _FakeBridge();

  @override
  Widget movieSection({
    required Instance radarr,
    required MovieSubtitlesRef movie,
  }) =>
      Text('Subtitles for ${movie.title}');

  @override
  ProviderListenable<SeriesSubtitles> series(Instance sonarr, int seriesId) =>
      _readyProvider;
}

void main() {
  test('the default bridge renders nothing', () {
    const bridge = NoSubtitlesBridge();
    final movie = bridge.movieSection(radarr: _radarr, movie: _movie);
    final series = bridge.seriesSection(
      sonarr: _sonarr,
      series: const SeriesSubtitlesRef(seriesId: 1, title: 'Show'),
    );
    for (final w in [movie, series]) {
      expect(w, isA<SizedBox>());
      expect((w as SizedBox).width, 0);
      expect(w.height, 0);
    }
  });

  test('the default bridge reports subtitles off', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final bridge = container.read(subtitlesBridgeProvider);
    expect(bridge, isA<NoSubtitlesBridge>());
    expect(
      container.read(bridge.series(_sonarr, 1)),
      const SeriesSubtitlesOff(),
    );
  });

  test('an override replaces the bridge', () {
    final container = ProviderContainer(
      overrides: [
        subtitlesBridgeProvider.overrideWithValue(const _FakeBridge()),
      ],
    );
    addTearDown(container.dispose);
    final bridge = container.read(subtitlesBridgeProvider);
    expect(container.read(bridge.series(_sonarr, 1)), _ready);
  });

  testWidgets('screens render the overriding bridge', (tester) async {
    Widget page() => MaterialApp(
          theme: ThemeData(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ref
                  .watch(subtitlesBridgeProvider)
                  .movieSection(radarr: _radarr, movie: _movie),
            ),
          ),
        );

    await tester.pumpWidget(ProviderScope(child: page()));
    expect(find.text('Subtitles for Film'), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          subtitlesBridgeProvider.overrideWithValue(const _FakeBridge()),
        ],
        child: page(),
      ),
    );
    expect(find.text('Subtitles for Film'), findsOneWidget);
  });

  test('series refs ignore the episode lookup in ==', () {
    final a = SeriesSubtitlesRef(
      seriesId: 1,
      title: 'Show',
      episodeInfo: (_) => null,
    );
    final b = SeriesSubtitlesRef(
      seriesId: 1,
      title: 'Show',
      episodeInfo: (_) => null,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
