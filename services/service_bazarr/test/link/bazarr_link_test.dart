import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/link/bazarr_link.dart';

ArrCandidate cand(
  String id,
  String apiKey, [
  String localUrl = '',
  String externalUrl = '',
]) =>
    ArrCandidate(
      id: id,
      apiKey: apiKey,
      localUrl: localUrl,
      externalUrl: externalUrl,
    );

Instance inst(
  String id,
  ServiceKind kind, {
  String key = 'k',
  String localUrl = '',
  Map<String, String> links = const <String, String>{},
  InstanceAuth? auth,
}) =>
    Instance(
      id: id,
      name: id,
      kind: kind,
      localUrl: localUrl,
      externalUrl: '',
      urlMode: UrlMode.auto,
      auth: auth ?? InstanceAuthApiKey(apiKey: key),
      links: links,
    );

LinkState manual(String id) => LinkState(arrId: id, how: LinkHow.manual);
LinkState detected(String id) => LinkState(arrId: id, how: LinkHow.detected);
const LinkState none = LinkState(how: LinkHow.none);
const LinkState off = LinkState(how: LinkHow.off);
const LinkState stale = LinkState(how: LinkHow.stale);

void main() {
  group('matchArrInstance', () {
    final List<ArrCandidate> candidates = <ArrCandidate>[
      cand('r1', 'key-a', 'http://192.168.1.10:7878'),
      cand('r2', 'key-b', 'http://192.168.1.11:7878'),
    ];

    test('links the instance whose API key Bazarr uses', () {
      expect(
        matchArrInstance(
          const BazarrArrSide(
            enabled: true,
            apiKey: 'key-b',
            host: 'radarr',
            port: 7878,
          ),
          candidates,
        ),
        'r2',
      );
    });

    test('ignores surrounding whitespace in keys', () {
      expect(
        matchArrInstance(
          const BazarrArrSide(enabled: true, apiKey: ' key-a '),
          candidates,
        ),
        'r1',
      );
    });

    test('compares keys case-sensitively', () {
      expect(
        matchArrInstance(
          const BazarrArrSide(enabled: true, apiKey: 'KEY-A'),
          candidates,
        ),
        isNull,
      );
    });

    test('finds nothing without a matching key', () {
      expect(
        matchArrInstance(
          const BazarrArrSide(enabled: true, apiKey: 'key-z'),
          candidates,
        ),
        isNull,
      );
    });

    test('finds nothing when Bazarr has that arr switched off or no key', () {
      expect(
        matchArrInstance(
          const BazarrArrSide(enabled: false, apiKey: 'key-a'),
          candidates,
        ),
        isNull,
      );
      expect(
        matchArrInstance(
          const BazarrArrSide(enabled: true, apiKey: ''),
          candidates,
        ),
        isNull,
      );
      expect(
        matchArrInstance(const BazarrArrSide(enabled: true), candidates),
        isNull,
      );
    });

    test('breaks a shared-key tie by port, then by host', () {
      final List<ArrCandidate> shared = <ArrCandidate>[
        cand('lan', 'same', 'http://10.0.0.5:7878'),
        cand('vpn', 'same', 'https://radarr.example.com'),
        cand('4k', 'same', 'http://10.0.0.5:7879'),
      ];
      expect(
        matchArrInstance(
          const BazarrArrSide(enabled: true, apiKey: 'same', port: 7879),
          shared,
        ),
        '4k',
      );
      expect(
        matchArrInstance(
          const BazarrArrSide(
            enabled: true,
            apiKey: 'same',
            host: 'radarr.example.com',
          ),
          shared,
        ),
        'vpn',
      );
      expect(
        matchArrInstance(
          const BazarrArrSide(enabled: true, apiKey: 'same'),
          shared,
        ),
        'lan',
      );
    });

    test('uses the host to pick between candidates on the same port', () {
      final List<ArrCandidate> shared = <ArrCandidate>[
        cand('lan', 'same', 'http://10.0.0.5:7878'),
        cand('vpn', 'same', 'http://100.64.0.5:7878'),
      ];
      expect(
        matchArrInstance(
          const BazarrArrSide(
            enabled: true,
            apiKey: 'same',
            host: '100.64.0.5',
            port: 7878,
          ),
          shared,
        ),
        'vpn',
      );
    });

    test('reads ports and hosts from either URL, with or without a scheme', () {
      final List<ArrCandidate> shared = <ArrCandidate>[
        cand('a', 'same', 'http://10.0.0.5'),
        cand('b', 'same', '', 'radarr.lan:7879/radarr'),
        cand('c', 'same', '', 'https://User@Radarr.Example.com:8443/path'),
      ];
      expect(
        matchArrInstance(
          const BazarrArrSide(enabled: true, apiKey: 'same', port: 7879),
          shared,
        ),
        'b',
      );
      expect(
        matchArrInstance(
          const BazarrArrSide(
            enabled: true,
            apiKey: 'same',
            host: 'radarr.example.com',
          ),
          shared,
        ),
        'c',
      );
    });
  });

  group('hostOf', () {
    test('strips scheme, user info, port and path, and lowercases', () {
      expect(
        hostOf('https://me:pw@Radarr.Example.com:8443/x?y#z'),
        'radarr.example.com',
      );
      expect(hostOf(' 10.0.0.5:7878 '), '10.0.0.5');
      expect(hostOf(''), '');
    });
  });

  group('formatArrAddress', () {
    test('joins host and port', () {
      expect(
        formatArrAddress(
          const BazarrArrSide(enabled: true, host: 'radarr', port: 7878),
        ),
        'radarr:7878',
      );
      expect(
        formatArrAddress(const BazarrArrSide(enabled: true, host: 'radarr')),
        'radarr',
      );
    });

    test('is null when the arr is off or has no host', () {
      expect(
        formatArrAddress(
          const BazarrArrSide(enabled: false, host: 'radarr', port: 7878),
        ),
        isNull,
      );
      expect(formatArrAddress(const BazarrArrSide(enabled: true)), isNull);
    });
  });

  group('resolveLinkState', () {
    const Set<String> ids = <String>{'r1', 'r2'};

    test('prefers the stored choice over detection', () {
      expect(resolveLinkState('r1', 'r2', ids), manual('r1'));
    });

    test('honours the off switch', () {
      expect(resolveLinkState(Instance.linkNone, 'r2', ids), off);
    });

    test('flags a stored id whose instance is gone', () {
      expect(resolveLinkState('deleted', 'r2', ids), stale);
    });

    test('uses detection when automatic', () {
      expect(resolveLinkState(null, 'r2', ids), detected('r2'));
      expect(resolveLinkState(null, null, ids), none);
      expect(resolveLinkState(null, 'deleted', ids), none);
    });
  });

  group('bazarrForArr', () {
    test('picks the manual claim over a detected one', () {
      expect(
        bazarrForArr('r1', <BazarrLinkEntry>[
          BazarrLinkEntry(bazarrId: 'b1', state: detected('r1')),
          BazarrLinkEntry(bazarrId: 'b2', state: manual('r1')),
        ]),
        'b2',
      );
    });

    test('falls back to instance order between equals', () {
      expect(
        bazarrForArr('r1', <BazarrLinkEntry>[
          BazarrLinkEntry(bazarrId: 'b1', state: detected('r1')),
          BazarrLinkEntry(bazarrId: 'b2', state: detected('r1')),
        ]),
        'b1',
      );
    });

    test('is null when nothing claims the arr', () {
      expect(
        bazarrForArr('r1', const <BazarrLinkEntry>[
          BazarrLinkEntry(bazarrId: 'b1', state: off),
        ]),
        isNull,
      );
      expect(bazarrForArr('', const <BazarrLinkEntry>[]), isNull);
    });
  });

  group('itemsArrInstance', () {
    test('uses the linked instance, even with several configured', () {
      expect(itemsArrInstance(manual('r2'), <String>['r1', 'r2']), 'r2');
      expect(itemsArrInstance(detected('r2'), <String>['r1', 'r2']), 'r2');
    });

    test('falls back to the only instance when nothing is linked', () {
      expect(itemsArrInstance(none, <String>['r1']), 'r1');
      expect(itemsArrInstance(stale, <String>['r1']), 'r1');
      expect(itemsArrInstance(null, <String>['r1']), 'r1');
    });

    test('has no instance when nothing is linked and several are configured',
        () {
      expect(itemsArrInstance(none, <String>['r1', 'r2']), isNull);
      expect(itemsArrInstance(null, <String>['r1', 'r2']), isNull);
      expect(itemsArrInstance(null, <String>[]), isNull);
    });

    test('never falls back when the link is switched off', () {
      expect(itemsArrInstance(off, <String>['r1']), isNull);
    });
  });

  group('planLinkPick', () {
    Map<String, String?> plan({
      required String bazarrId,
      required String pick,
      required List<Instance> bazarrs,
      required LinkState state,
      required List<BazarrLinkEntry> entries,
      String? detectedId,
      ServiceKind kind = ServiceKind.radarr,
    }) =>
        planLinkPick(
          kind: kind,
          bazarrId: bazarrId,
          pick: pick,
          bazarrs: bazarrs,
          state: state,
          detectedId: detectedId,
          entries: entries,
        );

    test('sets the target and returns other manual claims to automatic', () {
      final List<Instance> bazarrs = <Instance>[
        inst('b1', ServiceKind.bazarr, links: <String, String>{'radarr': 'r1'}),
        inst('b2', ServiceKind.bazarr),
        inst('b3', ServiceKind.bazarr, links: <String, String>{'radarr': 'r2'}),
      ];
      expect(
        plan(
          bazarrId: 'b2',
          pick: 'r1',
          bazarrs: bazarrs,
          state: none,
          entries: <BazarrLinkEntry>[
            BazarrLinkEntry(bazarrId: 'b1', state: manual('r1')),
            const BazarrLinkEntry(bazarrId: 'b2', state: none),
            BazarrLinkEntry(bazarrId: 'b3', state: manual('r2')),
          ],
        ),
        <String, String?>{'b2': 'r1', 'b1': null},
      );
    });

    test('touches only the field of the given kind', () {
      final List<Instance> bazarrs = <Instance>[
        inst('b1', ServiceKind.bazarr, links: <String, String>{'radarr': 's1'}),
        inst('b2', ServiceKind.bazarr),
      ];
      expect(
        plan(
          kind: ServiceKind.sonarr,
          bazarrId: 'b2',
          pick: 's1',
          bazarrs: bazarrs,
          state: none,
          entries: const <BazarrLinkEntry>[
            BazarrLinkEntry(bazarrId: 'b1', state: none),
            BazarrLinkEntry(bazarrId: 'b2', state: none),
          ],
        ),
        <String, String?>{'b2': 's1'},
      );
    });

    test('picking the detected instance nobody else claims stays automatic',
        () {
      final List<Instance> bazarrs = <Instance>[
        inst('b1', ServiceKind.bazarr, links: <String, String>{'radarr': 'r2'}),
      ];
      // From a manual r2 to the detected r1: the stored id goes away.
      expect(
        plan(
          bazarrId: 'b1',
          pick: 'r1',
          bazarrs: bazarrs,
          state: manual('r2'),
          detectedId: 'r1',
          entries: <BazarrLinkEntry>[
            BazarrLinkEntry(bazarrId: 'b1', state: manual('r2')),
          ],
        ),
        <String, String?>{'b1': null},
      );
    });

    test('picking the detected instance another Bazarr claims stores it', () {
      final List<Instance> bazarrs = <Instance>[
        inst('b1', ServiceKind.bazarr, links: <String, String>{'radarr': 'r1'}),
        inst('b2', ServiceKind.bazarr),
      ];
      // b2 detects r1 but b1 has it by hand: b2 is outranked, and the pick
      // moves the link to b2.
      expect(
        plan(
          bazarrId: 'b2',
          pick: 'r1',
          bazarrs: bazarrs,
          state: detected('r1'),
          detectedId: 'r1',
          entries: <BazarrLinkEntry>[
            BazarrLinkEntry(bazarrId: 'b1', state: manual('r1')),
            BazarrLinkEntry(bazarrId: 'b2', state: detected('r1')),
          ],
        ),
        <String, String?>{'b2': 'r1', 'b1': null},
      );
    });

    test('a detected claim elsewhere is outranked without being changed', () {
      final List<Instance> bazarrs = <Instance>[
        inst('b1', ServiceKind.bazarr),
        inst('b2', ServiceKind.bazarr),
      ];
      expect(
        plan(
          bazarrId: 'b2',
          pick: 'r1',
          bazarrs: bazarrs,
          state: detected('r1'),
          detectedId: 'r1',
          entries: <BazarrLinkEntry>[
            BazarrLinkEntry(bazarrId: 'b1', state: detected('r1')),
            BazarrLinkEntry(bazarrId: 'b2', state: detected('r1')),
          ],
        ),
        <String, String?>{'b2': 'r1'},
      );
    });

    test('re-picking detected on a manual row returns it to automatic', () {
      final List<Instance> bazarrs = <Instance>[
        inst('b1', ServiceKind.bazarr, links: <String, String>{'radarr': 'r1'}),
      ];
      expect(
        plan(
          bazarrId: 'b1',
          pick: 'r1',
          bazarrs: bazarrs,
          state: manual('r1'),
          detectedId: 'r1',
          entries: <BazarrLinkEntry>[
            BazarrLinkEntry(bazarrId: 'b1', state: manual('r1')),
          ],
        ),
        <String, String?>{'b1': null},
      );
    });

    test('None stores the off value', () {
      final List<Instance> bazarrs = <Instance>[
        inst('b1', ServiceKind.bazarr),
      ];
      expect(
        plan(
          bazarrId: 'b1',
          pick: Instance.linkNone,
          bazarrs: bazarrs,
          state: detected('r1'),
          detectedId: 'r1',
          entries: <BazarrLinkEntry>[
            BazarrLinkEntry(bazarrId: 'b1', state: detected('r1')),
          ],
        ),
        <String, String?>{'b1': Instance.linkNone},
      );
    });

    test('re-picking the current choice is a no-op', () {
      final List<Instance> bazarrs = <Instance>[
        inst('b1', ServiceKind.bazarr, links: <String, String>{'radarr': 'r2'}),
        inst(
          'b2',
          ServiceKind.bazarr,
          links: <String, String>{'radarr': 'none'},
        ),
        inst('b3', ServiceKind.bazarr),
      ];
      final List<BazarrLinkEntry> entries = <BazarrLinkEntry>[
        BazarrLinkEntry(bazarrId: 'b1', state: manual('r2')),
        const BazarrLinkEntry(bazarrId: 'b2', state: off),
        BazarrLinkEntry(bazarrId: 'b3', state: detected('r1')),
      ];
      expect(
        plan(
          bazarrId: 'b1',
          pick: 'r2',
          bazarrs: bazarrs,
          state: manual('r2'),
          detectedId: 'r1',
          entries: entries,
        ),
        isEmpty,
      );
      expect(
        plan(
          bazarrId: 'b2',
          pick: Instance.linkNone,
          bazarrs: bazarrs,
          state: off,
          entries: entries,
        ),
        isEmpty,
      );
      expect(
        plan(
          bazarrId: 'b3',
          pick: 'r1',
          bazarrs: bazarrs,
          state: detected('r1'),
          detectedId: 'r1',
          entries: entries,
        ),
        isEmpty,
      );
    });
  });

  group('linkRowOf', () {
    test('a detected link another Bazarr wins shows as not linked', () {
      final LinkRow byManual = linkRowOf(
        bazarrId: 'b2',
        state: detected('r1'),
        stored: null,
        entries: <BazarrLinkEntry>[
          BazarrLinkEntry(bazarrId: 'b1', state: manual('r1')),
          BazarrLinkEntry(bazarrId: 'b2', state: detected('r1')),
        ],
      );
      expect(byManual.selected, isNull);
      expect(byManual.outrankedBy, 'b1');
      expect(byManual.outrankedByManual, isTrue);

      final LinkRow byOrder = linkRowOf(
        bazarrId: 'b2',
        state: detected('r1'),
        stored: null,
        entries: <BazarrLinkEntry>[
          BazarrLinkEntry(bazarrId: 'b1', state: detected('r1')),
          BazarrLinkEntry(bazarrId: 'b2', state: detected('r1')),
        ],
      );
      expect(byOrder.outrankedBy, 'b1');
      expect(byOrder.outrankedByManual, isFalse);
    });

    test('selects the arr, None, or the stale id', () {
      expect(
        linkRowOf(
          bazarrId: 'b1',
          state: detected('r1'),
          stored: null,
          entries: <BazarrLinkEntry>[
            BazarrLinkEntry(bazarrId: 'b1', state: detected('r1')),
          ],
        ).selected,
        'r1',
      );
      expect(
        linkRowOf(
          bazarrId: 'b1',
          state: off,
          stored: Instance.linkNone,
          entries: const <BazarrLinkEntry>[],
        ).selected,
        Instance.linkNone,
      );
      expect(
        linkRowOf(
          bazarrId: 'b1',
          state: stale,
          stored: 'gone',
          entries: const <BazarrLinkEntry>[],
        ).selected,
        'gone',
      );
    });
  });

  group('withLink', () {
    test('sets and removes one kind, keeping the other', () {
      final Instance b = inst(
        'b1',
        ServiceKind.bazarr,
        links: <String, String>{'radarr': 'r1', 'sonarr': 's1'},
      );
      expect(
        withLink(b, ServiceKind.radarr, 'r2').links,
        <String, String>{'radarr': 'r2', 'sonarr': 's1'},
      );
      expect(
        withLink(b, ServiceKind.radarr, null).links,
        <String, String>{'sonarr': 's1'},
      );
    });
  });

  group('readArrSide', () {
    test('reads the connection of an enabled arr', () {
      final BazarrArrSide side = readArrSide(
        <String, dynamic>{
          'general': <String, dynamic>{'use_radarr': true},
          'radarr': <String, dynamic>{
            'ip': 'radarr',
            'port': 7878,
            'apikey': 'k',
          },
        },
        ServiceKind.radarr,
      );
      expect(side.enabled, isTrue);
      expect(side.apiKey, 'k');
      expect(side.host, 'radarr');
      expect(side.port, 7878);
    });

    test('accepts a numeric string port', () {
      expect(
        readArrSide(
          <String, dynamic>{
            'radarr': <String, dynamic>{'port': ' 7878 '},
          },
          ServiceKind.radarr,
        ).port,
        7878,
      );
    });

    test('enables an arr only for exactly true', () {
      for (final Object? flag in <Object?>['true', 1, 'True', null]) {
        expect(
          readArrSide(
            <String, dynamic>{
              'general': <String, dynamic>{'use_sonarr': flag},
              'sonarr': <String, dynamic>{'apikey': 'k'},
            },
            ServiceKind.sonarr,
          ).enabled,
          isFalse,
          reason: 'use_sonarr: $flag',
        );
      }
    });

    test('reads malformed settings as disabled', () {
      for (final Object? settings in <Object?>[
        null,
        'not settings',
        <dynamic>[1, 2],
        <String, dynamic>{'general': 'x', 'radarr': 'y'},
      ]) {
        final BazarrArrSide side = readArrSide(settings, ServiceKind.radarr);
        expect(side.enabled, isFalse);
        expect(side.apiKey, isNull);
        expect(side.host, isNull);
      }
      final BazarrArrSide wrongTypes = readArrSide(
        <String, dynamic>{
          'general': <String, dynamic>{'use_radarr': true},
          'radarr': <String, dynamic>{'ip': 5, 'port': 'abc', 'apikey': 3},
        },
        ServiceKind.radarr,
      );
      expect(wrongTypes.enabled, isTrue);
      expect(wrongTypes.apiKey, isNull);
      expect(wrongTypes.host, isNull);
      expect(wrongTypes.port, isNull);
    });
  });

  group('detectFromSettings', () {
    final Map<String, dynamic> settings = <String, dynamic>{
      'general': <String, dynamic>{'use_radarr': true, 'use_sonarr': false},
      'radarr': <String, dynamic>{
        'ip': 'radarr',
        'port': 7878,
        'apikey': 'radarr-key-2',
      },
      'sonarr': <String, dynamic>{
        'ip': 'sonarr',
        'port': 8989,
        'apikey': 'sonarr-key',
      },
      'opensubtitlescom': <String, dynamic>{
        'username': 'me',
        'password': 'provider-secret',
      },
      'auth': <String, dynamic>{'apikey': 'bazarr-own-key'},
    };
    final List<Instance> radarrs = <Instance>[
      inst(
        'r1',
        ServiceKind.radarr,
        key: 'radarr-key-1',
        localUrl: 'http://radarr:7878',
      ),
      inst(
        'r2',
        ServiceKind.radarr,
        key: 'radarr-key-2',
        localUrl: 'http://radarr2:7878',
      ),
    ];
    final List<Instance> sonarrs = <Instance>[
      inst(
        's1',
        ServiceKind.sonarr,
        key: 'sonarr-key',
        localUrl: 'http://sonarr:8989',
      ),
    ];

    test('matches by API key and skips an arr Bazarr has switched off', () {
      expect(
        detectFromSettings(settings, radarrs: radarrs, sonarrs: sonarrs),
        const ArrLinkDetection(
          radarr: ArrLinkSide(instanceId: 'r2', address: 'radarr:7878'),
        ),
      );
    });

    test("returns ids and addresses only, never the settings' secrets", () {
      final String serialized =
          detectFromSettings(settings, radarrs: radarrs, sonarrs: sonarrs)
              .toString();
      for (final String secret in <String>[
        'radarr-key-2',
        'sonarr-key',
        'provider-secret',
        'bazarr-own-key',
      ]) {
        expect(serialized, isNot(contains(secret)));
      }
      expect(serialized, contains('r2'));
    });

    test('tolerates a malformed settings payload', () {
      expect(
        detectFromSettings('not settings', radarrs: radarrs, sonarrs: sonarrs),
        const ArrLinkDetection(),
      );
    });

    test('ignores instances without an API key', () {
      expect(
        detectFromSettings(
          settings,
          radarrs: <Instance>[
            inst(
              'r9',
              ServiceKind.radarr,
              auth: const InstanceAuth.userPass(
                username: 'radarr-key-2',
                password: 'radarr-key-2',
              ),
            ),
          ],
          sonarrs: const <Instance>[],
        ).radarr.instanceId,
        isNull,
      );
    });
  });

  group('arrFingerprint', () {
    test('lists Radarr then Sonarr ids, flagging keyless ones', () {
      expect(
        arrFingerprint(<Instance>[
          inst('s1', ServiceKind.sonarr, key: 'sonarr-secret'),
          inst('b1', ServiceKind.bazarr, key: 'bazarr-secret'),
          inst('r1', ServiceKind.radarr, key: 'radarr-secret'),
          inst('r2', ServiceKind.radarr, key: '  '),
        ]),
        'r1,r2:nokey,s1',
      );
    });

    test('never contains a key', () {
      final String fingerprint = arrFingerprint(<Instance>[
        inst('r1', ServiceKind.radarr, key: 'radarr-secret'),
        inst('s1', ServiceKind.sonarr, key: 'sonarr-secret'),
      ]);
      expect(fingerprint, isNot(contains('secret')));
    });
  });

  test('candidates and sides never print their key', () {
    expect(
      ArrCandidate.of(inst('r1', ServiceKind.radarr, key: 'radarr-secret'))
          .toString(),
      isNot(contains('secret')),
    );
    expect(
      const BazarrArrSide(enabled: true, apiKey: 'radarr-secret').toString(),
      isNot(contains('secret')),
    );
  });
}
