import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../bazarr_api.dart';
import '../bazarr_providers.dart';
import '../link/bazarr_link_providers.dart';
import '../models/bazarr_models.dart';
import 'bazarr_subtitle_mapping.dart';

// Bazarr data behind the subtitle UI on the Radarr and Sonarr pages: one
// movie or series at a time (not the whole library), the per-episode view a
// series page needs, and the coverage grid.

/// A Bazarr instance plus a Radarr movie id or Sonarr series id.
typedef BazarrItemKey = (Instance bazarr, int id);

// --- Refresh requests from the arr pages ---

/// What an arr page asks to refetch (see [requestBazarrItemRefresh]).
@immutable
class _RefreshRequest {
  const _RefreshRequest(this.kind, this.arrId, this.itemId);

  final ServiceKind kind;
  final String arrId;
  final int itemId;
}

// The bridge's `refresh(arr, itemId)` has no ref to invalidate with, so it
// posts here and the live item providers refetch themselves.
final StreamController<_RefreshRequest> _refreshRequests =
    StreamController<_RefreshRequest>.broadcast(sync: true);

/// Asks the item providers of the Bazarr serving [arr] to refetch item
/// [itemId] (a Radarr movie id or a Sonarr series id). Providers nobody
/// watches are left alone: they load fresh when next watched.
void requestBazarrItemRefresh(Instance arr, int itemId) =>
    _refreshRequests.add(_RefreshRequest(arr.kind, arr.id, itemId));

/// Calls [onRefresh] when an arr page served by [bazarr] asks to refetch
/// item [itemId] of [kind].
void _listenForRefresh(
  Ref ref, {
  required Instance bazarr,
  required ServiceKind kind,
  required int itemId,
  required void Function() onRefresh,
}) {
  final StreamSubscription<_RefreshRequest> sub =
      _refreshRequests.stream.listen((_RefreshRequest r) {
    if (r.kind != kind || r.itemId != itemId || !ref.mounted) {
      return;
    }
    // Item ids are per arr instance: skip a request from an arr that
    // another Bazarr serves.
    final Instance? arr = ref.read(instanceByIdProvider(r.arrId));
    final Instance? serving = arr == null
        ? null
        : ref.read(
            bazarrForArrProvider(arr),
          );
    if (serving != null && serving.id != bazarr.id) {
      return;
    }
    onRefresh();
  });
  ref.onDispose(() {
    unawaited(sub.cancel());
  });
}

// --- Items ---

/// Bazarr's view of one Radarr movie, or null when Bazarr doesn't list it
/// (not synced from Radarr yet).
final bazarrMovieItemProvider =
    FutureProvider.autoDispose.family<BazarrMovie?, BazarrItemKey>(
  (Ref ref, BazarrItemKey key) async {
    _listenForRefresh(
      ref,
      bazarr: key.$1,
      kind: ServiceKind.radarr,
      itemId: key.$2,
      onRefresh: ref.invalidateSelf,
    );
    final BazarrApi api = await ref.watch(bazarrApiProvider(key.$1).future);
    return api.getMovie(key.$2);
  },
  retry: (int _, Object __) => null,
);

/// Bazarr's view of one Sonarr series, or null when Bazarr doesn't list it
/// (not synced from Sonarr yet).
final bazarrSeriesItemProvider =
    FutureProvider.autoDispose.family<BazarrSeries?, BazarrItemKey>(
  (Ref ref, BazarrItemKey key) async {
    _listenForRefresh(
      ref,
      bazarr: key.$1,
      kind: ServiceKind.sonarr,
      itemId: key.$2,
      onRefresh: () {
        ref.invalidate(
          bazarrEpisodesProvider((instance: key.$1, seriesId: key.$2)),
        );
        ref.invalidateSelf();
      },
    );
    final BazarrApi api = await ref.watch(bazarrApiProvider(key.$1).future);
    return api.getSeriesItem(key.$2);
  },
  retry: (int _, Object __) => null,
);

