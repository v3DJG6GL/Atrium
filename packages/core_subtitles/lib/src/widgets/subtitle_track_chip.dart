import 'package:flutter/material.dart';

import '../subtitle_model.dart';
import 'tag_metrics.dart';

/// A subtitle language tag, used everywhere subtitles appear (movie card,
/// episode rows, coverage grid, Bazarr library rows and posters).
///
/// Subtitles are square chips whose fill says whether the subtitle exists:
/// solid primary = a file, grey with an outline = a track inside the video,
/// dashed amber = wanted but missing. Audio is a round outlined pill
/// (`AudioPill`), so the two never read as the same thing. A modifier sits in
/// a round corner badge, "F" for forced or an ear for hearing impaired, so it
/// is never mistaken for part of the language code.
class SubtitleTrackChip extends StatelessWidget {
  const SubtitleTrackChip({
    required this.code2,
    required this.state,
    this.forced = false,
    this.hi = false,
    this.size = TagSize.md,
    this.languageName,
    this.ringColor,
    super.key,
  });

  /// A chip for an overview [chip].
  SubtitleTrackChip.fromChip(
    SubtitleChip chip, {
    TagSize size = TagSize.md,
    Color? ringColor,
    Key? key,
  }) : this(
          code2: chip.code2,
          state: chip.state,
          forced: chip.forced,
          hi: chip.hi,
          size: size,
          ringColor: ringColor,
          key: key,
        );

  final String code2;
  final SubtitleState state;
  final bool forced;

  /// Hearing impaired. A forced chip shows only the forced badge.
  final bool hi;
  final TagSize size;

  /// Spoken by screen readers instead of the code, when known.
  final String? languageName;

  /// Color of the badge's cut-out ring: the surface the chip sits on.
  final Color? ringColor;

  static String _stateLabel(SubtitleState state) => switch (state) {
        SubtitleState.present => 'subtitle file',
        SubtitleState.embedded => 'embedded subtitle track',
        SubtitleState.missing => 'missing subtitle',
      };

  /// What a screen reader announces for this chip.
  String get semanticLabel => '${languageName ?? code2}'
      '${forced ? ', forced' : ''}'
      '${hi ? ', hearing impaired' : ''}'
      ', ${_stateLabel(state)}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = TagMetrics.of(context, size);
    final radius = BorderRadius.circular(m.chipRadius);
    final missingColor = subtitleMissingColor(scheme);

    final (fill, border, textColor) = switch (state) {
      SubtitleState.present => (scheme.primary, null, scheme.onPrimary),
      SubtitleState.embedded => (
          scheme.surfaceContainerHighest,
          Border.all(color: scheme.outline),
          scheme.onSurfaceVariant,
        ),
      SubtitleState.missing => (null, null, missingColor),
    };

    Widget box = Container(
      constraints: BoxConstraints(minWidth: m.chipMinWidth),
      height: m.height,
      padding: EdgeInsets.symmetric(horizontal: m.chipPadding),
      decoration: BoxDecoration(
        color: fill,
        border: border,
        borderRadius: radius,
      ),
      // Not `alignment:`, which would stretch the chip to the full width of
      // a Wrap or Column.
      child: Center(
        widthFactor: 1,
        child: TagCodeText(
          code2.toUpperCase(),
          metrics: m,
          color: textColor,
        ),
      ),
    );
    if (state == SubtitleState.missing) {
      box = CustomPaint(
        foregroundPainter: DashedRRectPainter(
          color: missingColor,
          strokeWidth: m.dashedBorderWidth,
          radius: m.chipRadius,
          dash: m.dashedBorderWidth * 2,
          gap: m.dashedBorderWidth * 1.5,
        ),
        child: box,
      );
    }

    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          box,
          if (forced)
            TagCornerBadge(
              metrics: m,
              ringColor: ringColor,
              child: const Text(
                'F',
                textScaler: TextScaler.noScaling,
              ),
            )
          else if (hi)
            TagCornerBadge(
              metrics: m,
              ringColor: ringColor,
              child: const Icon(Icons.hearing),
            ),
        ],
      ),
    );
  }
}

/// Paints a dashed rounded-rectangle outline inside its bounds.
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular((radius - inset).clamp(0, double.infinity)),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        dashed.addPath(metric.extractPath(distance, end), Offset.zero);
        distance += dash + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}
