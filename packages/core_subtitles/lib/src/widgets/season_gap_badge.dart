import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import 'tag_metrics.dart';

/// A season header's count of episodes missing at least one subtitle
/// language: a captions icon and the number, in the missing-subtitle amber.
/// Renders nothing at zero.
class SeasonGapBadge extends StatelessWidget {
  const SeasonGapBadge({required this.gaps, super.key});

  /// Episodes of the season missing subtitles.
  final int gaps;

  @override
  Widget build(BuildContext context) {
    if (gaps <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = subtitleMissingColor(theme.colorScheme);
    return Semantics(
      container: true,
      label: '$gaps episode${gaps == 1 ? '' : 's'} missing subtitles',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Insets.xs,
        children: [
          Icon(Icons.closed_caption_outlined, size: 16, color: color),
          Text(
            '$gaps',
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
