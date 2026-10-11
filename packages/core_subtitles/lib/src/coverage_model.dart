import 'package:flutter/foundation.dart' show listEquals;
import 'package:meta/meta.dart';

import 'language_codes.dart';
import 'subtitle_model.dart';

// Series coverage: the language × episode grid, the per-episode language
// lines of the season list, and season gap counts. Pure.

/// One cell of the coverage grid: the episode has that language as a file,
/// embedded, is missing it, or doesn't want it.
enum CoverageCell { missing, present, embedded, unwanted }

/// One column of the coverage grid: a language plus its flags.
@immutable
class CoverageLanguage {
  const CoverageLanguage({
    required this.key,
    required this.code2,
    this.forced = false,
    this.hi = false,
  });

  /// A column for [code2] with the `code2|fh` key filled in.
  CoverageLanguage.of(String code2, {bool forced = false, bool hi = false})
      : this(
          key: subtitleLanguageKey(code2, forced: forced, hi: hi),
          code2: code2,
          forced: forced,
          hi: hi,
        );

  /// `code2|fh`.
  final String key;
  final String code2;
  final bool forced;
  final bool hi;

  @override
  bool operator ==(Object other) =>
      other is CoverageLanguage &&
      other.key == key &&
      other.code2 == code2 &&
      other.forced == forced &&
      other.hi == hi;

  @override
  int get hashCode => Object.hash(key, code2, forced, hi);

  @override
  String toString() => 'CoverageLanguage($key)';
}

/// What the subtitle manager knows about one episode.
@immutable
class CoverageEpisode {
  const CoverageEpisode({
    required this.episodeId,
    required this.season,
    required this.episode,
    this.subtitles = const [],
    this.missing = const [],
    this.audio = const [],
  });

  /// The Sonarr episode id.
  final int episodeId;
  final int season;
  final int episode;

  /// Subtitles it has (files and embedded tracks).
  final List<SubtitleTrack> subtitles;

  /// Languages it still wants, flags included.
  final List<SubtitleTrack> missing;

  /// The audio languages the subtitle manager detected for the file.
  final List<Language> audio;

  @override
  bool operator ==(Object other) =>
      other is CoverageEpisode &&
      other.episodeId == episodeId &&
      other.season == season &&
      other.episode == episode &&
      listEquals(other.subtitles, subtitles) &&
      listEquals(other.missing, missing) &&
      listEquals(other.audio, audio);

  @override
  int get hashCode => Object.hash(
        episodeId,
        season,
        episode,
        Object.hashAll(subtitles),
        Object.hashAll(missing),
        Object.hashAll(audio),
      );
}

/// One episode's row of the grid.
@immutable
class CoverageGridEpisode {
  const CoverageGridEpisode({
    required this.episodeId,
    required this.episode,
    required this.cells,
  });

  final int episodeId;
  final int episode;

  /// One cell per [CoverageGrid.languages] column.
  final List<CoverageCell> cells;

  @override
  bool operator ==(Object other) =>
      other is CoverageGridEpisode &&
      other.episodeId == episodeId &&
      other.episode == episode &&
      listEquals(other.cells, cells);

  @override
  int get hashCode => Object.hash(episodeId, episode, Object.hashAll(cells));
}

/// One season of the grid.
@immutable
class CoverageSeason {
  const CoverageSeason({
    required this.season,
    required this.episodes,
    required this.gaps,
  });

  final int season;

  /// By episode number, ascending.
  final List<CoverageGridEpisode> episodes;

  /// Episodes with at least one missing language.
  final int gaps;

  @override
  bool operator ==(Object other) =>
      other is CoverageSeason &&
      other.season == season &&
      other.gaps == gaps &&
      listEquals(other.episodes, episodes);

  @override
  int get hashCode => Object.hash(season, gaps, Object.hashAll(episodes));
}

/// The language × episode grid for a series.
@immutable
class CoverageGrid {
  const CoverageGrid({required this.languages, required this.seasons});

  final List<CoverageLanguage> languages;

  /// Latest season first.
  final List<CoverageSeason> seasons;

  @override
  bool operator ==(Object other) =>
      other is CoverageGrid &&
      listEquals(other.languages, languages) &&
      listEquals(other.seasons, seasons);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(languages), Object.hashAll(seasons));
}

