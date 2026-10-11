/// Public surface of `service_bazarr`.
///
/// Bazarr API client (API-key header via the shared Dio), models, Riverpod
/// providers, the per-instance [BazarrHome] UI, the links between a Bazarr
/// and its Radarr and Sonarr, and the subtitle actions behind them.
library;

export 'src/bazarr_api.dart';
export 'src/bazarr_home.dart';
export 'src/bazarr_open.dart';
export 'src/bazarr_providers.dart';
export 'src/history/bazarr_history_providers.dart';
export 'src/library/bazarr_library_providers.dart';
export 'src/library/bazarr_library_tab.dart';
export 'src/link/bazarr_connected_apps_section.dart';
export 'src/link/bazarr_link.dart';
export 'src/link/bazarr_link_providers.dart';
export 'src/models/bazarr_models.dart';
export 'src/subtitles/bazarr_activity.dart';
export 'src/subtitles/bazarr_subtitle_mapping.dart';
export 'src/subtitles/bazarr_subtitle_params.dart';
export 'src/subtitles/bazarr_subtitle_providers.dart';
export 'src/subtitles/bazarr_subtitles_bridge.dart';
export 'src/subtitles/bazarr_version.dart';
export 'src/subtitles/job_watch.dart';
export 'src/subtitles/manual_search/bazarr_manual_search_screen.dart';
export 'src/subtitles/manual_search/open_manual_search.dart';
export 'src/subtitles/subtitle_actions.dart';
export 'src/subtitles/ui/episode_subtitles_sheet.dart';
export 'src/subtitles/ui/movie_subtitles_card.dart';
export 'src/subtitles/ui/subtitles_block.dart';
