import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';

import '../language_codes.dart';
import '../subtitle_model.dart';
import 'subtitles_providers.dart';

// The arr → subtitle-manager bridge.
//
// Service packages must not import each other, yet the Radarr movie page and
// the Sonarr series page show subtitles that belong to Bazarr. So Radarr and
// Sonarr depend only on this neutral interface; `service_bazarr` implements
// it, and `app/` overrides `subtitlesBridgeProvider` with that
// implementation at bootstrap. Without an override the no-op default renders
// nothing, so the arr screens work unchanged without Bazarr.

/// What the Radarr movie page knows about a movie, for its subtitles section.
@immutable
class MovieSubtitlesRef {
  const MovieSubtitlesRef({
    required this.radarrId,
    required this.title,
    this.audioLanguages,
    this.videoFps,
    this.originalLanguage,
  });

  /// The Radarr movie id.
  final int radarrId;
  final String title;

  /// The file's slash-joined `mediaInfo.audioLanguages`.
  final String? audioLanguages;

  /// The file's `mediaInfo.videoFps`.
  final double? videoFps;

  /// Radarr's `originalLanguage.name`.
  final String? originalLanguage;

  @override
  bool operator ==(Object other) =>
      other is MovieSubtitlesRef &&
      other.radarrId == radarrId &&
      other.title == title &&
      other.audioLanguages == audioLanguages &&
      other.videoFps == videoFps &&
      other.originalLanguage == originalLanguage;

  @override
  int get hashCode => Object.hash(
        radarrId,
        title,
        audioLanguages,
        videoFps,
        originalLanguage,
      );
}

/// What the Sonarr series page knows about one episode, for the episode
/// subtitles sheet.
@immutable
class EpisodeSubtitlesInfo {
  const EpisodeSubtitlesInfo({
    required this.episodeId,
    required this.season,
    required this.episode,
    required this.title,
    this.mediaLine,
    this.audioLanguages,
    this.videoFps,
  });

  /// The Sonarr episode id.
  final int episodeId;
  final int season;
  final int episode;
  final String title;

  /// A ready-made summary of the file ("1080p · x265 · 1.2 GB").
  final String? mediaLine;

  /// The file's slash-joined `mediaInfo.audioLanguages`.
  final String? audioLanguages;

  /// The file's `mediaInfo.videoFps`.
  final double? videoFps;

  @override
  bool operator ==(Object other) =>
      other is EpisodeSubtitlesInfo &&
      other.episodeId == episodeId &&
      other.season == season &&
      other.episode == episode &&
      other.title == title &&
      other.mediaLine == mediaLine &&
      other.audioLanguages == audioLanguages &&
      other.videoFps == videoFps;

  @override
  int get hashCode => Object.hash(
        episodeId,
        season,
        episode,
        title,
        mediaLine,
        audioLanguages,
        videoFps,
      );
}

/// What the Sonarr series page knows about a series.
///
/// [episodeInfo] looks up an episode's details from the page's current
/// data; it is left out of `==`, since a new closure doesn't mean a
/// different series.
@immutable
class SeriesSubtitlesRef {
  const SeriesSubtitlesRef({
    required this.seriesId,
    required this.title,
    this.originalLanguage,
    this.episodeInfo,
  });

  /// The Sonarr series id.
  final int seriesId;
  final String title;

  /// Sonarr's `originalLanguage.name`.
  final String? originalLanguage;

  /// Details of one of the series' episodes, by Sonarr episode id; null when
  /// the page doesn't have it.
  final EpisodeSubtitlesInfo? Function(int episodeId)? episodeInfo;

  @override
  bool operator ==(Object other) =>
      other is SeriesSubtitlesRef &&
      other.seriesId == seriesId &&
      other.title == title &&
      other.originalLanguage == originalLanguage;

  @override
  int get hashCode => Object.hash(seriesId, title, originalLanguage);
}

/// The subtitle tags of one episode, for its line in the season list.
@immutable
class EpisodeSubtitleTags {
  const EpisodeSubtitleTags({
    required this.chips,
    this.bazarrAudio = const [],
  });

  final List<SubtitleChip> chips;

  /// The audio languages Bazarr detected, the fallback when the file's own
  /// tags are missing or untagged (see `mediaAudioTags`).
  final List<Language> bazarrAudio;

