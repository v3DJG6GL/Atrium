import 'package:flutter/material.dart';

import 'tag_metrics.dart';

/// "+3" after the tags that fit in a line.
class OverflowTag extends StatelessWidget {
  const OverflowTag({
    required this.count,
    this.size = TagSize.md,
    super.key,
  });

  /// How many tags are hidden.
  final int count;
  final TagSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = TagMetrics.of(context, size);
    return Semantics(
      container: true,
      label: '$count more',
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minWidth: m.chipMinWidth),
        height: m.height,
        padding: EdgeInsets.symmetric(horizontal: m.chipPadding),
        // Not `alignment:`, which would stretch the tag to the full width
        // of a Wrap or Column.
        child: Center(
          widthFactor: 1,
          child: TagCodeText(
            '+$count',
            metrics: m,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
