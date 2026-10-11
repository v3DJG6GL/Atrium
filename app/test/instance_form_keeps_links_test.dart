import 'package:atrium/src/screens/instance_form_screen.dart';
import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A Bazarr's links to Radarr and Sonarr are written by its Connected apps
/// section as soon as they're picked, not by the form's Save. Saving the
/// form must keep them, including a pick made after the form opened.
void main() {
  const Instance bazarr = Instance(
    id: 'bazarr',
    name: 'Bazarr',
    kind: ServiceKind.bazarr,
    localUrl: 'http://bazarr.example.test',
    externalUrl: '',
    urlMode: UrlMode.auto,
    auth: InstanceAuth.apiKey(apiKey: 'k'),
    links: <String, String>{'radarr': 'r1'},
  );

  late _Profiles profiles;

  Future<void> editBazarr(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    profiles = _Profiles(bazarr);
    final GoRouter router = GoRouter(
      initialLocation: '/edit',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext _, GoRouterState __) =>
              const Scaffold(body: Text('home')),
          routes: <RouteBase>[
            GoRoute(
              path: 'edit',
              builder: (BuildContext _, GoRouterState __) =>
                  InstanceFormScreen(instanceId: bazarr.id),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          profileListProvider.overrideWith(() => profiles),
          activeProfileIdProvider.overrideWith(_Active.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving an edit keeps the links', (WidgetTester tester) async {
    await editBazarr(tester);

    await save(tester);

    expect(profiles.saved.single.links, bazarr.links);
  });

  testWidgets('saving keeps a link picked after the form opened',
      (WidgetTester tester) async {
    await editBazarr(tester);
    const Map<String, String> picked = <String, String>{
      'radarr': 'r1',
      'sonarr': Instance.linkNone,
    };
    profiles.replace(bazarr.copyWith(links: picked));
    await tester.pump();

    await save(tester);

    expect(profiles.saved.single.links, picked);
  });
}

class _Profiles extends ProfileListController {
  _Profiles(this.instance);

  final Instance instance;
  final List<Instance> saved = <Instance>[];

  @override
  Future<List<Profile>> build() async => <Profile>[
        Profile(id: 'p', name: 'Default', instances: <Instance>[instance]),
      ];

  void replace(Instance next) {
    state = AsyncData<List<Profile>>(<Profile>[
      Profile(id: 'p', name: 'Default', instances: <Instance>[next]),
    ]);
  }

  @override
  Future<void> upsertInstance(String profileId, Instance instance) async {
    saved.add(instance);
  }
}

class _Active extends ActiveProfileIdController {
  @override
  String? build() => 'p';

  @override
  Future<void> select(String? id) async => state = id;
}
