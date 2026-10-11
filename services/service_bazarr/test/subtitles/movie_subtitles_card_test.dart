import 'dart:typed_data';

import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitles_bridge.dart';
import 'package:service_bazarr/src/subtitles/ui/movie_subtitles_card.dart';
import 'package:service_bazarr/src/subtitles/ui/subtitle_sheet.dart';
import 'package:service_bazarr/src/subtitles/ui/subtitles_section.dart';
import 'package:service_bazarr/src/subtitles/ui/upload_subtitle_sheet.dart';

import '../support/fake_scheduler.dart';
import 'subtitle_test_support.dart';

void main() {
  late FakeSubtitlesApi api;
  late FakeScheduler scheduler;

  setUp(() {
    api = FakeSubtitlesApi();
    scheduler = FakeScheduler();
  });

  Widget section() => const BazarrSubtitlesBridge().movieSection(
        radarr: radarr,
        movie: const MovieSubtitlesRef(
          radarrId: 42,
          title: 'Film',
          audioLanguages: 'eng',
          videoFps: 25,
          originalLanguage: 'English',
        ),
      );

  Future<void> show(
    WidgetTester tester, {
    List<Override>? overrides,
  }) async {
    await pumpPage(
      tester,
      section(),
      overrides: overrides ?? subtitleOverrides(api: api, scheduler: scheduler),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders nothing when no Bazarr serves the Radarr',
      (WidgetTester tester) async {
    await show(
      tester,
      overrides: subtitleOverrides(
        api: api,
        scheduler: scheduler,
        linked: false,
      ),
    );
    expect(find.text('Subtitles'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('shows a skeleton while loading', (WidgetTester tester) async {
    await pumpPage(
      tester,
      section(),
      overrides: subtitleOverrides(
        api: api,
        scheduler: scheduler,
        movie: never,
      ),
    );
    await tester.pump();
    expect(find.text('Subtitles'), findsOneWidget);
    expect(find.text('Bazarr'), findsOneWidget);
    expect(find.byType(SubtitlesSkeleton), findsOneWidget);
  });

  testWidgets('keeps the chips compact and the Bazarr name at the end',
      (WidgetTester tester) async {
    await show(tester);
    final Finder chips = find.byType(SubtitleTrackChip);
    expect(chips, findsWidgets);
    for (final Element chip in chips.evaluate()) {
      expect(tester.getSize(find.byWidget(chip.widget)).width, lessThan(80));
    }
    expect(
      tester.getTopRight(find.text('Bazarr')).dx,
      moreOrLessEquals(
        tester.getTopRight(find.byType(SubtitlesSectionHeader)).dx,
      ),
    );
  });

  testWidgets('offers Retry when Bazarr is unreachable',
      (WidgetTester tester) async {
    await show(
      tester,
      overrides: subtitleOverrides(
        api: api,
        scheduler: scheduler,
        movie: () => throw StateError('offline'),
      ),
    );
    expect(find.text("Couldn't reach Bazarr."), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('says when Bazarr does not list the movie',
      (WidgetTester tester) async {
    await show(
      tester,
      overrides: subtitleOverrides(
        api: api,
        scheduler: scheduler,
        movie: () => null,
      ),
    );
    expect(
      find.text(
        "Bazarr doesn't list this movie yet. It picks up new Radarr movies "
        'on its next sync.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('collapsed: chips and have/total; expanded: the rows',
      (WidgetTester tester) async {
    await show(tester);
    // de file, en embedded, fr missing.
    expect(find.text('1/3', findRichText: true), findsNothing);
    expect(find.text('2/3', findRichText: true), findsOneWidget);
    expect(find.byType(SubtitleTrackChip), findsNWidgets(3));
    expect(find.text('German'), findsNothing);

    await tester.tap(
      find.bySemanticsLabel('Subtitles, 2 of 3 languages present'),
    );
    await tester.pumpAndSettle();
    expect(find.text('German'), findsOneWidget);
    expect(find.text('External · SRT · 84 KB'), findsOneWidget);
    expect(find.text('Embedded track 3'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget, reason: 'profile row');
    expect(find.text('English, original'), findsOneWidget);
  });

  testWidgets('starts expanded when asked', (WidgetTester tester) async {
    await pumpPage(
      tester,
      const BazarrMovieSubtitlesCardHost(),
      overrides: subtitleOverrides(api: api, scheduler: scheduler),
    );
    await tester.pumpAndSettle();
    expect(find.text('German'), findsOneWidget);
  });

  group('expanded', () {
    Future<void> showExpanded(
      WidgetTester tester, {
      String version = '1.6.2',
      BazarrMovie movie = movieFixture,
      Future<List<BazarrLanguageProfile>> Function()? profiles,
    }) async {
      await pumpPage(
        tester,
        const BazarrMovieSubtitlesCardHost(),
        overrides: subtitleOverrides(
          api: api,
          scheduler: scheduler,
          version: version,
          movie: () => movie,
          profiles: profiles,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a missing row spins while its search runs',
        (WidgetTester tester) async {
      api.answer = never;
      await showExpanded(tester);
      await tester.tap(find.bySemanticsLabel('Search French subtitles'));
      await tester.pump();
      expect(api.calls, <String>['search m42 fr']);
      expect(find.text('Searching…'), findsOneWidget);
      expect(find.byType(SmallSpinner), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Search').first,
          matching: find.byWidgetPredicate((Widget w) => w is FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('an embedded track is gated by version: 1.6.1',
        (WidgetTester tester) async {
      await showExpanded(tester, version: '1.6.1');
      await tester.tap(find.byTooltip('English subtitle actions'));
      await tester.pumpAndSettle();
      expect(find.text('Embedded track'), findsOneWidget);
      expect(find.text('Needs Bazarr 1.6.2 or later'), findsOneWidget);
      expect(find.text('Saves this track next to the video'), findsOneWidget);
      final ListTile translate =
          tester.widget<ListTile>(find.widgetWithText(ListTile, 'Translate…'));
      final ListTile extract = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Extract to file'));
      expect(translate.enabled, isFalse);
      expect(extract.enabled, isTrue);

      await tester.tap(find.text('Extract to file'));
      await settle(tester);
      expect(api.calls, <String>['tool m42 extract']);
      expect(find.text('Extracting the English track…'), findsOneWidget);
    });

    testWidgets('an embedded track Bazarr has not indexed',
        (WidgetTester tester) async {
      await showExpanded(
        tester,
        movie: movieFixture.copyWith(
          subtitles: <BazarrSubtitle>[
            germanFile,
            englishEmbedded.copyWith(id: null),
          ],
        ),
      );
      await tester.tap(find.byTooltip('English subtitle actions'));
      await tester.pumpAndSettle();
      expect(
        find.text("Bazarr hasn't indexed this track yet"),
        findsNWidgets(2),
      );
    });

    testWidgets('timing: three taps at 0.5 s shift by +1.5 s',
        (WidgetTester tester) async {
      await showExpanded(tester);
      await tester.tap(find.byTooltip('German subtitle actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adjust timing…'));
      await tester.pumpAndSettle();

      expect(find.text('Adjust timing'), findsOneWidget);
      expect(find.text('German · Film.de.srt'), findsOneWidget);
      expect(find.text('0.0 s'), findsOneWidget);
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Later'));
      }
      await tester.pump();
      expect(find.text('+1.5 s'), findsOneWidget);
      expect(find.text('Lines appear later'), findsOneWidget);
      expect(find.text('Shift by +1.5 s'), findsOneWidget);

      await tester.tap(find.text('Shift by +1.5 s'));
      await settle(tester);
      expect(api.calls, <String>[
        'tool m42 shift_offset(h=0,m=0,s=1,ms=500)',
      ]);
      expect(find.text('Shifted by +1.5 s: German'), findsOneWidget);
    });

    testWidgets('timing: a 25 fps video defaults to made for 23.976',
        (WidgetTester tester) async {
      await showExpanded(tester);
      await tester.tap(find.byTooltip('German subtitle actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adjust timing…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frame rate'));
      await tester.pumpAndSettle();
      expect(find.text('Convert 23.976 → 25 fps'), findsOneWidget);
      expect(
        find.textContaining('The video plays at 25 fps, from its media info.'),
        findsOneWidget,
      );
    });

    testWidgets('timing errors show in the sheet', (WidgetTester tester) async {
      api.answer = () async => throw StateError('nope');
      await showExpanded(tester);
      await tester.tap(find.byTooltip('German subtitle actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adjust timing…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Earlier'));
      await tester.pump();
      expect(find.text('Shift by −0.5 s'), findsOneWidget);
      await tester.tap(find.text('Shift by −0.5 s'));
      await tester.pumpAndSettle();
      expect(find.text("Bazarr couldn't change the timing"), findsOneWidget);
      expect(find.text('Adjust timing'), findsOneWidget);
    });

    testWidgets('upload prefills language and flags from the file name',
        (WidgetTester tester) async {
      await pumpPage(
        tester,
        const BazarrMovieSubtitlesCardHost(),
        overrides: <Override>[
          ...subtitleOverrides(api: api, scheduler: scheduler),
          subtitleFilePickerProvider.overrideWithValue(
            () async => PickedSubtitleFile(
              name: 'Film.de.forced.srt',
              size: 3,
              readBytes: () async => Uint8List.fromList(<int>[1, 2, 3]),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      expect(find.text('Upload subtitle'), findsOneWidget);
      expect(find.text('Choose a .srt, .ass or .vtt file'), findsOneWidget);

      await tester.tap(find.text('Choose a .srt, .ass or .vtt file'));
      await tester.pumpAndSettle();
      expect(find.text('Film.de.forced.srt'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      final ChoiceChip german =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'German'));
      expect(german.selected, isTrue);
      final SwitchListTile forced = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Forced'),
      );
      final SwitchListTile hi = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Hearing impaired'),
      );
      expect(forced.value, isTrue);
      expect(hi.value, isFalse);

      await tester.tap(find.widgetWithText(FilledButton, 'Upload').last);
      await settle(tester);
      expect(api.calls, <String>['upload m42 de Film.de.forced.srt']);
      expect(find.text('Uploaded German subtitle'), findsOneWidget);
    });

    testWidgets('upload rejects a file that is not a subtitle',
        (WidgetTester tester) async {
      await pumpPage(
        tester,
        const BazarrMovieSubtitlesCardHost(),
        overrides: <Override>[
          ...subtitleOverrides(api: api, scheduler: scheduler),
          subtitleFilePickerProvider.overrideWithValue(
            () async => PickedSubtitleFile(
              name: 'notes.pdf',
              size: 3,
              readBytes: () async => Uint8List(3),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a .srt, .ass or .vtt file'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "notes.pdf isn't a subtitle file. Pick an .srt, .ass or .vtt file.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('delete asks first', (WidgetTester tester) async {
      await showExpanded(tester);
      await tester.tap(find.byTooltip('German subtitle actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete subtitle'));
      await tester.pumpAndSettle();
      expect(find.text('Delete subtitle'), findsOneWidget, reason: 'title');
      expect(
        find.text(
          'Delete the German subtitle file? If the language profile asks '
          'for it, Bazarr searches for it again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);
      expect(api.calls, <String>[
        'delete m42 /movies/Film (2024)/Film.de.srt',
      ]);
      expect(find.text('Deleted German subtitle'), findsOneWidget);
    });

    testWidgets('Search on a movie searches every missing language at once',
        (WidgetTester tester) async {
      await showExpanded(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Search').last);
      await settle(tester);
      expect(api.calls, <String>['search-missing m42']);
      expect(find.text('Searching French subtitles…'), findsOneWidget);
    });

    testWidgets('the profile picker shows a load failure',
        (WidgetTester tester) async {
      await showExpanded(
        tester,
        profiles: () async => throw StateError('offline'),
      );
      expect(find.text('Unavailable'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Language profile: Unavailable'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the profiles"), findsOneWidget);
      expect(
        find.text("Bazarr didn't answer. Close this and try again."),
        findsOneWidget,
      );
      expect(find.text('None'), findsNothing);
    });

    testWidgets('the profile picker sets a profile',
        (WidgetTester tester) async {
      await showExpanded(tester);
      await tester.tap(find.bySemanticsLabel('Language profile: Default'));
      await tester.pumpAndSettle();
      expect(find.text('EN + DE HI'), findsOneWidget);
      expect(find.text('Bazarr stops looking for subtitles'), findsOneWidget);
      await tester.tap(find.text('None'));
      await settle(tester);
      expect(api.calls, <String>['profile 42 null']);
      expect(find.text('Language profile set to None'), findsOneWidget);
    });
  });
}

/// The movie card, expanded from the start.
class BazarrMovieSubtitlesCardHost extends StatelessWidget {
  const BazarrMovieSubtitlesCardHost({super.key});

  @override
  Widget build(BuildContext context) => const BazarrMovieSubtitlesCard(
        bazarr: bazarr,
        expanded: true,
        movie: MovieSubtitlesRef(
          radarrId: 42,
          title: 'Film',
          audioLanguages: 'eng',
          videoFps: 25,
          originalLanguage: 'English',
        ),
      );
}
