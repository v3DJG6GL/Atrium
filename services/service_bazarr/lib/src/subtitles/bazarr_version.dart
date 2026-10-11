import 'package:core_models/core_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../bazarr_providers.dart';
import '../models/bazarr_models.dart';

/// Dotted-version comparison for Bazarr's capability gates.
///
/// Tolerates the shapes Bazarr reports: a leading "v" ("v1.6.2"), and
/// pre-release or build suffixes ("1.6.3-beta.8", "1.2.0+abc"), which are
/// dropped. A pre-release therefore compares equal to its release — right for
/// feature gates, since a feature ships in the betas leading up to a version.
/// Missing parts count as 0.
///
/// Negative when [a] < [b], positive when [a] > [b], 0 when equal.
int compareVersions(String a, String b) {
  final List<int> pa = _parts(a);
  final List<int> pb = _parts(b);
  final int len = pa.length > pb.length ? pa.length : pb.length;
  for (int i = 0; i < len; i++) {
    final int da = i < pa.length ? pa[i] : 0;
    final int db = i < pb.length ? pb[i] : 0;
    if (da != db) {
      return da - db;
    }
  }
  return 0;
}

final RegExp _leadingV = RegExp('^v', caseSensitive: false);
final RegExp _suffix = RegExp(r'[-+\s]');
final RegExp _leadingDigits = RegExp(r'^\d+');

List<int> _parts(String version) {
  final String core =
      version.trim().replaceFirst(_leadingV, '').split(_suffix).first;
  return core.split('.').map((String p) {
    final String? digits = _leadingDigits.firstMatch(p)?.group(0);
    return digits == null ? 0 : int.parse(digits);
  }).toList();
}

/// True when [version] is [min] or newer. False when the version is unknown.
bool versionAtLeast(String? version, String min) {
  if (version == null || version.isEmpty) {
    return false;
  }
  return compareVersions(version, min) >= 0;
}

/// Optional Bazarr features and the first release that has each.
enum BazarrFeature {
  /// Searches and downloads run as background jobs, listed by /system/jobs;
  /// before that the requests block until done.
  jobs('1.5.6'),

  /// PATCH /subtitles action=extract: embedded track → file.
  extract('1.6.1'),

  /// action=translate on an embedded track via `subtitles_id`.
  translateEmbedded('1.6.2');

  const BazarrFeature(this.minVersion);

  final String minVersion;
}

/// Which features a Bazarr version supports. An unknown version (the status
/// call failed or hasn't answered yet) gets nothing optional — a hidden action
/// is better than one that fails with a 404 or 400.
@immutable
class BazarrCapabilities {
  const BazarrCapabilities.forVersion(this.version);

  final String? version;

  bool supports(BazarrFeature feature) =>
      versionAtLeast(version, feature.minVersion);

  @override
  bool operator ==(Object other) =>
      other is BazarrCapabilities && other.version == version;

  @override
  int get hashCode => version.hashCode;
}

/// Whether the gates rest on a real version: [checking] while the status call
/// runs, [unreadable] when it failed or answered without a version.
enum BazarrVersionState { checking, unreadable, known }

final RegExp _realVersion = RegExp(r'^v?\d', caseSensitive: false);

/// [hasStatus] is whether a status response is at hand (even from before a
/// failed refetch); [failed] whether the latest status call failed.
BazarrVersionState bazarrVersionState({
  String? version,
  required bool hasStatus,
  required bool failed,
}) {
  if (!hasStatus) {
    return failed ? BazarrVersionState.unreadable : BazarrVersionState.checking;
  }
  return _realVersion.hasMatch(version?.trim() ?? '')
      ? BazarrVersionState.known
      : BazarrVersionState.unreadable;
}

/// Why a version-gated feature is off, for its disabled row. Null when
/// [capabilities] says the feature is supported.
String? versionGateNote(
  BazarrVersionState state,
  BazarrFeature feature, [
  BazarrCapabilities? capabilities,
]) {
  if (capabilities != null && capabilities.supports(feature)) {
    return null;
  }
  return switch (state) {
    BazarrVersionState.checking => 'Checking Bazarr version…',
    BazarrVersionState.unreadable => "Couldn't read Bazarr's version",
    BazarrVersionState.known => 'Needs Bazarr ${feature.minVersion} or later',
  };
}

/// Note for an embedded track Bazarr has no row id for yet.
const String embeddedNotIndexedNote = "Bazarr hasn't indexed this track yet";

/// A Bazarr instance's version and what it unlocks.
@immutable
class BazarrVersionInfo {
  const BazarrVersionInfo({
    required this.state,
    required this.capabilities,
    this.version,
  });

  final BazarrVersionState state;
  final BazarrCapabilities capabilities;
  final String? version;

  bool supports(BazarrFeature feature) => capabilities.supports(feature);

  /// [versionGateNote] for this instance; null when [feature] is supported.
  String? gateNote(BazarrFeature feature) =>
      versionGateNote(state, feature, capabilities);

  @override
  bool operator ==(Object other) =>
      other is BazarrVersionInfo &&
      other.state == state &&
      other.capabilities == capabilities &&
      other.version == version;

  @override
  int get hashCode => Object.hash(state, capabilities, version);
}

/// Version state and capabilities of a Bazarr, from its (hourly refreshed)
/// system status.
final bazarrVersionInfoProvider =
    Provider.family<BazarrVersionInfo, Instance>((Ref ref, Instance instance) {
  final AsyncValue<BazarrSystemStatus> status =
      ref.watch(bazarrSystemStatusProvider(instance));
  final String? version = status.value?.bazarrVersion;
  final BazarrVersionState state = bazarrVersionState(
    version: version,
    hasStatus: status.hasValue,
    failed: status.hasError,
  );
  return BazarrVersionInfo(
    state: state,
    capabilities: BazarrCapabilities.forVersion(
      state == BazarrVersionState.known ? version : null,
    ),
    version: version,
  );
});
