import 'dart:io';

import 'package:core_storage/core_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/library/bazarr_library_logic.dart';
import 'package:service_bazarr/src/library/bazarr_library_providers.dart';

import '../subtitles/subtitle_test_support.dart';

void main() {
  group('view mode', () {
    late Directory tempDir;
    late Box<String> box;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bazarr_library_view');
      Hive.init(tempDir.path);
      box = await Hive.openBox<String>(AtriumBoxes.settings);
    });

    tearDown(() async {
      await box.clear();
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('starts as a list', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(
          bazarrLibraryViewModeProvider((bazarr, BazarrLibraryKind.movies)),
        ),
        BazarrLibraryViewMode.list,
      );
    });

    test('is kept per kind across restarts', () {
      final ProviderContainer first = ProviderContainer();
      first
          .read(
            bazarrLibraryViewModeProvider((bazarr, BazarrLibraryKind.series))
                .notifier,
          )
          .toggle();
      first.dispose();
      expect(box.get('bazarr.libraryView.b1.series'), 'posters');

      final ProviderContainer second = ProviderContainer();
      addTearDown(second.dispose);
      expect(
        second.read(
          bazarrLibraryViewModeProvider((bazarr, BazarrLibraryKind.series)),
        ),
        BazarrLibraryViewMode.posters,
      );
      expect(
        second.read(
          bazarrLibraryViewModeProvider((bazarr, BazarrLibraryKind.movies)),
        ),
        BazarrLibraryViewMode.list,
      );
    });

    test('ignores a stored value it does not know', () async {
      await box.put('bazarr.libraryView.b1.movies', 'mosaic');
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(
          bazarrLibraryViewModeProvider((bazarr, BazarrLibraryKind.movies)),
        ),
        BazarrLibraryViewMode.list,
      );
    });
  });

  group('library state', () {
    late ProviderContainer c;
    BazarrLibraryUi ui() => c.read(bazarrLibraryUiProvider(bazarr).notifier);
    BazarrLibraryUiState state() => c.read(bazarrLibraryUiProvider(bazarr));

    setUp(() {
      c = ProviderContainer();
      addTearDown(c.dispose);
    });

    test('keeps a chip per kind and drops the language filter on a switch',
        () {
      ui()
        ..setFilter(LibraryFilter.missing)
        ..cycleLanguage('en')
        ..setKind(BazarrLibraryKind.series);
      expect(state().filter, LibraryFilter.all);
      expect(state().languageFilter, isNull);

      ui()
        ..setFilter(LibraryFilter.complete)
        ..setKind(BazarrLibraryKind.movies);
      expect(state().filter, LibraryFilter.missing);
      expect(state().seriesFilter, LibraryFilter.complete);
    });

    test('collapses expanded rows on a filter or kind change', () {
      ui()
        ..setKind(BazarrLibraryKind.series)
        ..setFilter(LibraryFilter.missing)
        ..toggleExpanded(9);
      expect(state().expanded, <int>{9});
      ui().setFilter(LibraryFilter.all);
      expect(state().expanded, isEmpty);

      ui().toggleExpanded(9);
      ui().setKind(BazarrLibraryKind.movies);
      expect(state().expanded, isEmpty);
    });

    test('re-selecting the kind on screen changes nothing', () {
      ui().cycleLanguage('en');
      ui().setKind(BazarrLibraryKind.movies);
      expect(
        state().languageFilter,
        const LanguageFilter('en', LanguageShow.missing),
      );
    });

    test('"Clear filters" resets the chip, the language and the search', () {
      ui()
        ..setFilter(LibraryFilter.noProfile)
        ..cycleLanguage('de')
        ..setQuery('dune');
      expect(state().filtered, isTrue);
      ui().clearFilters();
      expect(state().filter, LibraryFilter.all);
      expect(state().languageFilter, isNull);
      expect(state().query, isEmpty);
      expect(state().filtered, isFalse);
    });
  });
}
