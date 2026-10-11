import 'package:meta/meta.dart';

import '../models/bazarr_models.dart';

/// The single place Bazarr subtitle request parameters are encoded.
///
/// Bazarr's routes disagree on how booleans are spelled (verified against
/// bazarr/api/ at v1.6.2), so each request type gets its own builder here and
/// nothing else formats them:
///
///   - PATCH /subtitles (sync, translate, extract, mods) compares `forced`,
///     `hi` and `original_format` to the exact string "True".
///   - POST /movies|episodes/subtitles (upload) compares to lowercase "true".
///   - PATCH /movies|episodes/subtitles (search one language) capitalizes, so
///     either works; it gets "True"/"False" like Bazarr's own UI sends.
///   - POST /providers/* (download a manual-search result) gets back exactly
///     the strings the search returned.

/// A movie or an episode, as Bazarr addresses them (by Radarr/Sonarr ids).
@immutable
sealed class SubtitleTarget {
  const SubtitleTarget();

  /// Stable key for busy rows and caches: `m<radarrId>` or `e<episodeId>`.
  String get key;

  /// Bazarr's `type` value in PATCH /subtitles: `movie` or `episode`.
  String get typeName;

  /// Bazarr's `id` value in PATCH /subtitles: the Radarr id of a movie, the
  /// Sonarr episode id of an episode.
  int get mediaId;
}

/// A Radarr movie, addressed by its Radarr id.
final class MovieTarget extends SubtitleTarget {
  const MovieTarget(this.radarrId);

  final int radarrId;

  @override
  String get key => 'm$radarrId';

  @override
  String get typeName => 'movie';

  @override
  int get mediaId => radarrId;

  @override
  bool operator ==(Object other) =>
      other is MovieTarget && other.radarrId == radarrId;

  @override
  int get hashCode => Object.hash('movie', radarrId);

  @override
  String toString() => 'MovieTarget($radarrId)';
}

/// A Sonarr episode, addressed by its series and episode ids.
final class EpisodeTarget extends SubtitleTarget {
  const EpisodeTarget(this.seriesId, this.episodeId);

  final int seriesId;
  final int episodeId;

  @override
  String get key => 'e$episodeId';

  @override
  String get typeName => 'episode';

  @override
  int get mediaId => episodeId;

  @override
  bool operator ==(Object other) =>
      other is EpisodeTarget &&
      other.seriesId == seriesId &&
      other.episodeId == episodeId;

  @override
  int get hashCode => Object.hash('episode', seriesId, episodeId);

  @override
  String toString() => 'EpisodeTarget($seriesId, $episodeId)';
}

/// One language to search or upload: the code plus its forced/HI flags.
@immutable
class LanguageChoice {
  const LanguageChoice({
    required this.code2,
    this.forced = false,
    this.hi = false,
  });

  final String code2;
  final bool forced;
  final bool hi;

  @override
  bool operator ==(Object other) =>
      other is LanguageChoice &&
      other.code2 == code2 &&
      other.forced == forced &&
      other.hi == hi;

  @override
  int get hashCode => Object.hash(code2, forced, hi);

  @override
  String toString() => 'LanguageChoice($code2, forced: $forced, hi: $hi)';
}

/// "True" / "False", as most Bazarr routes expect.
String boolCap(bool b) => b ? 'True' : 'False';

/// "true" / "false", as the upload route expects.
String boolLower(bool b) => b ? 'true' : 'false';

/// The id params of the /movies|episodes/subtitles, /providers (POST) and
/// /blacklist routes.
Map<String, Object> targetParams(SubtitleTarget target) => switch (target) {
      MovieTarget(:final int radarrId) => <String, Object>{
          'radarrid': radarrId,
        },
      EpisodeTarget(:final int seriesId, :final int episodeId) =>
        <String, Object>{'seriesid': seriesId, 'episodeid': episodeId},
    };

/// `api/movies/subtitles` or `api/episodes/subtitles`.
String subtitlesRoute(SubtitleTarget target) => switch (target) {
      MovieTarget() => 'api/movies/subtitles',
      EpisodeTarget() => 'api/episodes/subtitles',
    };

/// `api/providers/movies` or `api/providers/episodes`.
String providersRoute(SubtitleTarget target) => switch (target) {
      MovieTarget() => 'api/providers/movies',
      EpisodeTarget() => 'api/providers/episodes',
    };

