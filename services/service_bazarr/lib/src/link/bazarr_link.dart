/// Which Bazarr instance serves which Radarr / Sonarr instance.
///
/// A Bazarr only manages subtitles for the one Radarr and the one Sonarr it
/// is configured against, so the movie and series pages must ask the right
/// Bazarr, or none. The link is stored on the Bazarr [Instance] in
/// [Instance.links], keyed by the arr's [ServiceKind.name]:
///
/// - key absent: automatic. Bazarr's own settings name the Radarr/Sonarr it
///   talks to, including its API key. An API key belongs to exactly one
///   server, so a key match identifies the instance, unlike a hostname.
/// - an instance id: set by the user; wins over detection.
/// - [Instance.linkNone]: switched off.
///
/// Everything here is pure. The network half lives in
/// `bazarr_link_providers.dart`.
library;

import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';

/// The arr kinds a Bazarr links to.
const List<ServiceKind> bazarrArrKinds = <ServiceKind>[
  ServiceKind.radarr,
  ServiceKind.sonarr,
];

/// What Bazarr's settings say about one of the two arrs it can talk to.
class BazarrArrSide {
  const BazarrArrSide({
    required this.enabled,
    this.apiKey,
    this.host,
    this.port,
  });

  /// An integration Bazarr has switched off, or settings that couldn't be
  /// read.
  static const BazarrArrSide disabled = BazarrArrSide(enabled: false);

  final bool enabled;
  final String? apiKey;
  final String? host;
  final int? port;

  // Never print the key.
  @override
  String toString() => 'BazarrArrSide(enabled: $enabled, host: $host, '
      'port: $port, hasKey: ${apiKey?.trim().isNotEmpty ?? false})';
}

/// A Radarr/Sonarr instance configured in the app, as the matcher sees it.
class ArrCandidate {
  const ArrCandidate({
    required this.id,
    required this.localUrl,
    required this.externalUrl,
    this.apiKey,
  });

  /// The candidate for [instance]. Only an API-key auth carries a key.
  static ArrCandidate of(Instance instance) => ArrCandidate(
        id: instance.id,
        apiKey: switch (instance.auth) {
          InstanceAuthApiKey(:final String apiKey) => apiKey,
          _ => null,
        },
        localUrl: instance.localUrl,
        externalUrl: instance.externalUrl,
      );

  final String id;
  final String? apiKey;
  final String localUrl;
  final String externalUrl;

  // Never print the key.
  @override
  String toString() => 'ArrCandidate($id)';
}

/// The candidate Bazarr is configured against, or null.
///
/// The API key must match (trimmed, case-sensitive). Should several
/// candidates share a key (one server added twice, say a LAN and a VPN
/// entry), they narrow to the ones whose URL also carries Bazarr's port, then
/// to the one on Bazarr's host, then the first.
String? matchArrInstance(BazarrArrSide side, List<ArrCandidate> candidates) {
  final String? key = side.apiKey?.trim();
  if (!side.enabled || key == null || key.isEmpty) {
    return null;
  }

  final List<ArrCandidate> matches = candidates
      .where((ArrCandidate c) => c.apiKey?.trim() == key)
      .toList(growable: false);
  if (matches.length <= 1) {
    return matches.firstOrNull?.id;
  }

  List<ArrCandidate> pool = matches;
  final int? port = side.port;
  if (port != null && port != 0) {
    final List<ArrCandidate> byPort = pool
        .where((ArrCandidate c) => _portsOf(c).contains(port))
        .toList(growable: false);
    if (byPort.isNotEmpty) {
      pool = byPort;
    }
  }
  final String? host = side.host?.trim().toLowerCase();
  if (host != null && host.isNotEmpty) {
    final ArrCandidate? byHost =
        pool.firstWhereOrNull((ArrCandidate c) => _hostsOf(c).contains(host));
    if (byHost != null) {
      return byHost.id;
    }
  }
  return pool.first.id;
}

final RegExp _hasScheme = RegExp('^[a-z]+://', caseSensitive: false);

/// The explicit ports of a candidate's two URLs.
Set<int> _portsOf(ArrCandidate c) {
  final Set<int> ports = <int>{};
  for (final String raw in <String>[c.localUrl, c.externalUrl]) {
    if (raw.isEmpty) {
      continue;
    }
    final Uri? uri =
        Uri.tryParse(_hasScheme.hasMatch(raw) ? raw : 'http://$raw');
    // Unparseable URL: contributes no port.
    if (uri != null && uri.hasPort) {
      ports.add(uri.port);
    }
  }
  return ports;
}

