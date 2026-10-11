import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../bazarr_open.dart';
import '../link/bazarr_link_providers.dart';
import '../models/bazarr_models.dart';
import '../subtitles/manual_search/manual_search_helpers.dart'
    show humanizeMatchKey;
import 'bazarr_history_logic.dart';
import 'bazarr_history_providers.dart';

/// What the user picked in the detail sheet; the sheet closes first, then
/// the History tab acts on it.
enum HistoryDetailAction { open, blacklist }

/// "Oct 9, 2026 14:22", or Bazarr's own timestamp when it couldn't be read.
String historyWhenLabel(HistoryEntry entry) {
  final DateTime? at = entry.at;
  return at != null
      ? DateFormat.yMMMd().add_Hm().format(at)
      : historyRawTime(entry.item);
}

/// Bazarr's own text for when [item] happened, for an entry whose time
/// couldn't be read.
String historyRawTime(BazarrHistoryItem item) =>
    item.timestamp.isNotEmpty ? item.timestamp : item.parsedTimestamp;

/// Opens the details of one history [entry].
Future<HistoryDetailAction?> showHistoryDetailSheet(
  BuildContext context, {
  required Instance bazarr,
  required HistoryEntry entry,
}) =>
    showModalBottomSheet<HistoryDetailAction>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (BuildContext context) =>
          HistoryDetailSheet(bazarr: bazarr, entry: entry),
    );

/// An entry's language, score, provider and time, Bazarr's description,
/// what matched, the file, and the ways to act on it.
class HistoryDetailSheet extends ConsumerWidget {
  const HistoryDetailSheet({
    required this.bazarr,
    required this.entry,
    super.key,
  });

  final Instance bazarr;
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final BazarrHistoryItem item = entry.item;
    final HistoryActionMeta meta = historyActionMeta(item.action);
    final String when = historyWhenLabel(entry);
    final bool isMovie = entry.kind == HistoryKind.movie;
    final bool blacklistedHere =
        ref.watch(bazarrHistoryBlacklistedProvider(bazarr)).contains(entry.key);
    final bool hasArr = ref.watch(bazarrArrTargetsProvider) != null &&
        ref.watch(
              bazarrItemsArrProvider(
                (
                  bazarrId: bazarr.id,
                  kind: isMovie ? ServiceKind.radarr : ServiceKind.sonarr,
                ),
              ),
            ) !=
            null;
    final bool canOpen =
        isMovie ? (item.radarrId ?? 0) > 0 : (item.sonarrSeriesId ?? 0) > 0;
    final String languageName = item.language?.name ?? '';
    final String path = item.subtitlesPath ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          0,
          Insets.lg,
          Insets.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(historyTitle(entry), style: theme.textTheme.titleLarge),
            const SizedBox(height: Insets.xxs),
            Text(
              when.isNotEmpty ? '${meta.label} · $when' : meta.label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Insets.lg),
            _StatGrid(
              stats: <(String, String)>[
                ('Language', languageName.isNotEmpty ? languageName : '—'),
                ('Score', item.score.isNotEmpty ? item.score : '—'),
                ('Provider', item.provider.isNotEmpty ? item.provider : '—'),
                ('When', when.isNotEmpty ? when : '—'),
              ],
            ),
            // Bazarr's own explanation: the only detail a sync, translation
            // or unknown action has.
            if (item.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: Insets.md),
              SelectableText(
                item.description,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (item.matches.isNotEmpty) ...<Widget>[
              const SizedBox(height: Insets.md),
              _MatchGroup(label: 'Matched', keys: item.matches, matched: true),
            ],
            if (item.dontMatches.isNotEmpty) ...<Widget>[
              const SizedBox(height: Insets.md),
              _MatchGroup(
                label: "Didn't match",
                keys: item.dontMatches,
                matched: false,
              ),
            ],
            if (path.isNotEmpty) ...<Widget>[
              const SizedBox(height: Insets.md),
              SelectableText(
                path,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Insets.sm),
            if (canOpen)
              _SheetAction(
                icon: isMovie ? Icons.movie_outlined : Icons.tv_outlined,
                label: isMovie ? 'Open movie' : 'Open episode',
                subtitle: hasArr
                    ? 'Its Subtitles section on the Radarr or Sonarr page'
                    : "On Bazarr's page",
                onTap: () =>
                    Navigator.of(context).pop(HistoryDetailAction.open),
              ),
            if (canBlacklist(entry) && !blacklistedHere)
              _SheetAction(
                icon: Icons.block,
                label: 'Blacklist and search again',
                subtitle: 'Deletes this file, never picks it again, '
                    'finds another',
                danger: true,
                onTap: () =>
                    Navigator.of(context).pop(HistoryDetailAction.blacklist),
              ),
          ],
        ),
      ),
    );
  }
}

