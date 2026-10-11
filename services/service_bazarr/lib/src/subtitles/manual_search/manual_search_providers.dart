import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bazarr_api.dart';
import '../../bazarr_providers.dart';
import '../../history/bazarr_history_providers.dart';
import '../../models/bazarr_models.dart';
import '../bazarr_activity.dart';
import '../bazarr_subtitle_params.dart';
import '../bazarr_subtitle_providers.dart';

/// Args of [bazarrManualSearchProvider]: the Bazarr and what it searches for.
typedef BazarrManualSearchArgs = ({Instance bazarr, SubtitleTarget target});

/// How long finished results stay cached once nobody watches them, so
/// reopening the search right away doesn't ask every provider again.
const Duration bazarrManualSearchCacheTime = Duration(seconds: 60);

// When each result list arrived, keyed by the list itself so it travels with
// the cached value (a reopened search keeps its "2m ago").
final Expando<DateTime> _arrivedAt = Expando<DateTime>('manualSearchArrived');

/// When [results] (a value of [bazarrManualSearchProvider]) arrived.
DateTime? bazarrManualSearchArrivedAt(
  List<BazarrSubtitleSearchResult> results,
) =>
    _arrivedAt[results];

/// Bazarr's manual search for one movie or episode: every enabled provider's
/// candidates for every language in the item's profile.
///
/// Slow (providers are asked in turn), so leaving the screen cancels the
/// request, a failure is never retried on its own, and results are kept for
/// [bazarrManualSearchCacheTime] after the screen closes. Search again with
/// `ref.invalidate`.
final bazarrManualSearchProvider = FutureProvider.autoDispose
    .family<List<BazarrSubtitleSearchResult>, BazarrManualSearchArgs>(
  (Ref ref, BazarrManualSearchArgs args) async {
    final CancelToken cancelToken = CancelToken();
    ref.onDispose(cancelToken.cancel);
    final BazarrApi api =
        await ref.watch(bazarrApiProvider(args.bazarr).future);
    final List<BazarrSubtitleSearchResult> results =
        List<BazarrSubtitleSearchResult>.unmodifiable(
      await api.manualSearch(args.target, cancelToken: cancelToken),
    );
    _arrivedAt[results] = DateTime.now();
    if (!ref.mounted) {
      return results;
    }
    final link = ref.keepAlive();
    final Timer timer = Timer(bazarrManualSearchCacheTime, link.close);
    ref.onDispose(timer.cancel);
    return results;
  },
  // A search that failed or timed out isn't asked again behind the user's
  // back: every retry would hit every provider once more.
  retry: (int _, Object __) => null,
);

/// The providers a downloaded manual-search result changes, for
/// [BazarrActivity.run]'s refresh list.
List<WatchedProvider> bazarrManualSearchRefresh(
  Instance bazarr,
  SubtitleTarget target,
) =>
    <WatchedProvider>[
      ...switch (target) {
        MovieTarget(:final int radarrId) => <WatchedProvider>[
            bazarrMovieItemProvider((bazarr, radarrId)),
            bazarrMoviesProvider(bazarr),
          ],
        EpisodeTarget(:final int seriesId) => <WatchedProvider>[
            bazarrEpisodesProvider((instance: bazarr, seriesId: seriesId)),
            bazarrSeriesItemProvider((bazarr, seriesId)),
            bazarrSeriesProvider(bazarr),
          ],
      },
      bazarrBadgesProvider(bazarr),
      ...bazarrHistoryRefresh(bazarr),
    ];