/// Every non-empty hostname a candidate is reachable at.
Set<String> _hostsOf(ArrCandidate c) => <String>{
      for (final String url in <String>[c.localUrl, c.externalUrl])
        if (hostOf(url).isNotEmpty) hostOf(url),
    };

final RegExp _schemePrefix =
    RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);
final RegExp _authorityEnd = RegExp('[/?#]');
final RegExp _userInfo = RegExp('^[^@]*@');
final RegExp _portSuffix = RegExp(r':\d+$');

/// The lowercase hostname of [url]: scheme, path, user info and port
/// stripped. Empty when there is none.
String hostOf(String url) {
  final String stripped = url.trim().replaceFirst(_schemePrefix, '');
  final int end = stripped.indexOf(_authorityEnd);
  final String authority = end == -1 ? stripped : stripped.substring(0, end);
  return authority
      .replaceFirst(_userInfo, '')
      .replaceFirst(_portSuffix, '')
      .toLowerCase();
}

/// "radarr:7878": where Bazarr says it reaches the arr. Null when that arr is
/// off or has no host.
String? formatArrAddress(BazarrArrSide side) {
  final String? host = side.host;
  if (!side.enabled || host == null || host.isEmpty) {
    return null;
  }
  final int? port = side.port;
  return port != null && port != 0 ? '$host:$port' : host;
}

/// What detection found for one arr kind: ids and addresses only.
class ArrLinkSide {
  const ArrLinkSide({this.instanceId, this.address});

  /// The matched Radarr/Sonarr instance id, or null.
  final String? instanceId;

  /// Where Bazarr reaches that arr, e.g. `radarr:7878`, or null.
  final String? address;

  @override
  bool operator ==(Object other) =>
      other is ArrLinkSide &&
      other.instanceId == instanceId &&
      other.address == address;

  @override
  int get hashCode => Object.hash(instanceId, address);

  @override
  String toString() =>
      'ArrLinkSide(instanceId: $instanceId, address: $address)';
}

/// The result of reading one Bazarr's settings. Holds no secrets.
class ArrLinkDetection {
  const ArrLinkDetection({
    this.radarr = const ArrLinkSide(),
    this.sonarr = const ArrLinkSide(),
  });

  final ArrLinkSide radarr;
  final ArrLinkSide sonarr;

  /// The side for [kind] (radarr or sonarr).
  ArrLinkSide of(ServiceKind kind) => switch (kind) {
        ServiceKind.radarr => radarr,
        ServiceKind.sonarr => sonarr,
        _ => throw ArgumentError.value(kind, 'kind', 'not linked by Bazarr'),
      };

  @override
  bool operator ==(Object other) =>
      other is ArrLinkDetection &&
      other.radarr == radarr &&
      other.sonarr == sonarr;

  @override
  int get hashCode => Object.hash(radarr, sonarr);

  @override
  String toString() => 'ArrLinkDetection(radarr: $radarr, sonarr: $sonarr)';
}

/// One arr side of Bazarr's settings (`GET api/system/settings`).
///
/// `general.use_radarr` / `general.use_sonarr` toggle each integration and
/// must be exactly `true`; `radarr.{apikey, ip, port}` and `sonarr.{…}` hold
/// the connection. Anything malformed reads as disabled or absent.
BazarrArrSide readArrSide(Object? settings, ServiceKind kind) {
  if (settings is! Map) {
    return BazarrArrSide.disabled;
  }
  final Object? general = settings['general'];
  final Object? conn = settings[kind.name];
  final bool enabled = general is Map && general['use_${kind.name}'] == true;
  if (conn is! Map) {
    return BazarrArrSide(enabled: enabled);
  }
  final Object? apiKey = conn['apikey'];
  final Object? host = conn['ip'];
  return BazarrArrSide(
    enabled: enabled,
    apiKey: apiKey is String ? apiKey : null,
    host: host is String ? host : null,
    port: _readPort(conn['port']),
  );
}

int? _readPort(Object? raw) {
  final int? port = switch (raw) {
    final int n => n,
    final String s => int.tryParse(s.trim()),
    _ => null,
  };
  return port != null && port > 0 && port <= 65535 ? port : null;
}

/// Matches Bazarr's [settings] against the profile's Radarr and Sonarr
/// instances.
///
/// The settings carry every provider password and Bazarr's own API key, so
/// nothing from them leaves this function except instance ids and display
/// addresses.
ArrLinkDetection detectFromSettings(
  Object? settings, {
  required List<Instance> radarrs,
  required List<Instance> sonarrs,
}) {
  ArrLinkSide side(ServiceKind kind, List<Instance> instances) {
    final BazarrArrSide read = readArrSide(settings, kind);
    return ArrLinkSide(
      instanceId: matchArrInstance(
        read,
        <ArrCandidate>[
          for (final Instance i in instances)
            if (i.kind == kind) ArrCandidate.of(i),
        ],
      ),
      address: formatArrAddress(read),
    );
  }

  return ArrLinkDetection(
    radarr: side(ServiceKind.radarr, radarrs),
    sonarr: side(ServiceKind.sonarr, sonarrs),
  );
}

