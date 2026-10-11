import 'package:core_models/core_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_sonarr/service_sonarr.dart';

void main() {
  const instance = Instance(
    id: 'sonarr-test-1',
    name: 'Sonarr Test',
    kind: ServiceKind.sonarr,
    localUrl: 'http://localhost:8989',
    externalUrl: '',
    urlMode: UrlMode.auto,
    auth: InstanceAuthApiKey(apiKey: 'test-key'),
  );

  const series = <SonarrSeries>[
    SonarrSeries(id: 1, title: 'Amélie', year: 2001),
    SonarrSeries(id: 2, title: 'Dune', year: 1984),
    SonarrSeries(id: 3, title: 'Dune', year: 2021),
    SonarrSeries(id: 4, title: 'The Office', sortTitle: 'office', year: 0),
  ];

  Future<List<int>> search(String query) async {
    final container = ProviderContainer(
      overrides: [
        sonarrSeriesProvider(instance).overrideWith((ref) async => series),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      sonarrFilteredSeriesProvider(instance),
      (_, __) {},
    );
    addTearDown(sub.close);
    container.read(sonarrSearchQueryProvider(instance).notifier).state = query;
    await container.read(sonarrSeriesProvider(instance).future);
    return container
        .read(sonarrFilteredSeriesProvider(instance))
        .requireValue
        .map((SonarrSeries s) => s.id)
        .toList();
  }

  group('sonarrFilteredSeriesProvider search', () {
    test('finds an accented title typed without accents', () async {
      expect(await search('amelie'), <int>[1]);
    });

    test('narrows by a trailing year', () async {
      expect(await search('dune 1984'), <int>[2]);
    });

    test("doesn't let a trailing year hide a series with year 0", () async {
      expect(await search('office 2005'), <int>[4]);
    });

    test('keeps everything without a query', () async {
      expect(await search(''), hasLength(4));
    });
  });

  test('the search index is only built while a query is active', () async {
    final container = ProviderContainer(
      overrides: [
        sonarrSeriesProvider(instance).overrideWith((ref) async => series),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      sonarrFilteredSeriesProvider(instance),
      (_, __) {},
    );
    addTearDown(sub.close);
    await container.read(sonarrSeriesProvider(instance).future);
    container.read(sonarrFilteredSeriesProvider(instance));
    expect(container.exists(sonarrSearchIndexProvider(instance)), isFalse);

    container.read(sonarrSearchQueryProvider(instance).notifier).state = 'dune';
    container.read(sonarrFilteredSeriesProvider(instance));
    expect(container.exists(sonarrSearchIndexProvider(instance)), isTrue);
  });
}
