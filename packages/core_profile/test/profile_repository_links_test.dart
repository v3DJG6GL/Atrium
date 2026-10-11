import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Links between instances have to survive the operations that rewrite
/// instance ids (import) or remove an instance (delete).
void main() {
  late Directory tempDir;
  late Box<String> profiles;
  late Box<String> settings;
  late ProfileRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_links_test');
    Hive.init(tempDir.path);
    profiles = await Hive.openBox<String>('profiles');
    settings = await Hive.openBox<String>('settings');
    repo = ProfileRepository(
      profilesBox: profiles,
      settingsBox: settings,
      secrets: _MemorySecureStorage(),
    );
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Profile sample() => Profile(
        id: 'p1',
        name: 'Home',
        instances: <Instance>[
          _instance('r1', ServiceKind.radarr),
          _instance('s1', ServiceKind.sonarr),
          _instance(
            'b1',
            ServiceKind.bazarr,
            links: const <String, String>{'radarr': 'r1', 'sonarr': 's1'},
          ),
          _instance(
            'b2',
            ServiceKind.bazarr,
            links: const <String, String>{
              'radarr': Instance.linkNone,
              'sonarr': 'gone',
            },
          ),
        ],
      );

  test('import moves links to the new ids, keeps none, drops unknown', () async {
    final String json = repo.exportProfile(sample(), includeSecrets: true);

    final Profile imported = await repo.importProfile(json);

    final Instance radarr =
        imported.instances.firstWhere((Instance i) => i.name == 'r1');
    final Instance sonarr =
        imported.instances.firstWhere((Instance i) => i.name == 's1');
    final Instance b1 =
        imported.instances.firstWhere((Instance i) => i.name == 'b1');
    final Instance b2 =
        imported.instances.firstWhere((Instance i) => i.name == 'b2');
    expect(radarr.id, isNot('r1'));
    expect(b1.links, <String, String>{'radarr': radarr.id, 'sonarr': sonarr.id});
    expect(b2.links, const <String, String>{'radarr': Instance.linkNone});
  });

  test('deleting an instance drops the links that point at it', () async {
    await repo.saveProfile(sample());

    await repo.deleteInstance('p1', 'r1');

    final Profile after = (await repo.getProfile('p1'))!;
    final Instance b1 = after.instances.firstWhere((Instance i) => i.id == 'b1');
    final Instance b2 = after.instances.firstWhere((Instance i) => i.id == 'b2');
    expect(b1.links, const <String, String>{'sonarr': 's1'});
    expect(b2.links, sample().instances[3].links);
  });

  test('upsertInstances replaces several instances in one write', () async {
    await repo.saveProfile(sample());
    final Profile before = (await repo.getProfile('p1'))!;
    final Instance b1 = before.instances.firstWhere((Instance i) => i.id == 'b1');
    final Instance b2 = before.instances.firstWhere((Instance i) => i.id == 'b2');
    int writes = 0;
    profiles.watch(key: 'p1').listen((_) => writes++);

    await repo.upsertInstances('p1', <Instance>[
      b1.copyWith(links: const <String, String>{'sonarr': 's1'}),
      b2.copyWith(links: const <String, String>{'radarr': 'r1'}),
    ]);
    await Future<void>.delayed(Duration.zero);

    final Profile after = (await repo.getProfile('p1'))!;
    expect(writes, 1);
    expect(
      after.instances.firstWhere((Instance i) => i.id == 'b1').links,
      const <String, String>{'sonarr': 's1'},
    );
    expect(
      after.instances.firstWhere((Instance i) => i.id == 'b2').links,
      const <String, String>{'radarr': 'r1'},
    );
    expect(after.instances.map((Instance i) => i.id), <String>['r1', 's1', 'b1', 'b2']);
  });

  test('export keeps links but not the API key', () {
    final String json = repo.exportProfile(sample());
    final Map<String, dynamic> decoded = jsonDecode(json) as Map<String, dynamic>;
    final Map<String, dynamic> b1 = (decoded['instances'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((Map<String, dynamic> i) => i['id'] == 'b1');

    expect(b1['links'], <String, dynamic>{'radarr': 'r1', 'sonarr': 's1'});
    expect(json, isNot(contains('key-b1')));
  });
}

Instance _instance(
  String id,
  ServiceKind kind, {
  Map<String, String> links = const <String, String>{},
}) =>
    Instance(
      id: id,
      name: id,
      kind: kind,
      localUrl: 'http://192.168.1.10',
      externalUrl: '',
      urlMode: UrlMode.auto,
      auth: InstanceAuth.apiKey(apiKey: 'key-$id'),
      links: links,
    );

/// Keeps secrets in a map instead of the platform keystore.
class _MemorySecureStorage extends AtriumSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
