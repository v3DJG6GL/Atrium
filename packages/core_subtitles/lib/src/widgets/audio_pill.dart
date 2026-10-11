import 'package:flutter/material.dart';

import '../subtitle_model.dart';
import 'tag_metrics.dart';

/// An audio language tag: a round outlined pill (subtitles are square chips,
/// so the two never read as the same thing), with a house in the corner
/// badge for the production's original language.
class AudioPill extends StatelessWidget {
  const AudioPill({
    required this.code2,
    this.name,
    this.original = false,
    this.size = TagSize.md,
    this.ringColor,
    super.key,
  });

  /// A pill for an audio [tag].
  AudioPill.fromTag(
    AudioTag tag, {
    TagSize size = TagSize.md,
    Color? ringColor,
    Key? key,
  }) : this(
          code2: tag.code2,
          name: tag.name,
          original: tag.original,
          size: size,
          ringColor: ringColor,
          key: key,
        );

  final String code2;

  /// Spoken by screen readers instead of the code, when known.
  final String? name;

  /// The production's own language.
  final bool original;
  final TagSize size;

  /// Color of the badge's cut-out ring: the surface the pill sits on.
  final Color? ringColor;

  /// What a screen reader announces for this pill.
  String get semanticLabel =>
      '${name ?? code2} audio${original ? ', original language' : ''}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = TagMetrics.of(context, size);
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: BoxConstraints(minWidth: m.pillMinWidth),
            height: m.height,
            padding: EdgeInsets.symmetric(horizontal: m.pillPadding),
            decoration: ShapeDecoration(
              shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
            ),
            // Not `alignment:`, which would stretch the pill to the full
            // width of a Wrap or Column.
            child: Center(
              widthFactor: 1,
              child: TagCodeText(
                code2.toUpperCase(),
                metrics: m,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (original)
            TagCornerBadge(
              metrics: m,
              ringColor: ringColor,
              child: const Icon(Icons.home_rounded),
            ),
        ],
      ),
    );
  }
}
