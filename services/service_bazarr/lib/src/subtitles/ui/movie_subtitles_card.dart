import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bazarr_models.dart';
import '../bazarr_subtitle_mapping.dart';
import '../bazarr_subtitle_params.dart';
import '../bazarr_subtitle_providers.dart';
import '../subtitle_actions.dart';
import '../subtitle_ui_text.dart';
import 'subtitle_flows.dart';
import 'subtitles_block.dart';
import 'subtitles_section.dart';

/// The Subtitles section of a Radarr movie page, from the Bazarr serving
/// that Radarr: collapsed, one line of chips and "have/total"; expanded, the
/// audio languages and the subtitle list. Brings its own top spacing.
class BazarrMovieSubtitlesCard extends ConsumerStatefulWidget {
  const BazarrMovieSubtitlesCard({
    required this.bazarr,
    required this.movie,
    this.expanded = false,
    super.key,
  });

  final Instance bazarr;
  final MovieSubtitlesRef movie;

  /// Start expanded (opened from Bazarr's history).
  final bool expanded;

  @override
  ConsumerState<BazarrMovieSubtitlesCard> createState() =>
      _BazarrMovieSubtitlesCardState();
}

class _BazarrMovieSubtitlesCardState
    extends ConsumerState<BazarrMovieSubtitlesCard> {
  late bool _expanded = widget.expanded;

  @override
  Widget build(BuildContext context) {
    final BazarrItemKey key = (widget.bazarr, widget.movie.radarrId);
    final AsyncValue<BazarrMovie?> item =
        ref.watch(bazarrMovieItemProvider(key));
    final String name = bazarrDisplayName(widget.bazarr);
    final BazarrMovie? movie = item.value;

    final Widget body;
    if (!item.hasValue && !item.hasError) {
      body = const SubtitlesSkeleton();
    } else if (!item.hasValue) {
      body = SubtitlesUnreachable(
        bazarrName: name,
        onRetry: () => ref.invalidate(bazarrMovieItemProvider(key)),
      );
    } else if (movie == null) {
      body = SubtitlesNotListed(bazarrName: name);
    } else {
      body = _card(context, movie);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: Insets.lg),
        SubtitlesSectionHeader(
          bazarrName: name,
          unreachable: item.hasError && item.hasValue,
        ),
        body,
      ],
    );
  }

  Widget _card(BuildContext context, BazarrMovie movie) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<SubtitleRow> rows = movie.subtitleRows();
    final List<SubtitleChip> chips = buildSubtitleChips(rows);
    final ({int have, int total}) coverage = subtitleCoverage(chips);
    final List<AudioTag> audio = mediaAudioTags(
      widget.movie.audioLanguages,
      movie.audioLanguages(),
      originalLanguage: widget.movie.originalLanguage,
    );
    final SubtitleSubject subject = SubtitleSubject(
      target: MovieTarget(widget.movie.radarrId),
      rows: rows,
      title: widget.movie.title,
      searchTitle: widget.movie.title,
      videoFps: widget.movie.videoFps,
      profileId: movie.profileId,
      profileOwner: MovieProfileOwner(widget.movie.radarrId),
    );

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: _expanded,
            label: 'Subtitles, ${coverage.have} of ${coverage.total} '
                'languages present',
            excludeSemantics: true,
            onTap: _toggle,
            child: InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.md,
                  Insets.md,
                  Insets.lg,
                  Insets.md,
                ),
                child: Row(
                  spacing: Insets.sm,
                  children: <Widget>[
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.chevron_right,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: chips.isEmpty
                          ? Text(
                              'None',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          : Padding(
                              // Room for the corner badges.
                              padding: const EdgeInsets.only(top: Insets.xs),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: Insets.sm,
                                children: <Widget>[
                                  for (final SubtitleChip c in chips)
                                    SubtitleTrackChip.fromChip(
                                      c,
                                      ringColor: scheme.surfaceContainerHigh,
                                    ),
                                ],
                              ),
                            ),
                    ),
                    if (coverage.total > 0)
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: '${coverage.have}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                            TextSpan(text: '/${coverage.total}'),
                          ],
                        ),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...<Widget>[
            if (audio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.lg,
                  0,
                  Insets.lg,
                  Insets.md,
                ),
                child: AudioLine(
                  audio: audio,
                  ringColor: scheme.surfaceContainerHigh,
                  singleSeparator: ', ',
                ),
              ),
            BazarrSubtitlesBlock(bazarr: widget.bazarr, subject: subject),
          ],
        ],
      ),
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);
}

/// A volume icon and the audio languages; with one language its name too
/// ("English, original").
class AudioLine extends StatelessWidget {
  const AudioLine({
    required this.audio,
    this.ringColor,
    this.singleSeparator = ' · ',
    this.size = TagSize.md,
    super.key,
  });

  final List<AudioTag> audio;
  final Color? ringColor;

  /// Between the single language's name and "original".
  final String singleSeparator;
  final TagSize size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Semantics(
      container: true,
      label: 'Audio: ${audio.map(
            (AudioTag a) => '${a.name}${a.original ? ' (original)' : ''}',
          ).join(', ')}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Insets.xs),
        child: Wrap(
          spacing: 10,
          runSpacing: Insets.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Icon(Icons.volume_up_outlined, size: 16, color: scheme.outline),
            for (final AudioTag a in audio)
              AudioPill.fromTag(a, size: size, ringColor: ringColor),
            if (audio.length == 1)
              Text(
                '${audio.single.name}'
                '${audio.single.original ? '${singleSeparator}original' : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