/// How a Bazarr's link for one arr kind came about.
enum LinkHow {
  /// Set by the user and pointing at an existing instance.
  manual,

  /// Automatic, and detection found the instance.
  detected,

  /// Switched off by the user.
  off,

  /// Automatic, but nothing was detected (yet).
  none,

  /// Set by the user, but that instance no longer exists.
  stale,
}

/// One Bazarr's effective link for one arr kind.
class LinkState {
  const LinkState({required this.how, this.arrId});

  final String? arrId;
  final LinkHow how;

  @override
  bool operator ==(Object other) =>
      other is LinkState && other.arrId == arrId && other.how == how;

  @override
  int get hashCode => Object.hash(arrId, how);

  @override
  String toString() => 'LinkState(${how.name}, $arrId)';
}

/// One Bazarr instance's effective link for one arr kind.
///
/// [stored] is the [Instance.links] value (null = automatic), [detected] the
/// detection result for this kind (null while detection hasn't run or found
/// nothing), and [arrIds] the ids of the arr instances that exist right now.
LinkState resolveLinkState(
  String? stored,
  String? detected,
  Set<String> arrIds,
) {
  if (stored == Instance.linkNone) {
    return const LinkState(how: LinkHow.off);
  }
  if (stored != null) {
    return arrIds.contains(stored)
        ? LinkState(arrId: stored, how: LinkHow.manual)
        : const LinkState(how: LinkHow.stale);
  }
  if (detected != null && arrIds.contains(detected)) {
    return LinkState(arrId: detected, how: LinkHow.detected);
  }
  return const LinkState(how: LinkHow.none);
}

/// The Radarr/Sonarr instance a Bazarr's items resolve against (the library
/// its `radarrId` / `sonarrSeriesId` are looked up in), or null for none.
///
/// Those ids are per instance, so only the linked instance is safe. Without a
/// link, the one instance of the kind is used when there is exactly one; with
/// several, any pick could show another title's poster, so none is used. A
/// link switched off means this Bazarr has no such arr: no fallback.
String? itemsArrInstance(LinkState? state, List<String> arrIds) {
  final String? linked = state?.arrId;
  if (linked != null) {
    return linked;
  }
  if (state?.how == LinkHow.off) {
    return null;
  }
  return arrIds.length == 1 ? arrIds.single : null;
}

/// One Bazarr's link state for one arr kind.
class BazarrLinkEntry {
  const BazarrLinkEntry({required this.bazarrId, required this.state});

  final String bazarrId;
  final LinkState state;

  @override
  bool operator ==(Object other) =>
      other is BazarrLinkEntry &&
      other.bazarrId == bazarrId &&
      other.state == state;

  @override
  int get hashCode => Object.hash(bazarrId, state);

  @override
  String toString() => 'BazarrLinkEntry($bazarrId, $state)';
}

/// The Bazarr instance that serves [arrId], or null.
///
/// Two Bazarr instances can claim one arr. A link the user set wins over a
/// detected one; between equals, instance order decides, so the answer never
/// flips between renders.
String? bazarrForArr(String arrId, List<BazarrLinkEntry> entries) {
  if (arrId.isEmpty) {
    return null;
  }
  final List<BazarrLinkEntry> claims = entries
      .where((BazarrLinkEntry e) => e.state.arrId == arrId)
      .toList(growable: false);
  final BazarrLinkEntry? manual = claims
      .firstWhereOrNull((BazarrLinkEntry e) => e.state.how == LinkHow.manual);
  return (manual ?? claims.firstOrNull)?.bazarrId;
}

/// What one "Connected apps" row of a Bazarr shows.
class LinkRow {
  const LinkRow({
    required this.selected,
    this.outrankedBy,
    this.outrankedByManual = false,
  });

  /// The selected option: an arr id, [Instance.linkNone], the stale stored
  /// id, or null for "Not linked".
  final String? selected;

  /// The Bazarr that wins this row's detected instance, when another one
  /// does: the row then shows as not linked.
  final String? outrankedBy;

  /// Whether [outrankedBy] has the instance set by hand.
  final bool outrankedByManual;

  bool get outranked => outrankedBy != null;
}

