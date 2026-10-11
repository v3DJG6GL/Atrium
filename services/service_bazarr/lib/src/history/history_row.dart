import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bazarr_models.dart';
import 'bazarr_history_logic.dart';
import 'history_detail_sheet.dart';

/// The icon of an action [kind].
IconData historyActionIcon(HistoryActionKind kind) => switch (kind) {
      HistoryActionKind.deleted => Icons.delete_outline,
      HistoryActionKind.downloaded => Icons.download,
      HistoryActionKind.manual => Icons.person_search,
      HistoryActionKind.upgraded => Icons.arrow_circle_up,
      HistoryActionKind.uploaded => Icons.upload,
      HistoryActionKind.synced => Icons.graphic_eq,
      HistoryActionKind.translated => Icons.translate,
      HistoryActionKind.extracted => Icons.unarchive_outlined,
      HistoryActionKind.unknown => Icons.history,
    };

/// A day header of the History list.
class HistoryDayHeader extends StatelessWidget {
  const HistoryDayHeader({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.xs,
        Insets.md,
        Insets.xs,
        Insets.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One history entry: what happened, to what, in which language, and when.
class HistoryRow extends StatelessWidget {
  const HistoryRow({
    required this.entry,
    required this.blacklisted,
    required this.onTap,
    super.key,
  });

  final HistoryEntry entry;

  /// Bazarr's flag, or blacklisted from this app before history caught up.
  final bool blacklisted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final BazarrHistoryItem item = entry.item;
    final HistoryActionMeta meta = historyActionMeta(item.action);
    final String title = historyTitle(entry);
    final String summary = historySummary(item);
    final DateTime? at = entry.at;
    final String time =
        at != null ? DateFormat.Hm().format(at) : historyRawTime(item);
    final Widget? chip = historyLanguageChip(
      item,
      ringColor: scheme.surfaceContainerHigh,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Semantics(
        button: true,
        label: '$title, $summary${blacklisted ? ', blacklisted' : ''}',
        excludeSemantics: true,
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Radii.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.md,
                vertical: Insets.sm + 2,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(
                      historyActionIcon(meta.kind),
                      size: 18,
                      color: meta.kind == HistoryActionKind.deleted
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: Insets.xs),
                        Row(
                          children: <Widget>[
                            if (chip != null) ...<Widget>[
                              chip,
                              const SizedBox(width: Insets.sm),
                            ],
                            Expanded(
                              child: Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (blacklisted) ...<Widget>[
                    const SizedBox(width: Insets.sm),
                    Icon(
                      Icons.block,
                      key: const ValueKey<String>('history-blacklisted'),
                      size: 16,
                      color: scheme.error,
                    ),
                  ],
                  const SizedBox(width: Insets.sm),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
