import 'dart:async';

import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bazarr_api.dart';
import '../bazarr_providers.dart';
import 'bazarr_link.dart';

// Riverpod glue for the Bazarr → Radarr/Sonarr link (model:
// `bazarr_link.dart`).
//
// Detection reads a Bazarr's settings once and keeps only the derived
// result, for up to 30 minutes after the last listener. It runs again when
// the Bazarr's connection (URLs, key, headers) changes or the profile's
// Radarr/Sonarr set changes, and on "Detect again". It only runs for Bazarrs
// in automatic mode, so a link the user set never costs a request; the
// Connected apps section always detects, to show what Bazarr itself is
// configured against.

/// How long a detection result outlives its last listener.
const Duration _detectionKeepAlive = Duration(minutes: 30);

/// Ids of the profile's Radarr and Sonarr instances, each flagged when it
/// has no key (see [arrFingerprint]). Never contains a key.
final Provider<String> arrFingerprintProvider = Provider<String>(
  (Ref ref) => arrFingerprint(ref.watch(activeInstancesProvider)),
);

/// The Bazarr [Instance] with its links and name cleared, so a link pick or
/// a rename leaves it unchanged (providers notify only on a changed value)
/// while a URL, key or header edit re-runs detection. Null when the id is
/// not a Bazarr of the active profile.
final _bazarrConnectionProvider =
    Provider.family<Instance?, String>((Ref ref, String bazarrId) {
  final Instance? bazarr = ref.watch(instanceByIdProvider(bazarrId));
  if (bazarr == null || bazarr.kind != ServiceKind.bazarr) {
    return null;
  }
  return bazarr.copyWith(name: '', links: const <String, String>{});
});

/// The argument of [bazarrLinkDetectionProvider]. The fingerprint carries no
/// key.
typedef BazarrDetectionKey = ({String bazarrId, String fingerprint});

/// What one Bazarr's settings say about its Radarr and Sonarr, matched
/// against the profile's instances.
///
/// The settings response carries plaintext API keys and provider passwords,
/// so it never leaves this provider's body: only ids and addresses are kept.
/// Retries once after a second.
final bazarrLinkDetectionProvider =
    FutureProvider.autoDispose.family<ArrLinkDetection, BazarrDetectionKey>(
  (Ref ref, BazarrDetectionKey key) async {
    // Watched before any await, so connection edits always re-run this.
    final Instance? connection =
        ref.watch(_bazarrConnectionProvider(key.bazarrId));
    if (connection == null) {
      throw StateError('No Bazarr instance ${key.bazarrId} in this profile');
    }

    final link = ref.keepAlive();
    Timer? release;
    ref.onCancel(() {
      release?.cancel();
      release = Timer(_detectionKeepAlive, link.close);
    });
    ref.onResume(() {
      release?.cancel();
      release = null;
    });
    ref.onDispose(() => release?.cancel());

    final Instance full =
        ref.read(instanceByIdProvider(key.bazarrId)) ?? connection;
    final List<Instance> instances = ref.read(activeInstancesProvider);
    try {
      final BazarrApi api = await ref.watch(bazarrApiProvider(full).future);
      return detectFromSettings(
        await api.getBazarrSettings(),
        radarrs: instances
            .where((Instance i) => i.kind == ServiceKind.radarr)
            .toList(growable: false),
        sonarrs: instances
            .where((Instance i) => i.kind == ServiceKind.sonarr)
            .toList(growable: false),
      );
    } catch (_) {
      // Keep only successes: a failure is retried by the next listener.
      link.close();
      rethrow;
    }
  },
  retry: (int retryCount, Object _) =>
      retryCount < 1 ? const Duration(seconds: 1) : null,
);

/// Bazarr instances of the active profile, in order.
List<Instance> _bazarrsOf(List<Instance> instances) => instances
    .where((Instance i) => i.kind == ServiceKind.bazarr)
    .toList(growable: false);

/// Every Bazarr's link for one arr kind, in instance order.
///
/// Detection is watched only for Bazarrs in automatic mode, and only when
/// the profile has an instance of the kind to match. A detection still
/// loading or failed reads as [LinkHow.none].
final bazarrLinkEntriesProvider =
    Provider.autoDispose.family<List<BazarrLinkEntry>, ServiceKind>(
  (Ref ref, ServiceKind kind) {
    final List<Instance> instances = ref.watch(activeInstancesProvider);
    final Set<String> arrIds = <String>{
      for (final Instance i in instances)
        if (i.kind == kind) i.id,
    };
    final String fingerprint = ref.watch(arrFingerprintProvider);
    return <BazarrLinkEntry>[
      for (final Instance b in _bazarrsOf(instances))
        BazarrLinkEntry(
          bazarrId: b.id,
          state: resolveLinkState(
            b.links[kind.name],
            b.links[kind.name] == null && arrIds.isNotEmpty
                ? ref
                    .watch(
                      bazarrLinkDetectionProvider(
                        (bazarrId: b.id, fingerprint: fingerprint),
                      ),
                    )
                    .value
                    ?.of(kind)
                    .instanceId
                : null,
            arrIds,
          ),
        ),
    ];
  },
);

