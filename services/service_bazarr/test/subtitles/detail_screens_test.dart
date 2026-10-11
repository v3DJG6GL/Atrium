import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/bazarr_movie_detail_screen.dart';
import 'package:service_bazarr/src/bazarr_series_detail_screen.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';

import '../support/fake_scheduler.dart';
import 'subtitle_test_support.dart';

void main() {
  late FakeSubtitlesApi api;
  late FakeScheduler scheduler;

  setUp(() {
    api = FakeSubtitlesApi();
    scheduler = FakeScheduler();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        retry: (int _, Object __) => null,
        overrides: subtitleOverrides(
          api: api,
          scheduler: scheduler,
          profiles: () => <BazarrLanguageProfile>[
            ...profilesFixture,
            ...seriesProfiles,
          ],
        ),
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the movie screen lists the subtitles with their actions',
      (WidgetTester tester) async {
    await pumpScreen(
      tester,
      const BazarrMovieDetailScreen(
        instance: bazarr,
        radarrId: 42,
        title: 'Film',
      ),
    );
    expect(find.text('German'), findsOneWidget);
    expect(find.text('External · SRT · 84 KB'), findsOneWidget);
    expect(find.bySemanticsLabel('Search French subtitles'), findsOneWidget);
    expect(find.bySemanticsLabel('Language profile: Default'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Search French subtitles'));
    await settle(tester);
    expect(api.calls, <String>['search m42 fr']);
  });

  testWidgets('the series screen opens an episode sheet from its card',
      (WidgetTester tester) async {
    await pumpScreen(
      tester,
      const BazarrSeriesDetailScreen(instance: bazarr, series: seriesFixture),
    );
    expect(find.text('S02E01 · Episode 1'), findsOneWidget);
    expect(find.byType(SubtitleTrackChip), findsNWidgets(5));

    await tester.tap(find.text('S02E01 · Episode 1'));
    await tester.pumpAndSettle();
    expect(find.text('S02E01 subtitles'), findsOneWidget);
    expect(find.text('S01E02'), findsOneWidget);
  });
}