// --- Series ---

/// Bazarr's episodes of one series, indexed for the series page: tags per
/// episode, gap counts and the airing order of the episodes with gaps.
@immutable
class BazarrSeriesEpisodes {
  BazarrSeriesEpisodes(List<BazarrEpisode> episodes)
      : episodes = List<BazarrEpisode>.unmodifiable(_airingOrder(episodes)) {
    final Map<int, BazarrEpisode> byId = <int, BazarrEpisode>{};
    final Map<int, EpisodeSubtitleTags> tags = <int, EpisodeSubtitleTags>{};
    final Map<int, int> gaps = <int, int>{};
    final List<int> gapOrder = <int>[];
    for (final BazarrEpisode e in this.episodes) {
      byId[e.sonarrEpisodeId] = e;
      tags[e.sonarrEpisodeId] = EpisodeSubtitleTags(
        chips: buildSubtitleChips(e.subtitleRows()),
        bazarrAudio: e.audioLanguage
            .map((BazarrLanguage l) => l.toLanguage())
            .toList(growable: false),
      );
      if (e.missingSubtitles.isNotEmpty) {
        final int season = e.season ?? 0;
        gaps[season] = (gaps[season] ?? 0) + 1;
        gapOrder.add(e.sonarrEpisodeId);
      }
    }
    this.byId = Map<int, BazarrEpisode>.unmodifiable(byId);
    this.tags = Map<int, EpisodeSubtitleTags>.unmodifiable(tags);
    gapsBySeason = Map<int, int>.unmodifiable(gaps);
    this.gapOrder = List<int>.unmodifiable(gapOrder);
  }

  /// In airing order: by season, then episode.
  final List<BazarrEpisode> episodes;

  /// By Sonarr episode id.
  late final Map<int, BazarrEpisode> byId;

  /// Subtitle tags per Sonarr episode id.
  late final Map<int, EpisodeSubtitleTags> tags;

  /// Episodes missing at least one language, per season.
  late final Map<int, int> gapsBySeason;

  /// Ids of the episodes missing at least one language, in airing order.
  late final List<int> gapOrder;

  int get seriesGaps => gapOrder.length;

  /// The episode with gaps before [episodeId] in airing order, or null.
  BazarrEpisode? previousGap(int episodeId) => _gapBeside(episodeId, -1);

  /// The episode with gaps after [episodeId] in airing order, or null.
  BazarrEpisode? nextGap(int episodeId) => _gapBeside(episodeId, 1);

  BazarrEpisode? _gapBeside(int episodeId, int direction) {
    final BazarrEpisode? current = byId[episodeId];
    if (current == null) {
      return null;
    }
    final int here = _position(current);
    BazarrEpisode? best;
    for (final int id in gapOrder) {
      final BazarrEpisode e = byId[id]!;
      final int pos = _position(e);
      if (direction < 0 ? pos < here : pos > here) {
        if (direction > 0) {
          return e;
        }
        best = e;
      }
    }
    return best;
  }

  static int _position(BazarrEpisode e) =>
      (e.season ?? 0) * 100000 + (e.episode ?? 0);

