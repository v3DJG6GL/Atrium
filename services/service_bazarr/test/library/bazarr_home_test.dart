import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/service_bazarr.dart';

import '../subtitles/subtitle_test_support.dart';

void main() {
  testWidgets('BazarrHome opens on the Library with its five tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (int _, Object __) => null,
        overrides: <Override>[
          activeInstancesProvider.overrideWithValue(const <Instance>[bazarr]),
          bazarrMoviesProvider(bazarr).overrideWith(
            (Ref ref) async => const <BazarrMovie>[
              BazarrMovie(
                radarrId: 1,
                title: 'The Matrix',
                year: 1999,
                profileId: 1,
                missingSubtitles: <BazarrSubtitle>[
                  BazarrSubtitle(name: 'English', code2: 'en'),
                ],
              ),
            ],
          ),
          bazarrSeriesProvider(bazarr).overrideWith(
            (Ref ref) async => const <BazarrSeries>[],
          ),
          bazarrProfilesProvider(bazarr).overrideWith(
            (Ref ref) async => const <BazarrLanguageProfile>[],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BazarrHome(instance: bazarr)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    for (final String tab in <String>[
      'Library',
      'History',
      'Blacklist',
      'System',
      'Settings',
    ]) {
      expect(find.widgetWithText(Tab, tab), findsOneWidget);
    }
    expect(find.widgetWithText(Tab, 'Wanted'), findsNothing);
    expect(find.text('The Matrix'), findsOneWidget);
    expect(find.text('Missing 1'), findsOneWidget);
  });
}
