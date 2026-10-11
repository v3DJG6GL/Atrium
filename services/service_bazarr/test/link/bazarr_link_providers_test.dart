import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/link/bazarr_link.dart';
import 'package:service_bazarr/src/link/bazarr_link_providers.dart';

import 'link_test_support.dart';

void main() {
  late SettingsRecorder recorder;
  late FakeProfiles profiles;

  Future<ProviderContainer> containerWith(List<Instance> instances) async {
    recorder = SettingsRecorder();
    profiles = FakeProfiles(instances);
    final ProviderContainer container = ProviderContainer.test(
      overrides: <Override>[...profileOverrides(profiles), recorder.override],
    );
    await container.read(profileListProvider.future);
    return container;
  }

  // Lets detection requests and rebuilds run.
  Future<void> settle(ProviderContainer container) async {
    for (int i = 0; i < 5; i++) {
      await container.pump();
      await pumpEventQueue();
    }
  }

  group('detection', () {
    test('a link pick does not re-detect; a URL change does', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1'),
        radarr1,
        radarr2,
        sonarr1,
      ]);
      final ProviderSubscription<BazarrLinkStatus> status = container.listen(
        bazarrLinkStatusProvider('b1'),
        (BazarrLinkStatus? _, BazarrLinkStatus __) {},
      );
      await settle(container);

      expect(recorder.calls, 1);
      expect(
        status.read().radarr,
        const LinkState(arrId: 'r2', how: LinkHow.detected),
      );
      expect(
        status.read().sonarr,
        const LinkState(arrId: 's1', how: LinkHow.detected),
      );
      expect(
        status.read().detection?.radarr.address,
        'radarr:7878',
      );

      profiles.replace(<Instance>[
        withLink(profiles.byId('b1'), ServiceKind.radarr, 'r1')
            .copyWith(name: 'Renamed'),
      ]);
      await settle(container);

      expect(
        status.read().radarr,
        const LinkState(arrId: 'r1', how: LinkHow.manual),
      );
      expect(recorder.calls, 1, reason: 'links and name are not connection');

      profiles.replace(<Instance>[
        profiles.byId('b1').copyWith(localUrl: 'http://bazarr.lan:6767'),
      ]);
      await settle(container);

      expect(recorder.calls, 2);
      expect(recorder.requests.last.localUrl, 'http://bazarr.lan:6767');
    });

    test('a new arr instance re-detects; Detect-again style refresh too',
        () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1'),
        radarr1,
      ]);
      container.listen(
        bazarrLinkStatusProvider('b1'),
        (BazarrLinkStatus? _, BazarrLinkStatus __) {},
      );
      await settle(container);
      expect(recorder.calls, 1);

      profiles.state = AsyncData<List<Profile>>(<Profile>[
        profiles.state.requireValue.single.copyWith(
          instances: <Instance>[...profiles.instances, radarr2],
        ),
      ]);
      await settle(container);
      expect(recorder.calls, 2);
      expect(
        container.read(bazarrLinkStatusProvider('b1')).radarr.arrId,
        'r2',
      );

      final String fingerprint = container.read(arrFingerprintProvider);
      await container.refresh(
        bazarrLinkDetectionProvider(
          (bazarrId: 'b1', fingerprint: fingerprint),
        ).future,
      );
      expect(recorder.calls, 3);
    });

    test('the fingerprint and detection carry no secret', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1'),
        radarr1,
        radarr2,
        sonarr1,
      ]);
      final String fingerprint = container.read(arrFingerprintProvider);
      expect(fingerprint, 'r1,r2,s1');
      final ArrLinkDetection detection = await container.read(
        bazarrLinkDetectionProvider(
          (bazarrId: 'b1', fingerprint: fingerprint),
        ).future,
      );
      for (final String secret in <String>[
        'radarr-key',
        'sonarr-key',
        'provider-secret',
        'bazarr-own-key',
      ]) {
        expect(detection.toString(), isNot(contains(secret)));
      }
    });
  });

  group('bazarrForArrProvider', () {
    test('a manual owner answers without any settings request', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1'),
        bazarr('b2', links: <String, String>{'radarr': 'r1'}),
        radarr1,
        radarr2,
      ]);
      final ProviderSubscription<Instance?> owner = container.listen(
        bazarrForArrProvider(radarr1.copyWith(name: 'Stale copy')),
        (Instance? _, Instance? __) {},
      );
      await settle(container);

      expect(owner.read()?.id, 'b2');
      expect(recorder.calls, 0);

      // It is the current instance of the profile.
      profiles.replace(<Instance>[
        profiles.byId('b2').copyWith(name: 'Bazarr 2'),
      ]);
      await settle(container);
      expect(owner.read()?.name, 'Bazarr 2');
    });

    test('detects for automatic Bazarrs and follows the first claim', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1'),
        bazarr('b2', localUrl: 'http://bazarr2:6767'),
        radarr1,
        radarr2,
      ]);
      final ProviderSubscription<Instance?> owner = container.listen(
        bazarrForArrProvider(radarr2),
        (Instance? _, Instance? __) {},
      );
      await settle(container);

      expect(owner.read()?.id, 'b1');
      expect(recorder.calls, 2);
      expect(
        container.read(bazarrForArrProvider(radarr1)),
        isNull,
        reason: 'no Bazarr is configured against r1',
      );
    });

    test('a manual claim outranks a detected one', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1'),
        bazarr('b2', links: <String, String>{'radarr': 'r2'}),
        radarr1,
        radarr2,
      ]);
      final ProviderSubscription<List<BazarrLinkEntry>> entries =
          container.listen(
        bazarrLinkEntriesProvider(ServiceKind.radarr),
        (List<BazarrLinkEntry>? _, List<BazarrLinkEntry> __) {},
      );
      await settle(container);

      expect(entries.read(), <BazarrLinkEntry>[
        const BazarrLinkEntry(
          bazarrId: 'b1',
          state: LinkState(arrId: 'r2', how: LinkHow.detected),
        ),
        const BazarrLinkEntry(
          bazarrId: 'b2',
          state: LinkState(arrId: 'r2', how: LinkHow.manual),
        ),
      ]);
      expect(recorder.calls, 1, reason: 'only the automatic Bazarr detects');
      expect(container.read(bazarrForArrProvider(radarr2))?.id, 'b2');
    });

    test('is null for an arr not in the profile', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1', links: <String, String>{'radarr': 'r1'}),
      ]);
      expect(container.read(bazarrForArrProvider(radarr1)), isNull);
    });
  });

  group('bazarrItemsArrProvider', () {
    Instance? itemsArr(ProviderContainer c, String bazarrId, ServiceKind k) =>
        c.read(bazarrItemsArrProvider((bazarrId: bazarrId, kind: k)));

    test('uses the only arr of the kind without detecting', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1'),
        radarr1,
      ]);
      expect(itemsArr(container, 'b1', ServiceKind.radarr)?.id, 'r1');
      expect(itemsArr(container, 'b1', ServiceKind.sonarr), isNull);
      await settle(container);
      expect(recorder.calls, 0);
    });

    test('never falls back when the link is off', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1', links: <String, String>{'radarr': Instance.linkNone}),
        radarr1,
      ]);
      expect(itemsArr(container, 'b1', ServiceKind.radarr), isNull);
    });

    test('uses the manual link, or detection, among several', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1', links: <String, String>{'radarr': 'r1'}),
        bazarr('b2', localUrl: 'http://bazarr2:6767'),
        radarr1,
        radarr2,
      ]);
      expect(itemsArr(container, 'b1', ServiceKind.radarr)?.id, 'r1');

      final ProviderSubscription<Instance?> detected = container.listen(
        bazarrItemsArrProvider((bazarrId: 'b2', kind: ServiceKind.radarr)),
        (Instance? _, Instance? __) {},
      );
      expect(detected.read(), isNull, reason: 'detection still running');
      await settle(container);
      expect(detected.read()?.id, 'r2');
    });

    test('has none among several when nothing is detected', () async {
      final ProviderContainer container = await containerWith(<Instance>[
        bazarr('b1'),
        radarr1,
        radarr2,
      ]);
      recorder.settings = (Instance _) => settingsFor(radarrKey: 'other');
      final ProviderSubscription<Instance?> items = container.listen(
        bazarrItemsArrProvider((bazarrId: 'b1', kind: ServiceKind.radarr)),
        (Instance? _, Instance? __) {},
      );
      await settle(container);
      expect(recorder.calls, 1);
      expect(items.read(), isNull);
    });
  });

  test('a stored id whose instance is gone reads as stale', () async {
    final ProviderContainer container = await containerWith(<Instance>[
      bazarr('b1', links: <String, String>{'radarr': 'gone'}),
      radarr1,
    ]);
    final ProviderSubscription<BazarrLinkStatus> status = container.listen(
      bazarrLinkStatusProvider('b1'),
      (BazarrLinkStatus? _, BazarrLinkStatus __) {},
    );
    await settle(container);
    expect(status.read().radarr, const LinkState(how: LinkHow.stale));
    expect(status.read().detection?.radarr.instanceId, isNull);
  });
}