/// `api/movies/blacklist` or `api/episodes/blacklist`.
String blacklistRoute(SubtitleTarget target) => switch (target) {
      MovieTarget() => 'api/movies/blacklist',
      EpisodeTarget() => 'api/episodes/blacklist',
    };

/// GET /providers/movies|episodes (manual search). The episodes route takes
/// only `episodeid`.
Map<String, Object> manualSearchParams(SubtitleTarget target) =>
    switch (target) {
      MovieTarget(:final int radarrId) => <String, Object>{
          'radarrid': radarrId,
        },
      EpisodeTarget(:final int episodeId) => <String, Object>{
          'episodeid': episodeId,
        },
    };

/// PATCH /movies|episodes/subtitles: search one language.
Map<String, Object> searchParams(SubtitleTarget target, LanguageChoice lang) =>
    <String, Object>{
      ...targetParams(target),
      'language': lang.code2,
      'forced': boolCap(lang.forced),
      'hi': boolCap(lang.hi),
    };

/// POST /movies|episodes/subtitles (multipart): upload a file.
Map<String, Object> uploadFields(SubtitleTarget target, LanguageChoice lang) =>
    <String, Object>{
      ...targetParams(target),
      'language': lang.code2,
      'forced': boolLower(lang.forced),
      'hi': boolLower(lang.hi),
    };

/// DELETE /movies|episodes/subtitles: remove an external file. The path is
/// sent exactly as Bazarr reported it.
Map<String, Object> deleteParams(SubtitleTarget target, BazarrSubtitle sub) =>
    <String, Object>{
      ...targetParams(target),
      'language': sub.code2.isNotEmpty ? sub.code2 : sub.code3,
      'forced': boolCap(sub.forced),
      'hi': boolCap(sub.hi),
      'path': sub.path ?? '',
    };

/// POST /providers/movies|episodes: download a manual-search result. Echoes
/// the result's own flag strings.
Map<String, Object> downloadResultParams(
  SubtitleTarget target,
  BazarrSubtitleSearchResult result,
) =>
    <String, Object>{
      ...targetParams(target),
      'provider': result.provider,
      'subtitle': result.subtitle,
      'hi': result.hearingImpaired,
      'forced': result.forced,
      'original_format':
          result.originalFormat.isEmpty ? 'False' : result.originalFormat,
    };

// --- PATCH /subtitles tools ---

/// One action of Bazarr's subtitle tools (PATCH /subtitles).
@immutable
sealed class SubtitleToolAction {
  const SubtitleToolAction();

  /// Re-sync the subtitle against the audio.
  const factory SubtitleToolAction.sync() = SyncToolAction;

  /// Translate into the language [to] (a code2).
  const factory SubtitleToolAction.translate(String to) = TranslateToolAction;

  /// Extract an embedded track into a file (Bazarr 1.6.1+).
  const factory SubtitleToolAction.extract() = ExtractToolAction;

  /// Run one of the [cleanupMods] by its id.
  const factory SubtitleToolAction.mod(String mod) = ModToolAction;

  /// Shift every cue by [ms] milliseconds (negative is earlier).
  const factory SubtitleToolAction.shift(int ms) = ShiftToolAction;

  /// Retime from one frame rate to another.
  const factory SubtitleToolAction.fps(num from, num to) = FpsToolAction;

  /// The `action` query value.
  String get action;
}

final class SyncToolAction extends SubtitleToolAction {
  const SyncToolAction();

  @override
  String get action => 'sync';

  @override
  bool operator ==(Object other) => other is SyncToolAction;

  @override
  int get hashCode => (SyncToolAction).hashCode;
}

final class TranslateToolAction extends SubtitleToolAction {
  const TranslateToolAction(this.to);

  final String to;

  @override
  String get action => 'translate';

  @override
  bool operator ==(Object other) =>
      other is TranslateToolAction && other.to == to;

  @override
  int get hashCode => Object.hash('translate', to);
}

final class ExtractToolAction extends SubtitleToolAction {
  const ExtractToolAction();

  @override
  String get action => 'extract';

  @override
  bool operator ==(Object other) => other is ExtractToolAction;

  @override
  int get hashCode => (ExtractToolAction).hashCode;
}

final class ModToolAction extends SubtitleToolAction {
  const ModToolAction(this.mod);

  final String mod;

  @override
  String get action => mod;

  @override
  bool operator ==(Object other) => other is ModToolAction && other.mod == mod;

  @override
  int get hashCode => Object.hash('mod', mod);
}

final class ShiftToolAction extends SubtitleToolAction {
  const ShiftToolAction(this.ms);

