import 'package:core_models/core_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_radarr/service_radarr.dart';

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

  const movies = <RadarrMovie>[
    RadarrMovie(id: 1, title: 'Amélie', year: 2001),
    RadarrMovie(id: 2, title: 'Dune', year: 1984),
    RadarrMovie(id: 3, title: 'Dune', year: 2021),
    RadarrMovie(id: 4, title: 'The Matrix', sortTitle: 'matrix', year: 1999),
  ];

  Future<List<int>> search(String query) async {
    final container = ProviderContainer(
      overrides: [
        radarrMoviesProvider(instance).overrideWith((ref) async => movies),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      radarrFilteredMoviesProvider(instance),
      (_, __) {},
    );
    addTearDown(sub.close);
    container.read(radarrSearchQueryProvider(instance).notifier).state = query;
    await container.read(radarrMoviesProvider(instance).future);
    return container
        .read(radarrFilteredMoviesProvider(instance))
        .requireValue
        .map((RadarrMovie m) => m.id)
        .toList();
  }

  group('radarrFilteredMoviesProvider search', () {
    test('finds an accented title typed without accents', () async {
      expect(await search('amelie'), <int>[1]);
    });

    test('narrows by a trailing year', () async {
      expect(await search('dune 1984'), <int>[2]);
    });

    test('keeps everything without a query', () async {
      expect(await search(''), hasLength(4));
    });
  });

  test('the search index is only built while a query is active', () async {
    final container = ProviderContainer(
      overrides: [
        radarrMoviesProvider(instance).overrideWith((ref) async => movies),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      radarrFilteredMoviesProvider(instance),
      (_, __) {},
    );
    addTearDown(sub.close);
    await container.read(radarrMoviesProvider(instance).future);
    container.read(radarrFilteredMoviesProvider(instance));
    expect(container.exists(radarrSearchIndexProvider(instance)), isFalse);

    container.read(radarrSearchQueryProvider(instance).notifier).state = 'dune';
    container.read(radarrFilteredMoviesProvider(instance));
    expect(container.exists(radarrSearchIndexProvider(instance)), isTrue);
  });
}
