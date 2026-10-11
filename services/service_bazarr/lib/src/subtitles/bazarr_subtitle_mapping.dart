import 'package:core_subtitles/core_subtitles.dart';

import '../models/bazarr_models.dart';

// Bazarr's models mapped onto the neutral subtitle types in core_subtitles,
// which the shared widgets and the Radarr/Sonarr bridge work with.

extension BazarrSubtitleTrack on BazarrSubtitle {
  /// This subtitle as a neutral track. A non-empty [path] marks an external
  /// file; without one it is a track embedded in the video.
  SubtitleTrack toTrack() => SubtitleTrack(
        code2: code2,
        name: name,
        code3: code3.isEmpty ? null : code3,
        forced: forced,
        hi: hi,
        path: path,
        id: id,
        embeddedTrackId: embeddedTrackId,
        fileSize: fileSize,
      );
}

extension BazarrLanguageToLanguage on BazarrLanguage {
  /// This language as a neutral [Language], normalised through the language
  /// table where it is known.
  Language toLanguage() =>
      normalizeLanguage(code2.isNotEmpty ? code2 : name) ??
      Language(code2: code2, code3: code3, name: name);
}

extension BazarrMovieSubtitles on BazarrMovie {
  /// Rows for every subtitle the movie has and every language it still wants.
  List<SubtitleRow> subtitleRows() => buildSubtitleRows(
        subtitles: subtitles.map((BazarrSubtitle s) => s.toTrack()),
        missing: missingSubtitles.map((BazarrSubtitle s) => s.toTrack()),
      );

  List<Language> audioLanguages() => audioLanguage
      .map((BazarrLanguage l) => l.toLanguage())
      .toList(growable: false);
}

extension BazarrEpisodeSubtitles on BazarrEpisode {
  /// Rows for every subtitle the episode has and every language it still
  /// wants.
  List<SubtitleRow> subtitleRows() => buildSubtitleRows(
        subtitles: subtitles.map((BazarrSubtitle s) => s.toTrack()),
        missing: missingSubtitles.map((BazarrSubtitle s) => s.toTrack()),
      );

  /// This episode as an input to the coverage grid and episode languages.
  CoverageEpisode toCoverageEpisode() => CoverageEpisode(
        episodeId: sonarrEpisodeId,
        season: season ?? 0,
        episode: episode ?? 0,
        subtitles: subtitles
            .map((BazarrSubtitle s) => s.toTrack())
            .toList(growable: false),
        missing: missingSubtitles
            .map((BazarrSubtitle s) => s.toTrack())
            .toList(growable: false),
        audio: audioLanguage
            .map((BazarrLanguage l) => l.toLanguage())
            .toList(growable: false),
      );
}
