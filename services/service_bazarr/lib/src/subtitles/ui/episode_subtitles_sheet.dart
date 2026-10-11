import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bazarr_models.dart';
import '../bazarr_subtitle_mapping.dart';
import '../bazarr_subtitle_params.dart';
import '../bazarr_subtitle_providers.dart';
import '../subtitle_ui_text.dart';
import 'movie_subtitles_card.dart';
import 'subtitle_flows.dart';
import 'subtitle_sheet.dart';
import 'subtitles_block.dart';

/// Opens the subtitles of one episode in a sheet. [episodeInfo] adds what
/// the Sonarr page knows (file audio, media line, frame rate).
Future<void> showEpisodeSubtitlesSheet(
  BuildContext context, {
  required Instance bazarr,
  required int seriesId,
  required int episodeId,
  String seriesTitle = '',
  String? originalLanguage,
  EpisodeSubtitlesInfo? Function(int episodeId)? episodeInfo,
}) =>
    showSubtitleSheet<void>(
      context,
      builder: (BuildContext _) => EpisodeSubtitlesSheet(
        bazarr: bazarr,
        seriesId: seriesId,
        episodeId: episodeId,
        seriesTitle: seriesTitle,
        originalLanguage: originalLanguage,
        episodeInfo: episodeInfo,
      ),
    );

/// One episode's subtitles: its audio languages, the subtitle list, and
/// buttons to step to the previous or next episode still missing a language,
/// so a season's gaps can be worked through without closing the sheet.
class EpisodeSubtitlesSheet extends ConsumerStatefulWidget {
  const EpisodeSubtitlesSheet({
    required this.bazarr,
    required this.seriesId,
    required this.episodeId,
    this.seriesTitle = '',
    this.originalLanguage,
    this.episodeInfo,
    super.key,
  });

  final Instance bazarr;

  /// The Sonarr series id.
  final int seriesId;

  /// The Sonarr episode id to open on.
  final int episodeId;
  final String seriesTitle;

  /// Sonarr's `originalLanguage.name`.
  final String? originalLanguage;
  final EpisodeSubtitlesInfo? Function(int episodeId)? episodeInfo;

  @override
  ConsumerState<EpisodeSubtitlesSheet> createState() =>
      _EpisodeSubtitlesSheetState();
}

class _EpisodeSubtitlesSheetState extends ConsumerState<EpisodeSubtitlesSheet> {
  late int _episodeId = widget.episodeId;
  String? _notice;
  Timer? _noticeTimer;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  // A SnackBar would show behind the sheet: confirmations show in it, or
  // as a SnackBar once it has closed.
  void _notify(String message) {
    if (!mounted) {
      _messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _notice = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final BazarrItemKey key = (widget.bazarr, widget.seriesId);
    final AsyncValue<BazarrSeriesEpisodes> episodes =
        ref.watch(bazarrSeriesEpisodesViewProvider(key));
    final BazarrSeries? series = ref.watch(bazarrSeriesItemProvider(key)).value;
    final BazarrSeriesEpisodes? view = episodes.value;
    final BazarrEpisode? episode = view?.byId[_episodeId];
    final EpisodeSubtitlesInfo? info = widget.episodeInfo?.call(_episodeId);

    if (view == null || episode == null) {
      return SubtitleSheetFrame(
        title: 'Subtitles',
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Center(
            child: view == null && !episodes.hasError
                ? const CircularProgressIndicator()
                : Text(
                    episodes.hasError && view == null
                        ? "Couldn't reach ${bazarrDisplayName(widget.bazarr)}."
                        : "Bazarr doesn't list this episode yet.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
          ),
        ),
      );
    }

    final String code = episodeCode(
      info?.season ?? episode.season,
      info?.episode ?? episode.episode,
    );
    final String title = info?.title ?? episode.title;
    final List<AudioTag> audio = mediaAudioTags(
      info?.audioLanguages,
      episode.audioLanguage.map((BazarrLanguage l) => l.toLanguage()),
      originalLanguage: widget.originalLanguage,
    );
    final SubtitleSubject subject = SubtitleSubject(
      target: EpisodeTarget(widget.seriesId, _episodeId),
      rows: episode.subtitleRows(),
      title:
          widget.seriesTitle.isEmpty ? code : '${widget.seriesTitle} · $code',
      searchTitle: code,
      videoFps: info?.videoFps,
      profileId: series?.profileId,
    );
    final BazarrEpisode? prev = view.previousGap(_episodeId);
    final BazarrEpisode? next = view.nextGap(_episodeId);
    final String? notice = _notice;

    return SubtitleSheetFrame(
      title: '$code subtitles',
      subtitle: <String>[
        if (title.isNotEmpty) title,
        if (info?.mediaLine?.isNotEmpty ?? false) info!.mediaLine!,
      ].join(' · '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (audio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.lg,
                      Insets.md,
                      Insets.lg,
                      Insets.sm,
                    ),
                    child: AudioLine(
                      audio: audio,
                      size: TagSize.sm,
                      ringColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                BazarrSubtitlesBlock(
                  bazarr: widget.bazarr,
                  subject: subject,
                  hideProfile: true,
                  raised: true,
                  notify: _notify,
                ),
              ],
            ),
          ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: Insets.md),
              child: Material(
                color: scheme.inverseSurface,
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.lg,
                    vertical: Insets.md,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      notice,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onInverseSurface),
                    ),
                  ),
                ),
              ),
            ),
          if (view.gapOrder.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Insets.lg),
              child: Row(
                spacing: Insets.sm,
                children: <Widget>[
                  Expanded(
                    child: _GapButton(
                      previous: true,
                      gap: prev,
                      onPressed: prev == null
                          ? null
                          : () => setState(
                                () => _episodeId = prev.sonarrEpisodeId,
                              ),
                    ),
                  ),
                  Expanded(
                    child: _GapButton(
                      previous: false,
                      gap: next,
                      onPressed: next == null
                          ? null
                          : () => setState(
                                () => _episodeId = next.sonarrEpisodeId,
                              ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GapButton extends StatelessWidget {
  const _GapButton({
    required this.previous,
    required this.gap,
    required this.onPressed,
  });

  final bool previous;
  final BazarrEpisode? gap;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final BazarrEpisode? gap = this.gap;
    final String label = gap != null
        ? episodeCode(gap.season, gap.episode)
        : previous
            ? 'No earlier gaps'
            : 'No later gaps';
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: previous
          ? 'Previous episode with missing subtitles'
          : 'Next episode with missing subtitles',
      value: gap == null ? null : label,
      onTap: onPressed,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Insets.xs,
          children: <Widget>[
            if (previous) const Icon(Icons.chevron_left, size: 18),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (!previous) const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
