import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_radarr/service_radarr.dart';

/// A bridge that renders a marker and records what the page passed it.
class _FakeBridge extends SubtitlesBridge {
  final List<MovieSubtitlesRef> movies = [];
  final List<(Instance, int)> refreshes = [];

  @override
  Widget movieSection({
    required Instance radarr,
    required MovieSubtitlesRef movie,
  }) {
    movies.add(movie);
    return const Text('fake-subtitles');
  }

  @override
  void refresh(Instance arr, int itemId) => refreshes.add((arr, itemId));
}

void main() {
  const instance = Instance(
    id: 'radarr-test-1',
    name: 'Radarr Test',
    kind: ServiceKind.radarr,
    localUrl: 'http://localhost:7878',
    externalUrl: '',
    urlMode: UrlMode.auto,
    auth: InstanceAuthApiKey(apiKey: 'test-key'),
  );

  const movieWithFile = RadarrMovie(
    id: 10,
    tmdbId: 101,
    title: 'Gladiator II',
    hasFile: true,
    inCinemas: '2024-11-22T00:00:00Z',
    originalLanguage: RadarrLanguage(id: 1, name: 'English'),
    movieFile: RadarrMovieFile(
      id: 7,
      relativePath: 'Gladiator II (2024).mkv',
      size: 1024,
      mediaInfo: RadarrMediaInfo(
        audioLanguages: 'English/German',
        videoFps: 23.976,
      ),
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    RadarrMovie movie, {
    SubtitlesBridge? bridge,
    bool expandSubtitles = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          radarrMovieByIdProvider((instance, movie.id))
              .overrideWith((ref) => movie),
          if (bridge != null) subtitlesBridgeProvider.overrideWithValue(bridge),
        ],
        child: MaterialApp(
          home: MovieDetailScreen(
            instance: instance,
            movieId: movie.id,
            movie: movie,
            expandSubtitles: expandSubtitles,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('RadarrMovie.movieFile', () {
    test('reads the media info with an int or a double frame rate', () {
      final asDouble = RadarrMovie.fromJson(<String, dynamic>{
        'id': 1,
        'title': 'A',
        'movieFile': <String, dynamic>{
          'id': 3,
          'relativePath': 'A.mkv',
          'size': 2048,
          'mediaInfo': <String, dynamic>{
            'audioLanguages': 'English/German',
            'videoFps': 23.976,
            'subtitles': 'English',
          },
        },
      });
      expect(asDouble.movieFile?.id, 3);
      expect(asDouble.movieFile?.relativePath, 'A.mkv');
      expect(asDouble.movieFile?.size, 2048);
      expect(asDouble.movieFile?.mediaInfo?.audioLanguages, 'English/German');
      expect(asDouble.movieFile?.mediaInfo?.videoFps, 23.976);
      expect(asDouble.movieFile?.mediaInfo?.subtitles, 'English');

      final asInt = RadarrMovie.fromJson(<String, dynamic>{
        'id': 1,
        'title': 'A',
        'movieFile': <String, dynamic>{
          'id': 3,
          'mediaInfo': <String, dynamic>{'videoFps': 25},
        },
      });
      expect(asInt.movieFile?.mediaInfo?.videoFps, 25.0);
      expect(asInt.movieFile?.mediaInfo?.videoFps, isA<double>());
    });

    test('is absent without a file', () {
      final movie =
          RadarrMovie.fromJson(<String, dynamic>{'id': 1, 'title': 'A'});
      expect(movie.movieFile, isNull);
    });

    test('is never serialised back to Radarr', () {
      final json = movieWithFile.toJson();
      expect(json.containsKey('movieFile'), isFalse);
      expect(json['title'], 'Gladiator II');
    });
  });

  group('MovieDetailScreen subtitles section', () {
    testWidgets('the default bridge adds nothing', (tester) async {
      await pump(tester, movieWithFile);

      expect(find.text('File Information'), findsOneWidget);
      expect(find.text('Release Dates'), findsOneWidget);
      expect(find.text('Subtitles'), findsNothing);
      expect(find.text('fake-subtitles'), findsNothing);
    });

    testWidgets('renders the bridge section between the file and release dates',
        (tester) async {
      final bridge = _FakeBridge();
      await pump(tester, movieWithFile, bridge: bridge);

      final section = find.text('fake-subtitles');
      expect(section, findsOneWidget);
      final double fileY = tester.getTopLeft(find.text('File Information')).dy;
      final double sectionY = tester.getTopLeft(section).dy;
      final double datesY = tester.getTopLeft(find.text('Release Dates')).dy;
      expect(sectionY, greaterThan(fileY));
      expect(sectionY, lessThan(datesY));

      expect(
        bridge.movies.last,
        const MovieSubtitlesRef(
          radarrId: 10,
          title: 'Gladiator II',
          audioLanguages: 'English/German',
          videoFps: 23.976,
          originalLanguage: 'English',
        ),
      );
    });

    testWidgets('opens the section expanded when asked to', (tester) async {
      final bridge = _FakeBridge();
      await pump(tester, movieWithFile, bridge: bridge, expandSubtitles: true);

      expect(bridge.movies, isNotEmpty);
      expect(bridge.movies.last.expanded, isTrue);
      expect(bridge.movies.last.radarrId, 10);
    });

    testWidgets('skips the section when the movie has no file', (tester) async {
      final bridge = _FakeBridge();
      await pump(
        tester,
        movieWithFile.copyWith(hasFile: false, movieFile: null),
        bridge: bridge,
      );

      expect(find.text('File Information'), findsOneWidget);
      expect(find.text('fake-subtitles'), findsNothing);
      expect(bridge.movies, isEmpty);
    });
  });
}