/// Label-over-value cells, two per row.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double cell = constraints.maxWidth / 2;
          return Wrap(
            runSpacing: Insets.sm,
            children: <Widget>[
              for (final (String label, String value) in stats)
                SizedBox(
                  width: cell,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Insets.xxs),
                      Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "Matched" / "Didn't match" and the attribute chips under it.
class _MatchGroup extends StatelessWidget {
  const _MatchGroup({
    required this.label,
    required this.keys,
    required this.matched,
  });

  final String label;
  final List<String> keys;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color fill =
        matched ? scheme.tertiaryContainer : scheme.errorContainer;
    final Color fg =
        matched ? scheme.onTertiaryContainer : scheme.onErrorContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Insets.xs + 2),
        Wrap(
          spacing: Insets.xs + 2,
          runSpacing: Insets.xs + 2,
          children: <Widget>[
            for (final String key in keys)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.sm,
                  vertical: Insets.xs,
                ),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      matched ? Icons.check : Icons.close,
                      size: 14,
                      color: fg,
                    ),
                    const SizedBox(width: Insets.xs),
                    Text(
                      humanizeMatchKey(key),
                      style: theme.textTheme.labelMedium?.copyWith(color: fg),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One action row of the sheet.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: danger
              ? scheme.error.withValues(alpha: 0.15)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Icon(
          icon,
          size: 20,
          color: danger ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        label,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: danger ? scheme.error : null),
      ),
      subtitle: Text(subtitle),
      trailing: danger ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Opens the movie or episode of [entry]: on its Radarr or Sonarr page when
/// Bazarr has one, otherwise on Bazarr's own page.
Future<void> openHistoryEntry(
  BuildContext context,
  WidgetRef ref,
  Instance bazarr,
  HistoryEntry entry,
) async {
  final BazarrHistoryItem item = entry.item;
  switch (entry.kind) {
    case HistoryKind.movie:
      final int? radarrId = item.radarrId;
      if (radarrId == null || radarrId <= 0) {
        return;
      }
      await openBazarrMovie(
        context,
        ref,
        bazarr,
        radarrId: radarrId,
        title: item.title,
      );
    case HistoryKind.episode:
      final int? seriesId = item.sonarrSeriesId;
      if (seriesId == null || seriesId <= 0) {
        return;
      }
      final int? episodeId = item.sonarrEpisodeId;
      await openBazarrSeries(
        context,
        ref,
        bazarr,
        seriesId: seriesId,
        episodeId: episodeId != null && episodeId > 0 ? episodeId : null,
      );
  }
}

/// [SubtitleTrackChip] of a history item's language, or null when Bazarr
/// sent none (it marshals a missing language as an object of nulls).
Widget? historyLanguageChip(
  BazarrHistoryItem item, {
  TagSize size = TagSize.sm,
  Color? ringColor,
}) {
  final BazarrSubtitle? language = item.language;
  if (language == null || language.code2.isEmpty) {
    return null;
  }
  return SubtitleTrackChip(
    code2: language.code2,
    state: SubtitleState.present,
    forced: language.forced,
    hi: language.hi,
    size: size,
    languageName: language.name.isNotEmpty ? language.name : null,
    ringColor: ringColor,
  );
}
