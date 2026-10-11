/// Subtitle and language models, shared subtitle widgets, and the bridge
/// between Radarr/Sonarr screens and a linked Bazarr.
library;

export 'src/bridge/subtitles_bridge.dart';
export 'src/bridge/subtitles_providers.dart';
export 'src/coverage_model.dart';
export 'src/elapsed.dart';
export 'src/language_codes.dart';
export 'src/subtitle_filename.dart';
export 'src/subtitle_model.dart';
export 'src/widgets/audio_pill.dart';
export 'src/widgets/language_lines.dart';
export 'src/widgets/overflow_tag.dart';
export 'src/widgets/searching_indicator.dart';
export 'src/widgets/season_gap_badge.dart';
export 'src/widgets/subtitle_track_chip.dart';
export 'src/widgets/tag_metrics.dart'
    show TagMetrics, TagSize, subtitleMissingColor;