/// The language × episode grid for a series. Columns are the series
/// profile's languages ([profileColumns]) or, without a profile, every
/// language any episode has; each cell says whether that episode has it as a
/// file, embedded, is missing it, or doesn't want it.
CoverageGrid buildCoverageGrid(
  Iterable<CoverageEpisode> episodes, {
  List<CoverageLanguage>? profileColumns,
}) {
  final languages = profileColumns ?? _collectLanguages(episodes);

  final bySeason = <int, ({List<CoverageGridEpisode> episodes, int gaps})>{};
  for (final ep in episodes) {
    final cells = [for (final lang in languages) _cellFor(ep, lang)];
    final prev =
        bySeason[ep.season] ?? (episodes: <CoverageGridEpisode>[], gaps: 0);
    prev.episodes.add(
      CoverageGridEpisode(
        episodeId: ep.episodeId,
        episode: ep.episode,
        cells: cells,
      ),
    );
    bySeason[ep.season] = (
      episodes: prev.episodes,
      gaps: prev.gaps + (cells.contains(CoverageCell.missing) ? 1 : 0),
    );
  }

  final seasons = [
    for (final e in bySeason.entries)
      CoverageSeason(
        season: e.key,
        episodes: _sortedBy(e.value.episodes, (a, b) => a.episode - b.episode),
        gaps: e.value.gaps,
      ),
  ];
  return CoverageGrid(
    languages: languages,
    seasons: _sortedBy(seasons, (a, b) => b.season - a.season),
  );
}

/// A stable sort, matching `Array.prototype.sort`.
List<T> _sortedBy<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  return [for (final e in indexed) e.$2];
}

List<CoverageLanguage> _collectLanguages(Iterable<CoverageEpisode> episodes) {
  final map = <String, CoverageLanguage>{};
  for (final ep in episodes) {
    for (final s in [...ep.subtitles, ...ep.missing]) {
      final lang = CoverageLanguage.of(s.code2, forced: s.forced, hi: s.hi);
      map.putIfAbsent(lang.key, () => lang);
    }
  }
  return _sortedBy(map.values.toList(), (a, b) => a.code2.compareTo(b.code2));
}

CoverageCell _cellFor(CoverageEpisode ep, CoverageLanguage lang) {
  bool same(SubtitleTrack s) =>
      s.code2 == lang.code2 && s.forced == lang.forced;
  // The manager lists exactly what it still wants, flags included. A plain
  // column is satisfied by an HI subtitle too (as in Bazarr), an HI column
  // only by HI.
  if (ep.missing.any((s) => same(s) && s.hi == lang.hi)) {
    return CoverageCell.missing;
  }
  final subs = ep.subtitles.where((s) => same(s) && (s.hi || !lang.hi));
  if (subs.any((s) => s.isFile)) return CoverageCell.present;
  if (subs.isNotEmpty) return CoverageCell.embedded;
  return CoverageCell.unwanted;
}

/// The language tags of one episode row in the season list.
@immutable
class EpisodeLanguages {
  const EpisodeLanguages({required this.audio, this.chips});

  final List<AudioTag> audio;

  /// Null while the subtitle manager has no data for the episode (request
  /// pending or failed, or the episode not synced yet): nothing to show or
  /// open.
  final List<SubtitleChip>? chips;

  @override
  bool operator ==(Object other) =>
      other is EpisodeLanguages &&
      listEquals(other.audio, audio) &&
      listEquals(other.chips, chips);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(audio),
        chips == null ? null : Object.hashAll(chips!),
      );

  @override
  String toString() => 'EpisodeLanguages(audio: $audio, chips: $chips)';
}

/// Per-episode language tags for the season list, keyed by Sonarr episode
/// id. Driven by Sonarr's [episodes] with a file, so the file's audio
/// ([fileAudio]: episode file id → `mediaInfo.audioLanguages`) still shows
/// when [bazarrEpisodes] is missing or lags behind Sonarr; subtitle chips only
/// for episodes the subtitle manager lists.
Map<int, EpisodeLanguages> buildEpisodeLanguages({
  required Iterable<({int id, int? episodeFileId})> episodes,
  required Map<int, String?> fileAudio,
  Iterable<CoverageEpisode>? bazarrEpisodes,
  String? originalLanguage,
}) {
  final bazarrById = {
    for (final e in bazarrEpisodes ?? const <CoverageEpisode>[]) e.episodeId: e,
  };
  final map = <int, EpisodeLanguages>{};
  for (final ep in episodes) {
    final fileId = ep.episodeFileId;
    if (fileId == null || fileId == 0) continue;
    final be = bazarrById[ep.id];
    final audio = mediaAudioTags(
      fileAudio[fileId],
      be?.audio,
      originalLanguage: originalLanguage,
    );
    // An empty line would only show two bare icons.
    if (be == null && audio.isEmpty) continue;
    map[ep.id] = EpisodeLanguages(
      audio: audio,
      chips: be == null
          ? null
          : buildSubtitleChips(
              buildSubtitleRows(subtitles: be.subtitles, missing: be.missing),
            ),
    );
  }
  return map;
}

/// Episodes of one season that still miss languages, for "Search missing".
List<CoverageEpisode> seasonMissingEpisodes(
  Iterable<CoverageEpisode> episodes,
  int season,
) =>
    [
      for (final ep in episodes)
        if (ep.season == season && ep.missing.isNotEmpty) ep,
    ];

/// How many episodes of [season] still miss at least one language.
int seasonGapCount(Iterable<CoverageEpisode> episodes, int season) =>
    seasonMissingEpisodes(episodes, season).length;
