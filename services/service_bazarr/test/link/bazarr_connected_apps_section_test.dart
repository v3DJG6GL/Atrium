import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/link/bazarr_connected_apps_section.dart';

import 'link_test_support.dart';

void main() {
  late SettingsRecorder recorder;
  late FakeProfiles profiles;

  Future<void> show(WidgetTester tester, Instance bazarrInstance) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    recorder = SettingsRecorder();
    profiles = FakeProfiles(<Instance>[
      bazarrInstance,
      radarr1,
      radarr2,
      sonarr1,
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[...profileOverrides(profiles), recorder.override],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: Insets.page,
              children: <Widget>[
                BazarrConnectedAppsSection(bazarrId: bazarrInstance.id),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('shows detected links and where Bazarr reaches them',
      (WidgetTester tester) async {
    await show(tester, bazarr('b1', name: 'Bazarr'));

    expect(find.text('Connected apps'), findsOneWidget);
    expect(find.text('Radarr for Bazarr'), findsOneWidget);
    expect(find.text('Sonarr for Bazarr'), findsOneWidget);
    expect(find.text('Movies 4K'), findsOneWidget);
    expect(find.text('Shows'), findsOneWidget);
    expect(find.text('Detected'), findsNWidgets(2));
    expect(
      find.text('Bazarr reaches radarr:7878 and sonarr:8989'),
      findsOneWidget,
    );
    expect(recorder.calls, 1);
  });

  testWidgets('a link set by hand shows Set by you',
      (WidgetTester tester) async {
    await show(
      tester,
      bazarr('b1', name: 'Bazarr', links: <String, String>{'radarr': 'r1'}),
    );

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Set by you'), findsOneWidget);
    expect(find.text('Detected'), findsOneWidget, reason: 'the Sonarr row');
  });

  testWidgets('a link to a deleted instance shows Unavailable instance',
      (WidgetTester tester) async {
    await show(
      tester,
      bazarr('b1', name: 'Bazarr', links: <String, String>{'radarr': 'gone'}),
    );

    expect(
      find.textContaining('Unavailable instance'),
      findsOneWidget,
    );

    await openPicker(tester, 'Radarr for Bazarr');
    expect(find.text('Unavailable instance'), findsOneWidget);
    expect(
      find.text('Deleted or disabled. Pick another one, or None.'),
      findsOneWidget,
    );
  });

  testWidgets('choosing None writes the off value',
      (WidgetTester tester) async {
    await show(tester, bazarr('b1', name: 'Bazarr'));

    await openPicker(tester, 'Radarr for Bazarr');
    expect(find.text('Same API key Bazarr uses for Radarr'), findsOneWidget);
    expect(find.text("Don't show subtitles on Radarr pages"), findsOneWidget);
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();

    final Instance written = profiles.upserts.single.single;
    expect(written.id, 'b1');
    expect(written.links, <String, String>{'radarr': Instance.linkNone});
    expect(find.text('Radarr unlinked'), findsOneWidget);
    expect(
      find.textContaining("None\nDon't show subtitles on Radarr pages"),
      findsOneWidget,
    );
  });

  testWidgets('picking another instance stores it and moves the link',
      (WidgetTester tester) async {
    await show(tester, bazarr('b1', name: 'Bazarr'));

    await openPicker(tester, 'Radarr for Bazarr');
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();

    expect(
      profiles.upserts.single.single.links,
      <String, String>{'radarr': 'r1'},
    );
    expect(find.text('Linked Movies'), findsOneWidget);
    expect(find.text('Set by you'), findsOneWidget);
    expect(recorder.calls, 1, reason: 'a pick does not re-detect');
  });

  testWidgets('Detect again reads the settings again',
      (WidgetTester tester) async {
    await show(tester, bazarr('b1', name: 'Bazarr'));
    expect(recorder.calls, 1);

    await tester.tap(find.text('Detect again'));
    await tester.pumpAndSettle();

    expect(recorder.calls, 2);
    expect(find.text('Found Movies 4K and Shows'), findsOneWidget);
    expect(profiles.upserts, isEmpty);
  });

  testWidgets('a failed read retries once, then says so',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    recorder = SettingsRecorder(
      (Instance _) => throw StateError('unreachable'),
    );
    profiles = FakeProfiles(<Instance>[bazarr('b1', name: 'Bazarr'), radarr1]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[...profileOverrides(profiles), recorder.override],
        child: const MaterialApp(
          home: Scaffold(body: BazarrConnectedAppsSection(bazarrId: 'b1')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text("Reading Bazarr's settings…"), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(recorder.calls, 2);
    expect(
      find.text("Couldn't read Bazarr's settings. Check the connection above."),
      findsOneWidget,
    );
    expect(
      find.text("Not linked\nCouldn't read Bazarr's settings"),
      findsNWidgets(2),
    );
  });

  testWidgets('renders nothing for an instance that is not a Bazarr',
      (WidgetTester tester) async {
    recorder = SettingsRecorder();
    profiles = FakeProfiles(<Instance>[radarr1]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[...profileOverrides(profiles), recorder.override],
        child: const MaterialApp(
          home: Scaffold(body: BazarrConnectedAppsSection(bazarrId: 'r1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connected apps'), findsNothing);
    expect(recorder.calls, 0);
  });
}