/// The Bazarr serving [arr] (a Radarr or Sonarr), as the current [Instance]
/// of the profile, or null: then no subtitle UI is shown.
///
/// Only [arr]'s id and kind are used, so a stale [Instance] works. A link set
/// by hand answers without asking any Bazarr.
final bazarrForArrProvider =
    Provider.autoDispose.family<Instance?, Instance>((Ref ref, Instance arr) {
  if (!bazarrArrKinds.contains(arr.kind)) {
    return null;
  }
  final List<Instance> instances = ref.watch(activeInstancesProvider);
  if (!instances.any((Instance i) => i.id == arr.id && i.kind == arr.kind)) {
    return null;
  }
  final List<Instance> bazarrs = _bazarrsOf(instances);
  final Instance? manualOwner = bazarrs
      .firstWhereOrNull((Instance b) => b.links[arr.kind.name] == arr.id);
  if (manualOwner != null) {
    return manualOwner;
  }
  final String? owner =
      bazarrForArr(arr.id, ref.watch(bazarrLinkEntriesProvider(arr.kind)));
  return bazarrs.firstWhereOrNull((Instance b) => b.id == owner);
});

/// The Radarr/Sonarr instance a Bazarr's items (their `radarrId` /
/// `sonarrSeriesId`) belong to, or null (see [itemsArrInstance]). Never the
/// app's active instance: those ids are per instance.
final bazarrItemsArrProvider = Provider.autoDispose
    .family<Instance?, ({String bazarrId, ServiceKind kind})>(
  (Ref ref, ({String bazarrId, ServiceKind kind}) arg) {
    final List<Instance> instances = ref.watch(activeInstancesProvider);
    final Instance? bazarr = instances.firstWhereOrNull(
      (Instance i) => i.id == arg.bazarrId && i.kind == ServiceKind.bazarr,
    );
    if (bazarr == null || !bazarrArrKinds.contains(arg.kind)) {
      return null;
    }
    final List<Instance> arrs = instances
        .where((Instance i) => i.kind == arg.kind)
        .toList(growable: false);
    final List<String> arrIds =
        arrs.map((Instance i) => i.id).toList(growable: false);
    final String? stored = bazarr.links[arg.kind.name];
    // With a single arr, automatic resolves to it whatever detection says.
    final BazarrDetectionKey key = (
      bazarrId: bazarr.id,
      fingerprint: ref.watch(arrFingerprintProvider),
    );
    final String? detected = stored == null && arrs.length > 1
        ? ref
            .watch(bazarrLinkDetectionProvider(key))
            .value
            ?.of(arg.kind)
            .instanceId
        : null;
    final String? id = itemsArrInstance(
      resolveLinkState(stored, detected, arrIds.toSet()),
      arrIds,
    );
    return arrs.firstWhereOrNull((Instance i) => i.id == id);
  },
);

/// Link state and detection detail for one Bazarr, for its Connected apps
/// section.
class BazarrLinkStatus {
  const BazarrLinkStatus({
    required this.radarr,
    required this.sonarr,
    this.detection,
    this.detecting = false,
    this.detectError,
  });

  final LinkState radarr;
  final LinkState sonarr;

  /// The last detection result, or null while none has completed.
  final ArrLinkDetection? detection;

  /// Whether Bazarr's settings are being read.
  final bool detecting;

  /// Why the last read failed, or null.
  final Object? detectError;

  LinkState of(ServiceKind kind) => switch (kind) {
        ServiceKind.radarr => radarr,
        ServiceKind.sonarr => sonarr,
        _ => throw ArgumentError.value(kind, 'kind', 'not linked by Bazarr'),
      };

  @override
  bool operator ==(Object other) =>
      other is BazarrLinkStatus &&
      other.radarr == radarr &&
      other.sonarr == sonarr &&
      other.detection == detection &&
      other.detecting == detecting &&
      other.detectError == detectError;

  @override
  int get hashCode =>
      Object.hash(radarr, sonarr, detection, detecting, detectError);
}

/// The [BazarrLinkStatus] of one Bazarr. Always detects, even with links set
/// by hand: the section shows what Bazarr itself is configured against next
/// to the user's choice.
final bazarrLinkStatusProvider =
    Provider.autoDispose.family<BazarrLinkStatus, String>(
  (Ref ref, String bazarrId) {
    final List<Instance> instances = ref.watch(activeInstancesProvider);
    final Instance? bazarr = instances.firstWhereOrNull(
      (Instance i) => i.id == bazarrId && i.kind == ServiceKind.bazarr,
    );
    if (bazarr == null) {
      return const BazarrLinkStatus(
        radarr: LinkState(how: LinkHow.none),
        sonarr: LinkState(how: LinkHow.none),
      );
    }
    final BazarrDetectionKey key = (
      bazarrId: bazarrId,
      fingerprint: ref.watch(arrFingerprintProvider),
    );
    final AsyncValue<ArrLinkDetection> detection =
        ref.watch(bazarrLinkDetectionProvider(key));
    final ArrLinkDetection? result = detection.value;

    LinkState state(ServiceKind kind) => resolveLinkState(
          bazarr.links[kind.name],
          result?.of(kind).instanceId,
          <String>{
            for (final Instance i in instances)
              if (i.kind == kind) i.id,
          },
        );

    return BazarrLinkStatus(
      radarr: state(ServiceKind.radarr),
      sonarr: state(ServiceKind.sonarr),
      detection: result,
      detecting: detection.isLoading,
      detectError: detection.hasError ? detection.error : null,
    );
  },
);

/// Re-reads [bazarrId]'s settings and resolves with the fresh result. Never
/// changes a stored choice: picking the detected instance is what returns a
/// row to automatic.
Future<ArrLinkDetection> redetectBazarrLinks(
  WidgetRef ref,
  String bazarrId,
) {
  final BazarrDetectionKey key = (
    bazarrId: bazarrId,
    fingerprint: ref.read(arrFingerprintProvider),
  );
  return ref.refresh(bazarrLinkDetectionProvider(key).future);
}
