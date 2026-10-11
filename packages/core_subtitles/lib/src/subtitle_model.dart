import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'language_codes.dart';

// View models for subtitle and audio-language UI, shared by the movie card,
// the episode rows and sheet, the coverage grid and the Bazarr library.
// Pure: no widgets, no services.

/// Whether a subtitle exists as an external file, as a track inside the
/// video, or is wanted but missing.
enum SubtitleState { present, embedded, missing }

/// One subtitle a subtitle manager has, or one language it still wants.
///
/// A track with a non-empty [path] is an external file
/// ([SubtitleState.present]); without one it is a track embedded in the
/// video ([SubtitleState.embedded]). Missing languages are passed as tracks
/// too, in their own list (see [buildSubtitleRows]).
@immutable
class SubtitleTrack {
  const SubtitleTrack({
    required this.code2,
    required this.name,
    this.code3,
    this.forced = false,
    this.hi = false,
    this.path,
    this.id,
    this.embeddedTrackId,
    this.fileSize,
  });

  final String code2;
  final String name;
  final String? code3;
  final bool forced;

  /// Hearing impaired.
  final bool hi;

  /// The external file's path, exactly as the subtitle manager reported it.
  final String? path;

  /// The subtitle manager's own id for the subtitle, when it has one.
  final int? id;

  /// The stream index of an embedded track (Bazarr 1.6+).
  final int? embeddedTrackId;

  /// Size of the external file in bytes.
  final int? fileSize;

  /// An external file rather than a track inside the video.
  bool get isFile => path != null && path!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is SubtitleTrack &&
      other.code2 == code2 &&
      other.name == name &&
      other.code3 == code3 &&
      other.forced == forced &&
      other.hi == hi &&
      other.path == path &&
      other.id == id &&
      other.embeddedTrackId == embeddedTrackId &&
      other.fileSize == fileSize;

  @override
  int get hashCode => Object.hash(
        code2,
        name,
        code3,
        forced,
        hi,
        path,
        id,
        embeddedTrackId,
        fileSize,
      );

  @override
  String toString() =>
      'SubtitleTrack($code2, forced: $forced, hi: $hi, path: $path, '
      'id: $id, embeddedTrackId: $embeddedTrackId)';
}

/// One row of a subtitle list.
@immutable
class SubtitleRow {
  const SubtitleRow({
    required this.key,
    required this.code2,
    required this.name,
    required this.forced,
    required this.hi,
    required this.state,
    this.track,
  });

  /// Stable across refetches: language + flags + file.
  final String key;
  final String code2;
  final String name;
  final bool forced;
  final bool hi;
  final SubtitleState state;

  /// The subtitle it stands for (present/embedded rows), or what is still
  /// wanted (missing rows).
  final SubtitleTrack? track;

  @override
  bool operator ==(Object other) =>
      other is SubtitleRow &&
      other.key == key &&
      other.code2 == code2 &&
      other.name == name &&
      other.forced == forced &&
      other.hi == hi &&
      other.state == state &&
      other.track == track;

  @override
  int get hashCode => Object.hash(key, code2, name, forced, hi, state, track);

  @override
  String toString() => 'SubtitleRow($key, $state)';
}

String _flags(bool forced, bool hi) => '${forced ? 'f' : ''}${hi ? 'h' : ''}';

/// The `code2|fh` key shared by chips and coverage columns.
String subtitleLanguageKey(
  String code2, {
  bool forced = false,
  bool hi = false,
}) =>
    '$code2|${_flags(forced, hi)}';

const Map<SubtitleState, int> _rowOrder = {
  SubtitleState.missing: 0,
  SubtitleState.present: 1,
  SubtitleState.embedded: 2,
};

const Map<SubtitleState, int> _chipRank = {
  SubtitleState.present: 0,
  SubtitleState.embedded: 1,
  SubtitleState.missing: 2,
};

/// A stable sort (Dart's [List.sort] is not guaranteed to be), matching
/// `Array.prototype.sort`.
List<T> _stableSorted<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  return [for (final e in indexed) e.$2];
}