  @override
  bool operator ==(Object other) =>
      other is EpisodeSubtitleTags &&
      listEquals(other.chips, chips) &&
      listEquals(other.bazarrAudio, bazarrAudio);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(chips), Object.hashAll(bazarrAudio));
}

/// Subtitle data for a Sonarr series, as the series page sees it.
@immutable
sealed class SeriesSubtitles {
  const SeriesSubtitles();
}

/// No Bazarr serves this Sonarr: show no subtitle UI.
final class SeriesSubtitlesOff extends SeriesSubtitles {
  const SeriesSubtitlesOff();

  @override
  bool operator ==(Object other) => other is SeriesSubtitlesOff;

  @override
  int get hashCode => (SeriesSubtitlesOff).hashCode;
}

/// A Bazarr serves this Sonarr, but its data isn't usable yet (loading,
/// failed, or the series not synced).
final class SeriesSubtitlesPending extends SeriesSubtitles {
  const SeriesSubtitlesPending();

  @override
  bool operator ==(Object other) => other is SeriesSubtitlesPending;

  @override
  int get hashCode => (SeriesSubtitlesPending).hashCode;
}

/// Bazarr's data for the series.
final class SeriesSubtitlesReady extends SeriesSubtitles {
  const SeriesSubtitlesReady({
    required this.episodes,
    required this.gapsBySeason,
    required this.seriesGaps,
  });

  /// Tags per Sonarr episode id, for the episodes Bazarr lists.
  final Map<int, EpisodeSubtitleTags> episodes;

  /// Episodes missing at least one language, per season number.
  final Map<int, int> gapsBySeason;

  /// Episodes missing at least one language, across the series.
  final int seriesGaps;

  @override
  bool operator ==(Object other) =>
      other is SeriesSubtitlesReady &&
      other.seriesGaps == seriesGaps &&
      mapEquals(other.episodes, episodes) &&
      mapEquals(other.gapsBySeason, gapsBySeason);

  @override
  int get hashCode => Object.hash(
        seriesGaps,
        Object.hashAllUnordered(
          episodes.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        Object.hashAllUnordered(
          gapsBySeason.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
}

/// What Radarr and Sonarr screens ask of the subtitle manager, without
/// depending on it. Every member has a no-op default, so an arr screen works
/// unchanged when no implementation is installed (see [NoSubtitlesBridge]).
///
/// `app/` overrides [subtitlesBridgeProvider] with the Bazarr implementation.
/// Lookups key by the arr instance's id and resolve the current instances
/// from the profile, since screens may hold stale [Instance] objects.
abstract class SubtitlesBridge {
  const SubtitlesBridge();

  /// The subtitles section of a Radarr movie page, with its own top spacing;
  /// [SizedBox.shrink] when no Bazarr serves [radarr].
  Widget movieSection({
    required Instance radarr,
    required MovieSubtitlesRef movie,
  }) =>
      const SizedBox.shrink();

  /// The subtitles (coverage) section of a Sonarr series page, with its own
  /// top spacing; [SizedBox.shrink] when no Bazarr serves [sonarr].
  Widget seriesSection({
    required Instance sonarr,
    required SeriesSubtitlesRef series,
  }) =>
      const SizedBox.shrink();

  /// Bazarr's data for a series, keyed by (`sonarr.id`, [seriesId]).
  ProviderListenable<SeriesSubtitles> series(
    Instance sonarr,
    int seriesId,
  ) =>
      seriesSubtitlesOffProvider;

  /// Opens the subtitles sheet of one episode.
  Future<void> openEpisode(
    BuildContext context, {
    required Instance sonarr,
    required SeriesSubtitlesRef series,
    required int episodeId,
  }) async {}

  /// Searches the missing subtitles of one season.
  Future<void> searchSeasonMissing(
    BuildContext context, {
    required Instance sonarr,
    required int seriesId,
    required int season,
  }) async {}

  /// Searches the missing subtitles of a whole series.
  Future<void> searchSeriesMissing(
    BuildContext context, {
    required Instance sonarr,
    required SeriesSubtitlesRef series,
  }) async {}

  /// Refetches Bazarr's data for a movie or series after the arr page
  /// refreshed ([itemId]: the Radarr movie id or Sonarr series id).
  void refresh(Instance arr, int itemId) {}
}

/// The default bridge: no subtitle manager, so nothing shows.
final class NoSubtitlesBridge extends SubtitlesBridge {
  const NoSubtitlesBridge();
}
