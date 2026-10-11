import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:service_bazarr/src/bazarr_api.dart';
import 'package:service_bazarr/src/bazarr_providers.dart';

// Shared fixtures for the link tests.

Instance arr(
  String id,
  ServiceKind kind, {
  String? name,
  String key = 'k',
  String localUrl = '',
}) =>
    Instance(
      id: id,
      name: name ?? id,
      kind: kind,
      localUrl: localUrl,
      externalUrl: '',
      urlMode: UrlMode.auto,
      auth: InstanceAuthApiKey(apiKey: key),
    );

Instance bazarr(
  String id, {
  String? name,
  Map<String, String> links = const <String, String>{},
  String localUrl = 'http://bazarr:6767',
}) =>
    Instance(
      id: id,
      name: name ?? id,
      kind: ServiceKind.bazarr,
      localUrl: localUrl,
      externalUrl: '',
      urlMode: UrlMode.auto,
      auth: const InstanceAuthApiKey(apiKey: 'bazarr-own-key'),
      links: links,
    );

final Instance radarr1 = arr(
  'r1',
  ServiceKind.radarr,
  name: 'Movies',
  key: 'radarr-key-1',
  localUrl: 'http://radarr:7878',
);
final Instance radarr2 = arr(
  'r2',
  ServiceKind.radarr,
  name: 'Movies 4K',
  key: 'radarr-key-2',
  localUrl: 'http://radarr2:7878',
);
final Instance sonarr1 = arr(
  's1',
  ServiceKind.sonarr,
  name: 'Shows',
  key: 'sonarr-key',
  localUrl: 'http://sonarr:8989',
);

/// Bazarr settings that point at [radarr2] and [sonarr1], with secrets that
/// must never surface.
Map<String, dynamic> settingsFor({
  String radarrKey = 'radarr-key-2',
  String sonarrKey = 'sonarr-key',
}) =>
    <String, dynamic>{
      'general': <String, dynamic>{'use_radarr': true, 'use_sonarr': true},
      'radarr': <String, dynamic>{
        'ip': 'radarr',
        'port': 7878,
        'apikey': radarrKey,
      },
      'sonarr': <String, dynamic>{
        'ip': 'sonarr',
        'port': 8989,
        'apikey': sonarrKey,
      },
      'opensubtitlescom': <String, dynamic>{'password': 'provider-secret'},
    };

/// A [BazarrApi] whose settings call is counted, per Bazarr URL.
class FakeBazarrApi extends BazarrApi {
  FakeBazarrApi(this.instance, this.recorder) : super(Dio());

  final Instance instance;
  final SettingsRecorder recorder;

  @override
  Future<Map<String, dynamic>> getBazarrSettings() async {
    recorder.requests.add(instance);
    return recorder.settings(instance);
  }
}

class SettingsRecorder {
  SettingsRecorder([Map<String, dynamic> Function(Instance)? settings])
      : settings = settings ?? ((Instance _) => settingsFor());

  Map<String, dynamic> Function(Instance) settings;
  final List<Instance> requests = <Instance>[];

  int get calls => requests.length;

  Override get override => bazarrApiProvider.overrideWith(
        (Ref ref, Instance instance) => FakeBazarrApi(instance, this),
      );
}

/// One profile, `p`, whose instance writes land in memory.
class FakeProfiles extends ProfileListController {
  FakeProfiles(this.initial);

  final List<Instance> initial;
  final List<List<Instance>> upserts = <List<Instance>>[];

  List<Instance> get instances =>
      state.value?.single.instances ?? const <Instance>[];

  Instance byId(String id) => instances.firstWhere((Instance i) => i.id == id);

  @override
  Future<List<Profile>> build() async => <Profile>[
        Profile(id: 'p', name: 'Default', instances: initial),
      ];

  @override
  Future<void> upsertInstances(String profileId, List<Instance> changed) async {
    upserts.add(changed);
    replace(changed);
  }

  /// Writes [changed] without recording an upsert (a test's own edit).
  void replace(List<Instance> changed) {
    final Profile profile = state.requireValue.single;
    state = AsyncData<List<Profile>>(<Profile>[
      profile.copyWith(
        instances: <Instance>[
          for (final Instance i in profile.instances)
            changed.firstWhereOrNull((Instance c) => c.id == i.id) ?? i,
        ],
      ),
    ]);
  }
}

class FakeActiveProfile extends ActiveProfileIdController {
  @override
  String? build() => 'p';

  @override
  Future<void> select(String? id) async => state = id;
}

List<Override> profileOverrides(FakeProfiles profiles) => <Override>[
      profileListProvider.overrideWith(() => profiles),
      activeProfileIdProvider.overrideWith(FakeActiveProfile.new),
    ];