/// One row per subtitle the manager has and per language it still wants.
/// Missing languages come first (they are what needs attention), then
/// external files, then embedded tracks; each group by language name.
List<SubtitleRow> buildSubtitleRows({
  Iterable<SubtitleTrack>? subtitles,
  Iterable<SubtitleTrack>? missing,
}) {
  final rows = <SubtitleRow>[];
  final seen = <String, int>{};
  for (final sub in subtitles ?? const <SubtitleTrack>[]) {
    // Before Bazarr 1.6 embedded tracks carry no id, so two tracks of one
    // language would share a key; number the repeats.
    final where = sub.path ?? 'track${sub.embeddedTrackId ?? sub.id ?? ''}';
    final base = '${sub.code2}|${_flags(sub.forced, sub.hi)}|$where';
    final n = seen[base] ?? 0;
    seen[base] = n + 1;
    rows.add(
      SubtitleRow(
        key: n == 0 ? base : '$base#$n',
        code2: sub.code2,
        name: sub.name,
        forced: sub.forced,
        hi: sub.hi,
        state: sub.isFile ? SubtitleState.present : SubtitleState.embedded,
        track: sub,
      ),
    );
  }
  for (final miss in missing ?? const <SubtitleTrack>[]) {
    rows.add(
      SubtitleRow(
        key: '${miss.code2}|${_flags(miss.forced, miss.hi)}|missing',
        code2: miss.code2,
        name: miss.name,
        forced: miss.forced,
        hi: miss.hi,
        state: SubtitleState.missing,
        track: miss,
      ),
    );
  }
  return _stableSorted(rows, (a, b) {
    final byState = _rowOrder[a.state]! - _rowOrder[b.state]!;
    if (byState != 0) return byState;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// A compact subtitle tag for overview lines.
@immutable
class SubtitleChip {
  const SubtitleChip({
    required this.key,
    required this.code2,
    required this.forced,
    required this.hi,
    required this.state,
  });

  /// `code2|fh`.
  final String key;
  final String code2;
  final bool forced;
  final bool hi;
  final SubtitleState state;

  @override
  bool operator ==(Object other) =>
      other is SubtitleChip &&
      other.key == key &&
      other.code2 == code2 &&
      other.forced == forced &&
      other.hi == hi &&
      other.state == state;

  @override
  int get hashCode => Object.hash(key, code2, forced, hi, state);

  @override
  String toString() => 'SubtitleChip($key, $state)';
}

/// Compact chips for overview lines: one per language + flag combination,
/// keeping the best state (a file beats an embedded track beats missing), in
/// a stable order: present, embedded, then missing, by code.
List<SubtitleChip> buildSubtitleChips(Iterable<SubtitleRow> rows) {
  final best = <String, SubtitleChip>{};
  for (final row in rows) {
    final key = subtitleLanguageKey(row.code2, forced: row.forced, hi: row.hi);
    final prev = best[key];
    if (prev == null || _chipRank[row.state]! < _chipRank[prev.state]!) {
      best[key] = SubtitleChip(
        key: key,
        code2: row.code2,
        forced: row.forced,
        hi: row.hi,
        state: row.state,
      );
    }
  }
  return _stableSorted(best.values.toList(), (a, b) {
    final byState = _chipRank[a.state]! - _chipRank[b.state]!;
    return byState != 0 ? byState : a.code2.compareTo(b.code2);
  });
}

/// "3/4": languages present (file or embedded) out of all chips' languages.
({int have, int total}) subtitleCoverage(Iterable<SubtitleChip> chips) {
  var have = 0;
  var total = 0;
  for (final c in chips) {
    total++;
    if (c.state != SubtitleState.missing) have++;
  }
  return (have: have, total: total);
}

/// One audio language of a file.
@immutable
class AudioTag {
  const AudioTag({
    required this.code2,
    required this.name,
    this.original = false,
  });

  final String code2;
  final String name;

  /// The production's own language (Radarr/Sonarr originalLanguage).
  final bool original;

  @override
  bool operator ==(Object other) =>
      other is AudioTag &&
      other.code2 == code2 &&
      other.name == name &&
      other.original == original;

  @override
  int get hashCode => Object.hash(code2, name, original);

  @override
  String toString() => 'AudioTag($code2, $name, original: $original)';
}

/// Audio tags from the arr's slash-joined `mediaInfo.audioLanguages`
/// ("eng/eng/ger"), one per language however many tracks carry it. Marks the
/// original language (an arr `originalLanguage.name`) when known.
List<AudioTag> audioTagsFromArr(
  String? slashJoined, {
  String? originalLanguage,
}) =>
    _tag(parseLanguageList(slashJoined), originalLanguage);

/// Audio tags from languages a subtitle manager already identified (Bazarr's
/// `audio_language`). A language the code table lacks is kept as given.
List<AudioTag> audioTagsFromLanguages(
  Iterable<Language> languages, {
  String? originalLanguage,
}) {
  final seen = <String>{};
  final langs = <Language>[];
  for (final a in languages) {
    final lang = normalizeLanguage(a.code2) ??
        normalizeLanguage(a.name) ??
        // Already identified; keep a language our table lacks.
        (a.code2.isNotEmpty ? a : null);
    if (lang != null && seen.add(lang.code2)) langs.add(lang);
  }
  return _tag(langs, originalLanguage);
}

List<AudioTag> _tag(List<Language> langs, String? originalLanguage) {
  final original = normalizeLanguage(originalLanguage);
  // The arr names regional originals ("Portuguese (Brazil)" → pb) that file
  // tracks only tag by base language (por → pt): match the base only when no
  // track matches exactly, so a Spanish film's Latino dub isn't original too.
  final exact = original != null && langs.any((l) => l.code2 == original.code2);
  bool isOriginal(String code2) {
    if (original == null) return false;
    return exact
        ? code2 == original.code2
        : baseLanguageCode(original.code2) == baseLanguageCode(code2);
  }

  return [
    for (final l in langs)
      AudioTag(code2: l.code2, name: l.name, original: isOriginal(l.code2)),
  ];
}

/// Audio tags for one movie or episode file: the arr's probed
/// `mediaInfo.audioLanguages` (Radarr and Sonarr share the shape), else the
/// subtitle manager's audio languages. Parsed first, so a file with only
/// untagged tracks ("und/und") still falls back to [bazarrAudio].
List<AudioTag> mediaAudioTags(
  String? arrAudio,
  Iterable<Language>? bazarrAudio, {
  String? originalLanguage,
}) {
  final tags = audioTagsFromArr(arrAudio, originalLanguage: originalLanguage);
  if (tags.isNotEmpty) return tags;
  return audioTagsFromLanguages(
    bazarrAudio ?? const <Language>[],
    originalLanguage: originalLanguage,
  );
}

/// How many equal-width chips fit in [available] px before a "+N" chip is
/// needed. Uses the whole width first: all chips show if they fit, otherwise
/// as many as fit next to the "+N" chip.
int fitChips({
  required int count,
  required double available,
  required double chipWidth,
  required double gap,
  required double plusWidth,
}) {
  if (count <= 0 || available <= 0) return 0;
  final all = count * chipWidth + (count - 1) * gap;
  if (all <= available) return count;
  final step = chipWidth + gap;
  if (step <= 0) return count - 1;
  // n chips, each followed by a gap, then the "+N" chip.
  final n = ((available - plusWidth) / step).floor();
  return math.max(0, math.min(count - 1, n));
}
