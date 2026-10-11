import 'package:flutter/material.dart';

/// Tag sizes: [md] in cards and sheets, [sm] in list rows, [xs] over posters.
enum TagSize { xs, sm, md }

/// The measurements of one [TagSize], in logical pixels at a text scale of
/// 1 (Dashboarr's rem sizes × 16). [TagMetrics.of] scales them with the
/// user's text size, so tags grow as one piece instead of their text
/// outgrowing a fixed box.
@immutable
class TagMetrics {
  const TagMetrics._({
    required this.chipMinWidth,
    required this.height,
    required this.chipPadding,
    required this.chipRadius,
    required this.pillMinWidth,
    required this.pillPadding,
    required this.pillWidth,
    required this.gap,
    required this.fontSize,
    required this.badgeSize,
    required this.badgeTop,
    required this.badgeRight,
    required this.badgeFontSize,
    required this.badgeIconSize,
    required this.lineIconSize,
    required this.dashedBorderWidth,
  });

  static const TagMetrics _md = TagMetrics._(
    chipMinWidth: 32,
    height: 24,
    chipPadding: 6,
    chipRadius: 6,
    pillMinWidth: 32,
    pillPadding: 8,
    pillWidth: 35.2,
    gap: 11.52,
    fontSize: 11.2,
    badgeSize: 17.6,
    badgeTop: -7.2,
    badgeRight: -8,
    badgeFontSize: 9.92,
    badgeIconSize: 9,
    lineIconSize: 14,
    dashedBorderWidth: 1.6,
  );

  static const TagMetrics _sm = TagMetrics._(
    chipMinWidth: 25.6,
    height: 19.2,
    chipPadding: 4,
    chipRadius: 5.76,
    pillMinWidth: 27.2,
    pillPadding: 8,
    pillWidth: 32,
    gap: 8.8,
    fontSize: 9.6,
    badgeSize: 14.4,
    badgeTop: -6.08,
    badgeRight: -7.2,
    badgeFontSize: 8.32,
    badgeIconSize: 7,
    lineIconSize: 12,
    dashedBorderWidth: 1.6,
  );

  static const TagMetrics _xs = TagMetrics._(
    chipMinWidth: 19.2,
    height: 15.2,
    chipPadding: 4.8,
    chipRadius: 4.48,
    pillMinWidth: 19.2,
    pillPadding: 5.76,
    pillWidth: 24.8,
    gap: 4.8,
    fontSize: 8,
    badgeSize: 11.52,
    badgeTop: -4.8,
    badgeRight: -5.6,
    badgeFontSize: 6.72,
    badgeIconSize: 6,
    lineIconSize: 10,
    dashedBorderWidth: 1.6,
  );

  /// Unscaled metrics for [size].
  static TagMetrics forSize(TagSize size) => switch (size) {
        TagSize.md => _md,
        TagSize.sm => _sm,
        TagSize.xs => _xs,
      };

  /// Metrics for [size], scaled by the ambient text scale (at least 1, at
  /// most 2, so huge accessibility sizes still leave room for a tag or two).
  static TagMetrics of(BuildContext context, TagSize size) {
    final base = forSize(size);
    final scale =
        (MediaQuery.textScalerOf(context).scale(base.fontSize) / base.fontSize)
            .clamp(1.0, 2.0);
    return scale == 1.0 ? base : base._scaled(scale);
  }

  /// Minimum width of a subtitle chip; a two-letter code fits inside it.
  final double chipMinWidth;

  /// Height of chips and pills.
  final double height;

  /// Horizontal padding inside a chip.
  final double chipPadding;
  final double chipRadius;
  final double pillMinWidth;

  /// Horizontal padding inside an audio pill.
  final double pillPadding;

  /// Approximate rendered width of a two-letter audio pill (padding + text +
  /// border), for laying out "+N" overflow with `fitChips`. Erring wide only
  /// shows "+N" sooner; erring narrow would overflow into the next column.
  final double pillWidth;

  /// Gap between tags in a line.
  final double gap;
  final double fontSize;

  /// Edge length of the round corner badge, ring included.
  final double badgeSize;

  /// Offset of the badge from the tag's top edge (negative: pokes above).
  final double badgeTop;

  /// Offset of the badge from the tag's right edge (negative: pokes out).
  final double badgeRight;
  final double badgeFontSize;
  final double badgeIconSize;

  /// Size of the leading speaker / captions icon in a language line.
  final double lineIconSize;

  /// Stroke width of a missing chip's dashed border.
  final double dashedBorderWidth;

  /// Ring width around the corner badge.
  double get badgeRing => 2;

  TagMetrics _scaled(double s) => TagMetrics._(
        chipMinWidth: chipMinWidth * s,
        height: height * s,
        chipPadding: chipPadding * s,
        chipRadius: chipRadius * s,
        pillMinWidth: pillMinWidth * s,
        pillPadding: pillPadding * s,
        pillWidth: pillWidth * s,
        gap: gap * s,
        fontSize: fontSize * s,
        badgeSize: badgeSize * s,
        badgeTop: badgeTop * s,
        badgeRight: badgeRight * s,
        badgeFontSize: badgeFontSize * s,
        badgeIconSize: badgeIconSize * s,
        lineIconSize: lineIconSize * s,
        dashedBorderWidth: dashedBorderWidth,
      );
}

/// The color of wanted-but-missing subtitles: amber, dark enough to read on
/// a light surface and light enough on a dark one.
Color subtitleMissingColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
        ? Colors.amber.shade300
        : Colors.amber.shade800;

/// The round corner badge on a tag ("F", an ear, a house): an inverse-surface
/// disc with a ring in the color of the surface the tag sits on, so it reads
/// as cut out of the tag's corner.
class TagCornerBadge extends StatelessWidget {
  const TagCornerBadge({
    required this.metrics,
    required this.child,
    this.ringColor,
    super.key,
  });

  final TagMetrics metrics;

  /// The surface the tag sits on; defaults to [ColorScheme.surface].
  final Color? ringColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: metrics.badgeTop,
      right: metrics.badgeRight,
      width: metrics.badgeSize,
      height: metrics.badgeSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          shape: BoxShape.circle,
          border: Border.all(
            color: ringColor ?? scheme.surface,
            width: metrics.badgeRing,
          ),
        ),
        child: Center(
          child: IconTheme.merge(
            data: IconThemeData(
              color: scheme.onInverseSurface,
              size: metrics.badgeIconSize,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: scheme.onInverseSurface,
                fontSize: metrics.badgeFontSize,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The uppercase, extra-bold language code inside a tag.
class TagCodeText extends StatelessWidget {
  const TagCodeText(
    this.text, {
    required this.metrics,
    required this.color,
    this.fontWeight = FontWeight.w800,
    super.key,
  });

  final String text;
  final TagMetrics metrics;
  final Color color;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        softWrap: false,
        // Metrics already follow the text scale.
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: color,
          fontSize: metrics.fontSize,
          fontWeight: fontWeight,
          letterSpacing: metrics.fontSize * 0.025,
          height: 1,
        ),
      );
}
