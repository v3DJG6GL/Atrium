import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../subtitle_model.dart';
import 'audio_pill.dart';
import 'overflow_tag.dart';
import 'subtitle_track_chip.dart';
import 'tag_metrics.dart';

/// Audio languages and subtitles, each led by its icon (speaker / captions):
/// one line of two equal columns (audio left, subtitles right), or with
/// [stacked] audio above subtitles for narrow poster overlays. Used by the
/// Sonarr episode rows and the Bazarr library rows and posters.
///
/// Each column fills its whole width before collapsing the rest into "+N",
/// never a fixed cap, so wider screens and larger text show as many tags as
/// actually fit.
///
/// Without [audio] only the subtitles line shows, across the full width (the
/// Bazarr library's missing-episode rows list just what is missing).
class LanguageLines extends StatelessWidget {
  const LanguageLines({
    required this.subtitles,
    this.audio,
    this.size = TagSize.sm,
    this.stacked = false,
    this.onTap,
    this.semanticLabel,
    this.ringColor,
    super.key,
  });

  /// Null: subtitles only.
  final List<AudioTag>? audio;

  /// Null when the subtitle manager has no data: the column stays as a blank
  /// spacer (no captions icon claiming "none"), aligned with the rows around
  /// it.
  final List<SubtitleChip>? subtitles;
  final TagSize size;

  /// Audio above subtitles instead of side by side.
  final bool stacked;

  /// Makes the whole block one tappable button.
  final VoidCallback? onTap;

  /// The button's label when [onTap] is set; replaces the tags' own labels.
  final String? semanticLabel;

  /// The surface the tags sit on, for their corner badges' rings.
  final Color? ringColor;

  /// Gap between the two side-by-side columns (Dashboarr's `gap-2.5`).
  static const double _columnGap = 10;

  /// Gap between stacked lines (Dashboarr's `gap-0.5`).
  static const double _lineGap = 2;

  @override
  Widget build(BuildContext context) {
    final audio = this.audio;
    final subtitles = this.subtitles;

    final audioLine = audio == null
        ? null
        : _TagLine(
            icon: Icons.volume_up_outlined,
            size: size,
            count: audio.length,
            audio: true,
            tagBuilder: (i) => AudioPill.fromTag(
              audio[i],
              size: size,
              ringColor: ringColor,
              key: ValueKey(audio[i].code2),
            ),
          );
    final subtitleLine = subtitles == null
        ? null
        : _TagLine(
            icon: Icons.closed_caption_outlined,
            size: size,
            count: subtitles.length,
            audio: false,
            tagBuilder: (i) => SubtitleTrackChip.fromChip(
              subtitles[i],
              size: size,
              ringColor: ringColor,
              key: ValueKey(subtitles[i].key),
            ),
          );

    final Widget body;
    if (stacked) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _lineGap,
        children: [
          if (audioLine != null) audioLine,
          if (subtitleLine != null) subtitleLine,
        ],
      );
    } else {
      body = Row(
        spacing: _columnGap,
        children: [
          if (audioLine != null) Expanded(child: audioLine),
          Expanded(child: subtitleLine ?? const SizedBox.shrink()),
        ],
      );
    }

    if (onTap == null) return body;
    // A node of its own, so a tappable line inside a tappable row stays
    // reachable by screen readers instead of merging into the row.
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
        child: body,
      ),
    );
  }
}

/// One line of tags led by its icon, showing as many as fit and "+N" for the
/// rest.
class _TagLine extends StatelessWidget {
  const _TagLine({
    required this.icon,
    required this.size,
    required this.count,
    required this.audio,
    required this.tagBuilder,
  });

  final IconData icon;
  final TagSize size;
  final int count;

  /// Audio pills (wider) rather than subtitle chips.
  final bool audio;
  final Widget Function(int index) tagBuilder;

  @override
  Widget build(BuildContext context) {
    final m = TagMetrics.of(context, size);
    final scheme = Theme.of(context).colorScheme;
    // No clipping: corner badges poke above and right of their tag. The top
    // padding gives them room inside the line.
    return Padding(
      padding: EdgeInsets.only(top: -m.badgeTop),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Room left after the leading icon and its gap.
          final shown = width.isFinite
              ? fitChips(
                  count: count,
                  available: width - m.lineIconSize - m.gap,
                  chipWidth: audio ? m.pillWidth : m.chipMinWidth,
                  gap: m.gap,
                  plusWidth: m.chipMinWidth,
                )
              : count;
          // The width estimate errs wide; should a tag still come out wider,
          // let it overflow quietly instead of breaking the row.
          return OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            minWidth: 0,
            maxWidth: double.infinity,
            fit: OverflowBoxFit.deferToChild,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: m.gap,
              children: [
                Icon(
                  icon,
                  size: m.lineIconSize,
                  color: scheme.onSurfaceVariant,
                ),
                for (var i = 0; i < shown; i++) tagBuilder(i),
                if (shown < count)
                  OverflowTag(count: count - shown, size: size),
              ],
            ),
          );
        },
      ),
    );
  }
}
