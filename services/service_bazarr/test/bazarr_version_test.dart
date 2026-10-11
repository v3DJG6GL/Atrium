import 'package:core_models/core_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/service_bazarr.dart';

const Instance bazarr = Instance(
  id: 'bazarr-1',
  name: 'Bazarr Test',
  kind: ServiceKind.bazarr,
  localUrl: 'http://localhost:6767',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'dummy-api-key'),
);

void main() {
  group('compareVersions', () {
    test('orders dotted versions numerically', () {
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.6.1', '1.6.2'), lessThan(0));
      expect(compareVersions('1.6', '1.6.0'), 0);
    });

    test('ignores a leading v', () {
      expect(compareVersions('v1.6.2', '1.6.2'), 0);
      expect(compareVersions('V1.6.2', 'v1.6.1'), greaterThan(0));
    });

    test('drops pre-release and build suffixes', () {
      expect(compareVersions('1.6.3-beta.8', '1.6.3'), 0);
      expect(compareVersions('1.6.3-beta.8', '1.6.2'), greaterThan(0));
      expect(compareVersions('1.2.0+abc', '1.2.0'), 0);
      expect(compareVersions(' 1.2.0 dev', '1.2.0'), 0);
    });

    test('reads leading digits of each part, missing as 0', () {
      expect(compareVersions('1.6.2rc1', '1.6.2'), 0);
      expect(compareVersions('1.x.5', '1.0.5'), 0);
    });
  });

  group('versionAtLeast', () {
    test('gates on the minimum version', () {
      expect(versionAtLeast('1.6.1', '1.6.1'), isTrue);
      expect(versionAtLeast('v1.6.2', '1.6.1'), isTrue);
      expect(versionAtLeast('1.5.6', '1.6.1'), isFalse);
      expect(versionAtLeast('1.6.3-beta.8', '1.6.3'), isTrue);
    });

    test('treats an unknown version as too old', () {
      expect(versionAtLeast(null, '1.0.0'), isFalse);
      expect(versionAtLeast('', '1.0.0'), isFalse);
    });
  });

  group('BazarrCapabilities', () {
    Map<BazarrFeature, bool> caps(String? v) => <BazarrFeature, bool>{
          for (final BazarrFeature f in BazarrFeature.values)
            f: BazarrCapabilities.forVersion(v).supports(f),
        };

    test('gates each feature on the version that introduced it', () {
      expect(caps('1.5.5'), <BazarrFeature, bool>{
        BazarrFeature.jobs: false,
        BazarrFeature.extract: false,
        BazarrFeature.translateEmbedded: false,
      });
      expect(caps('1.5.6')[BazarrFeature.jobs], isTrue);
      expect(caps('1.5.6')[BazarrFeature.extract], isFalse);
      expect(caps('v1.6.1'), <BazarrFeature, bool>{
        BazarrFeature.jobs: true,
        BazarrFeature.extract: true,
        BazarrFeature.translateEmbedded: false,
      });
      expect(caps('1.6.3-beta.8'), <BazarrFeature, bool>{
        BazarrFeature.jobs: true,
        BazarrFeature.extract: true,
        BazarrFeature.translateEmbedded: true,
      });
    });

    test('offers nothing optional for an unknown version', () {
      expect(caps(null).values, everyElement(isFalse));
    });

    test('minimum versions', () {
      expect(BazarrFeature.jobs.minVersion, '1.5.6');
      expect(BazarrFeature.extract.minVersion, '1.6.1');
      expect(BazarrFeature.translateEmbedded.minVersion, '1.6.2');
    });
  });

  group('bazarrVersionState', () {
    test('is checking until the status call answers', () {
      expect(
        bazarrVersionState(hasStatus: false, failed: false),
        BazarrVersionState.checking,
      );
    });

    test('is unreadable when the call failed or carried no usable version', () {
      expect(
        bazarrVersionState(hasStatus: false, failed: true),
        BazarrVersionState.unreadable,
      );
      expect(
        bazarrVersionState(hasStatus: true, failed: false),
        BazarrVersionState.unreadable,
      );
      expect(
        bazarrVersionState(version: 'unknown', hasStatus: true, failed: false),
        BazarrVersionState.unreadable,
      );
    });

    test('is known for a real version, even after a failed refetch', () {
      expect(
        bazarrVersionState(version: 'v1.6.2', hasStatus: true, failed: true),
        BazarrVersionState.known,
      );
    });
  });

  group('versionGateNote', () {
    test('names the minimum version only once the version is known', () {
      expect(
        versionGateNote(BazarrVersionState.known, BazarrFeature.extract),
        'Needs Bazarr 1.6.1 or later',
      );
      expect(
        versionGateNote(
          BazarrVersionState.known,
          BazarrFeature.translateEmbedded,
        ),
        'Needs Bazarr 1.6.2 or later',
      );
      expect(
        versionGateNote(BazarrVersionState.checking, BazarrFeature.extract),
        'Checking Bazarr version…',
      );
      expect(
        versionGateNote(BazarrVersionState.unreadable, BazarrFeature.extract),
        "Couldn't read Bazarr's version",
      );
    });

    test('is null when the capabilities support the feature', () {
      expect(
        versionGateNote(
          BazarrVersionState.known,
          BazarrFeature.extract,
          const BazarrCapabilities.forVersion('1.6.1'),
        ),
        isNull,
      );
    });
  });

  group('bazarrVersionInfoProvider', () {
    test('derives state and capabilities from the system status', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          bazarrSystemStatusProvider.overrideWith(
            (Ref ref, Instance i) async =>
                const BazarrSystemStatus(bazarrVersion: '1.6.1'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final ProviderSubscription<BazarrVersionInfo> sub = container.listen(
        bazarrVersionInfoProvider(bazarr),
        (BazarrVersionInfo? _, BazarrVersionInfo __) {},
      );
      expect(sub.read().state, BazarrVersionState.checking);
      expect(
        sub.read().gateNote(BazarrFeature.jobs),
        'Checking Bazarr version…',
      );

      await container.read(bazarrSystemStatusProvider(bazarr).future);
      final BazarrVersionInfo info = sub.read();
      expect(info.state, BazarrVersionState.known);
      expect(info.version, '1.6.1');
      expect(info.supports(BazarrFeature.extract), isTrue);
      expect(info.gateNote(BazarrFeature.extract), isNull);
      expect(
        info.gateNote(BazarrFeature.translateEmbedded),
        'Needs Bazarr 1.6.2 or later',
      );
    });

    test('is unreadable when the status call fails', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          bazarrSystemStatusProvider.overrideWith(
            (Ref ref, Instance i) async => throw StateError('down'),
          ),
        ],
        retry: (int _, Object __) => null,
      );
      addTearDown(container.dispose);
      final ProviderSubscription<BazarrVersionInfo> sub = container.listen(
        bazarrVersionInfoProvider(bazarr),
        (BazarrVersionInfo? _, BazarrVersionInfo __) {},
      );
      await expectLater(
        container.read(bazarrSystemStatusProvider(bazarr).future),
        throwsStateError,
      );
      expect(sub.read().state, BazarrVersionState.unreadable);
      expect(sub.read().supports(BazarrFeature.jobs), isFalse);
    });
  });

  test('embedded-not-indexed note', () {
    expect(embeddedNotIndexedNote, "Bazarr hasn't indexed this track yet");
  });
}
