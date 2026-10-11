import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'subtitles_bridge.dart';

/// Always [SeriesSubtitlesOff]: what [SubtitlesBridge.series] returns when no
/// subtitle manager serves a Sonarr.
final seriesSubtitlesOffProvider =
    Provider<SeriesSubtitles>((ref) => const SeriesSubtitlesOff());

/// The installed [SubtitlesBridge]. Service packages must not import each
/// other, so Radarr and Sonarr read Bazarr through this; `app/` overrides it
/// with the Bazarr implementation at bootstrap. The default,
/// [NoSubtitlesBridge], renders nothing.
final subtitlesBridgeProvider =
    Provider<SubtitlesBridge>((ref) => const NoSubtitlesBridge());