/// The row of [bazarrId] for one kind: its [state], the [stored] value and
/// every Bazarr's [entries] for that kind.
///
/// A detected link that another Bazarr outranks (set by hand, or detected
/// too and earlier in order) shows as not linked, so pages and this row
/// agree on which Bazarr serves the instance.
LinkRow linkRowOf({
  required String bazarrId,
  required LinkState state,
  required String? stored,
  required List<BazarrLinkEntry> entries,
}) {
  final String? detectedArr = state.arrId;
  if (state.how == LinkHow.detected && detectedArr != null) {
    final String? winner = bazarrForArr(detectedArr, entries);
    if (winner != null && winner != bazarrId) {
      return LinkRow(
        selected: null,
        outrankedBy: winner,
        outrankedByManual: entries
                .firstWhereOrNull((BazarrLinkEntry e) => e.bazarrId == winner)
                ?.state
                .how ==
            LinkHow.manual,
      );
    }
  }
  return LinkRow(
    selected: switch (state.how) {
      LinkHow.off => Instance.linkNone,
      LinkHow.stale => stored,
      _ => state.arrId,
    },
  );
}

/// The [Instance.links] changes for picking [pick] (an arr id or
/// [Instance.linkNone]) in the row of [bazarrId] for [kind]: Bazarr id → new
/// stored value, null meaning automatic. Only Bazarrs whose value changes
/// are listed; an empty map means nothing to write.
///
/// - Picking the detected instance stores automatic, unless another Bazarr
///   claims it too (set by hand or detected), which could still outrank a
///   detected link; then it is stored by hand.
/// - Picking any other instance stores its id, and every other Bazarr that
///   had the same instance set by hand goes back to automatic, so the link
///   moves instead of leaving two manual claims. (A detected claim elsewhere
///   needs no change: the manual link outranks it.)
/// - Re-picking a hand-set link that detection also finds returns the row to
///   automatic; any other re-pick is a no-op.
/// - [Instance.linkNone] switches the row off.
///
/// [bazarrs] are every Bazarr of the profile, [state] the row's current
/// state, [detectedId] what this Bazarr's detection found for [kind]
/// (whatever is stored), and [entries] every Bazarr's state for [kind].
Map<String, String?> planLinkPick({
  required ServiceKind kind,
  required String bazarrId,
  required String pick,
  required List<Instance> bazarrs,
  required LinkState state,
  required String? detectedId,
  required List<BazarrLinkEntry> entries,
}) {
  String? storedOf(String id) =>
      bazarrs.firstWhereOrNull((Instance b) => b.id == id)?.links[kind.name];

  bool claimedElsewhere(String arrId) => entries.any(
        (BazarrLinkEntry e) => e.bazarrId != bazarrId && e.state.arrId == arrId,
      );

  final LinkRow row = linkRowOf(
    bazarrId: bazarrId,
    state: state,
    stored: storedOf(bazarrId),
    entries: entries,
  );
  final bool backToAutomatic = state.how == LinkHow.manual &&
      pick == detectedId &&
      !claimedElsewhere(pick);
  if (pick == row.selected && !backToAutomatic) {
    return const <String, String?>{};
  }

  final Map<String, String?> next = <String, String?>{};
  if (pick == Instance.linkNone) {
    next[bazarrId] = Instance.linkNone;
  } else {
    final bool automatic = pick == detectedId && !claimedElsewhere(pick);
    next[bazarrId] = automatic ? null : pick;
    for (final Instance b in bazarrs) {
      if (b.id != bazarrId && b.links[kind.name] == pick) {
        next[b.id] = null;
      }
    }
  }
  next.removeWhere(
    (String id, String? value) =>
        !bazarrs.any((Instance b) => b.id == id) || storedOf(id) == value,
  );
  return next;
}

/// [bazarr] with its link for [kind] set to [value]; null removes the key
/// (automatic).
Instance withLink(Instance bazarr, ServiceKind kind, String? value) {
  final Map<String, String> links = Map<String, String>.of(bazarr.links);
  if (value == null) {
    links.remove(kind.name);
  } else {
    links[kind.name] = value;
  }
  return bazarr.copyWith(links: links);
}

/// The Radarr then Sonarr ids of [instances] in order, each suffixed
/// `:nokey` when it has no usable API key. Never contains a key: it ends up
/// in a provider argument.
///
/// A new or removed arr re-runs detection, and so does a key added to an
/// instance that had none. A changed key is picked up by "Detect again".
String arrFingerprint(List<Instance> instances) {
  String part(Instance i) {
    final bool keyed = switch (i.auth) {
      InstanceAuthApiKey(:final String apiKey) => apiKey.trim().isNotEmpty,
      _ => false,
    };
    return keyed ? i.id : '${i.id}:nokey';
  }

  return <String>[
    for (final ServiceKind kind in bazarrArrKinds)
      for (final Instance i in instances)
        if (i.kind == kind) part(i),
  ].join(',');
}