  static List<BazarrEpisode> _airingOrder(List<BazarrEpisode> episodes) {
    // List.sort isn't stable; the index keeps equal positions in order.
    final List<(int, BazarrEpisode)> indexed = <(int, BazarrEpisode)>[
      for (int i = 0; i < episodes.length; i++) (i, episodes[i]),
    ];
    indexed.sort(((int, BazarrEpisode) a, (int, BazarrEpisode) b) {
      final int c = _position(a.$2).compareTo(_position(b.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return <BazarrEpisode>[for (final (int, BazarrEpisode) e in indexed) e.$2];
  }
}

/// [BazarrSeriesEpisodes] of one series, computed once per episode list.
final bazarrSeriesEpisodesViewProvider = Provider.autoDispose
    .family<AsyncValue<BazarrSeriesEpisodes>, BazarrItemKey>(
  (Ref ref, BazarrItemKey key) => ref
      .watch(bazarrEpisodesProvider((instance: key.$1, seriesId: key.$2)))
      .whenData(
        // A refetch keeps the old list while it loads: reuse its view.
        (List<BazarrEpisode> list) =>
            _seriesViews[list] ??= BazarrSeriesEpisodes(list),
      ),
);

final Expando<BazarrSeriesEpisodes> _seriesViews =
    Expando<BazarrSeriesEpisodes>('BazarrSeriesEpisodes');

/// Bazarr's subtitle data for a series on a Sonarr page, keyed by the
/// Sonarr instance **id** and the series id: [SeriesSubtitlesOff] when no
/// Bazarr serves that Sonarr, [SeriesSubtitlesPending] until both the series
/// and its episodes have loaded (or while Bazarr is unreachable, or doesn't
/// list the series), else [SeriesSubtitlesReady].
final bazarrSeriesSubtitlesProvider =
    Provider.autoDispose.family<SeriesSubtitles, (String, int)>(
  (Ref ref, (String, int) key) {
    final Instance? sonarr = ref.watch(instanceByIdProvider(key.$1));
    if (sonarr == null) {
      return const SeriesSubtitlesOff();
    }
    final Instance? bazarr = ref.watch(bazarrForArrProvider(sonarr));
    if (bazarr == null) {
      return const SeriesSubtitlesOff();
    }
    final BazarrItemKey item = (bazarr, key.$2);
    final AsyncValue<BazarrSeries?> series =
        ref.watch(bazarrSeriesItemProvider(item));
    final BazarrSeriesEpisodes? view =
        ref.watch(bazarrSeriesEpisodesViewProvider(item)).value;
    if (view == null || series.value == null) {
      return const SeriesSubtitlesPending();
    }
    return SeriesSubtitlesReady(
      episodes: view.tags,
      gapsBySeason: view.gapsBySeason,
      seriesGaps: view.seriesGaps,
    );
  },
);

// --- Profiles and coverage ---

/// Whether a profile item's "True"/"False" flag is set.
bool profileFlag(String value) => value == 'True';

/// The coverage columns of a language profile, one per item.
List<CoverageLanguage> profileColumns(BazarrLanguageProfile profile) =>
    <CoverageLanguage>[
      for (final BazarrProfileItem i in profile.items)
        CoverageLanguage.of(
          i.language,
          forced: profileFlag(i.forced),
          hi: profileFlag(i.hi),
        ),
    ];

/// The coverage grid of a series, once its profile has settled (null
/// before): built from the profile's languages, or from every language an
/// episode has when the series has no profile or the profiles didn't load.
final bazarrSeriesCoverageProvider =
    Provider.autoDispose.family<CoverageGrid?, BazarrItemKey>(
  (Ref ref, BazarrItemKey key) {
    final AsyncValue<BazarrSeries?> series =
        ref.watch(bazarrSeriesItemProvider(key));
    final List<BazarrEpisode>? episodes =
        ref.watch(bazarrSeriesEpisodesViewProvider(key)).value?.episodes;
    if (!series.hasValue || episodes == null) {
      return null;
    }
    final int? profileId = series.value?.profileId;
    BazarrLanguageProfile? profile;
    if (profileId != null) {
      final AsyncValue<List<BazarrLanguageProfile>> profiles =
          ref.watch(bazarrProfilesProvider(key.$1));
      if (!profiles.hasValue && profiles.isLoading) {
        // Without its profile the grid would show every language an episode
        // has, then jump to the profile's.
        return null;
      }
      for (final BazarrLanguageProfile p
          in profiles.value ?? const <BazarrLanguageProfile>[]) {
        if (p.profileId == profileId) {
          profile = p;
          break;
        }
      }
    }
    return buildCoverageGrid(
      episodes.map((BazarrEpisode e) => e.toCoverageEpisode()),
      profileColumns: profile == null ? null : profileColumns(profile),
    );
  },
);