  final int ms;

  @override
  String get action => buildShiftAction(ms);

  @override
  bool operator ==(Object other) => other is ShiftToolAction && other.ms == ms;

  @override
  int get hashCode => Object.hash('shift', ms);
}

final class FpsToolAction extends SubtitleToolAction {
  const FpsToolAction(this.from, this.to);

  final num from;
  final num to;

  @override
  String get action => buildFpsAction(from, to);

  @override
  bool operator ==(Object other) =>
      other is FpsToolAction && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash('fps', from, to);
}

/// Query params for PATCH /subtitles.
///
/// An external file is addressed by its path, sent exactly as Bazarr reported
/// it (already path-mapped; Bazarr checks it with os.path.exists). An embedded
/// track has no path and is addressed by its subtitle row id, which `extract`
/// and translating an embedded track require.
Map<String, Object> toolParams(
  SubtitleTarget target,
  BazarrSubtitle sub,
  SubtitleToolAction action,
) {
  final String? path = sub.path;
  final int? id = sub.id;
  return <String, Object>{
    'action': action.action,
    // translate targets a language; everything else names the file's own.
    'language': switch (action) {
      TranslateToolAction(:final String to) => to,
      _ => sub.code2,
    },
    'type': target.typeName,
    'id': target.mediaId,
    'forced': boolCap(sub.forced),
    'hi': boolCap(sub.hi),
    if (path != null && path.isNotEmpty)
      'path': path
    else if (id != null)
      'subtitles_id': id,
  };
}

/// One of Bazarr's text clean-up mods.
@immutable
class CleanupMod {
  const CleanupMod(this.id, this.label, this.description);

  /// The `action` value Bazarr expects.
  final String id;
  final String label;
  final String description;
}

/// Bazarr's text clean-up mods, in the order its own Tools menu lists them.
/// They only work on .srt files.
const List<CleanupMod> cleanupMods = <CleanupMod>[
  CleanupMod(
    'remove_HI',
    'Remove hearing-impaired tags',
    '[MUSIC], (laughs), speaker names',
  ),
  CleanupMod(
    'remove_tags',
    'Remove style tags',
    'Italics, bold, colors and positioning',
  ),
  CleanupMod('emoji', 'Remove emoji', 'Strips emoji characters'),
  CleanupMod(
    'OCR_fixes',
    'Fix OCR errors',
    'Common misreads from image-based subtitles',
  ),
  CleanupMod('common', 'Common fixes', 'Spacing, punctuation and line breaks'),
  CleanupMod(
    'fix_uppercase',
    'Fix all-caps text',
    'Converts shouted lines to sentence case',
  ),
  CleanupMod(
    'reverse_rtl',
    'Reverse right-to-left',
    'For Hebrew or Arabic shown backwards',
  ),
];

/// The shift_offset mod for a signed offset in milliseconds. Bazarr's own UI
/// negates every component for a negative shift, so this does too.
String buildShiftAction(int totalMs) {
  final int sign = totalMs < 0 ? -1 : 1;
  int rest = totalMs.abs();
  final int h = rest ~/ 3600000;
  rest -= h * 3600000;
  final int m = rest ~/ 60000;
  rest -= m * 60000;
  final int s = rest ~/ 1000;
  final int ms = rest - s * 1000;
  int v(int n) => n == 0 ? 0 : sign * n;
  return 'shift_offset(h=${v(h)},m=${v(m)},s=${v(s)},ms=${v(ms)})';
}

/// The change_FPS mod: retime a subtitle made for one frame rate to another.
/// Whole numbers print without a fraction (`25`, not `25.0`).
String buildFpsAction(num from, num to) =>
    'change_FPS(from=${_formatNum(from)},to=${_formatNum(to)})';

String _formatNum(num n) {
  if (n is double && n.isFinite && n == n.truncateToDouble()) {
    return n.toInt().toString();
  }
  return n.toString();
}

/// Common video frame rates, for the frame-rate picker.
const List<num> frameRates = <num>[23.976, 24, 25, 29.97, 30, 50, 59.94, 60];

/// Is this an external file Bazarr's text tools can edit? (.srt only.)
bool isModifiable(BazarrSubtitle sub) {
  final String? path = sub.path;
  return path != null && path.toLowerCase().endsWith('.srt');
}

/// A track inside the video file rather than a file next to it.
bool isEmbedded(BazarrSubtitle sub) {
  final String? path = sub.path;
  return path == null || path.isEmpty;
}
