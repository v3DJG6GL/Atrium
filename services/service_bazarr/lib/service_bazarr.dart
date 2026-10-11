/// Public surface of `service_bazarr`.
///
/// Bazarr API client (API-key header via the shared Dio), models, Riverpod
/// providers, the per-instance [BazarrHome] UI, the links between a Bazarr
/// and its Radarr and Sonarr, and the subtitle actions behind them.
library;

export 'src/bazarr_api.dart';
export 'src/bazarr_home.dart';
export 'src/bazarr_providers.dart';
export 'src/models/bazarr_models.dart';
export 'src/subtitles/bazarr_subtitle_mapping.dart';
export 'src/subtitles/bazarr_subtitle_params.dart';
