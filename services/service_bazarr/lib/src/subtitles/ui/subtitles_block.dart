import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bazarr_providers.dart';
import '../bazarr_activity.dart';
import '../subtitle_actions.dart';
import '../subtitle_ui_text.dart';
import 'subtitle_flows.dart';
import 'subtitle_sheet.dart';
import 'subtitles_section.dart';

/// The subtitle list of one movie or episode: one row per subtitle and per
/// missing language, then Search / Manual / Upload, then the language
/// profile.
///
/// A missing language gets its own Search (Bazarr searches one language per
/// request), everything that exists gets an actions button, and Manual sits
/// in the footer because a provider search returns every profile language at
/// once.
class SubtitlesBlock extends StatelessWidget {
  const SubtitlesBlock({
    required this.rows,
    required this.onSearchLanguage,
    required this.onRowMenu,
    required this.onSearchAll,
    required this.onManual,
    required this.onUpload,
    this.busyKeys = const <String>{},
    this.profileName,
    this.onPressProfile,
    this.hideProfile = false,
    this.raised = false,
    super.key,
  });

  final List<SubtitleRow> rows;

  /// Keys of the rows with an action still running.
  final Set<String> busyKeys;
  final ValueChanged<SubtitleRow> onSearchLanguage;
  final ValueChanged<SubtitleRow> onRowMenu;
  final VoidCallback onSearchAll;
  final VoidCallback onManual;
  final VoidCallback onUpload;

  /// Null: no profile.
  final String? profileName;
  final VoidCallback? onPressProfile;

  /// Episodes inherit their series' profile, which is set on the series.
  final bool hideProfile;

  /// On a lighter panel inside a sheet rather than a card.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color surface =
        raised ? scheme.surfaceContainerHighest : scheme.surfaceContainerHigh;
    final Widget divider = Divider(
      height: 1,
      thickness: 1,
      color: raised ? scheme.outlineVariant : scheme.surfaceContainerHighest,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.md,
            ),
            child: Text(
              'No subtitles yet, and no language profile asks for any.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final SubtitleRow row in rows) ...<Widget>[
            divider,
            _SubtitleRowView(
              row: row,
              busy: busyKeys.contains(row.key),
              ringColor: surface,
              onSearch: () => onSearchLanguage(row),
              onMenu: () => onRowMenu(row),
            ),
          ],
        divider,
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.sm,
          ),
          child: Row(
            spacing: Insets.sm,
            children: <Widget>[
              _ToolButton(
                icon: Icons.search_rounded,
                label: 'Search',
                onPressed: onSearchAll,
              ),
              _ToolButton(
                icon: Icons.person_search_outlined,
                label: 'Manual',
                onPressed: onManual,
              ),
              _ToolButton(
                icon: Icons.upload_file_outlined,
                label: 'Upload',
                onPressed: onUpload,
              ),
            ],
          ),
        ),
        if (!hideProfile) ...<Widget>[
          divider,
          LanguageProfileRow(
            profileName: profileName,
            onPressed: onPressProfile,
          ),
        ],
      ],
    );
  }
}

class _SubtitleRowView extends StatelessWidget {
  const _SubtitleRowView({
    required this.row,
    required this.busy,
    required this.ringColor,
    required this.onSearch,
    required this.onMenu,
  });

  final SubtitleRow row;
  final bool busy;
  final Color ringColor;
  final VoidCallback onSearch;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool missing = row.state == SubtitleState.missing;
    final bool embedded = row.state == SubtitleState.embedded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.sm,
        Insets.sm,
      ),
      child: Row(
        spacing: Insets.md,
        children: <Widget>[
          SubtitleTrackChip(
            code2: row.code2,
            state: row.state,
            forced: row.forced,
            hi: row.hi,
            languageName: row.name,
            ringColor: ringColor,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: embedded ? scheme.onSurfaceVariant : null,
                  ),
                ),
                Text(
                  busy && missing ? 'Searching…' : describeSubtitleRow(row),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: missing
                        ? subtitleMissingColor(scheme)
                        : embedded
                            ? scheme.outline
                            : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (missing)
            Padding(
              padding: const EdgeInsets.only(right: Insets.sm),
              child: Semantics(
                button: true,
                enabled: !busy,
                label: 'Search ${row.name} subtitles',
                onTap: busy ? null : onSearch,
                excludeSemantics: true,
                child: FilledButton.icon(
                  onPressed: busy ? null : onSearch,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Insets.md,
                    ),
                    minimumSize: const Size(0, 32),
                    shape: const StadiumBorder(),
                    textStyle: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  icon: busy
                      ? const SmallSpinner()
                      : const Icon(Icons.search, size: 16),
                  label: const Text('Search'),
                ),
              ),
            )
          else if (busy)
            const SizedBox.square(
              dimension: 48,
              child: Center(child: SmallSpinner()),
            )
          else
            IconButton(
              tooltip: '${row.name} subtitle actions',
              onPressed: onMenu,
              icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
        child: FilledButton.tonalIcon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          icon: Icon(icon, size: 18),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
}

/// [SubtitlesBlock] wired to a Bazarr: busy rows from its activity, the
/// profile's name, and every action with its sheets.
class BazarrSubtitlesBlock extends ConsumerWidget {
  const BazarrSubtitlesBlock({
    required this.bazarr,
    required this.subject,
    this.hideProfile = false,
    this.raised = false,
    this.notify,
    super.key,
  });

  final Instance bazarr;
  final SubtitleSubject subject;
  final bool hideProfile;
  final bool raised;

  /// Where confirmations go; SnackBars when null.
  final SubtitleNotify? notify;

  SubtitleActions _actions(BuildContext context) =>
      SubtitleActions.of(context, bazarr: bazarr, notify: notify);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BazarrActivityState activity =
        ref.watch(bazarrActivityProvider(bazarr.id));
    final Set<String> busy = <String>{
      for (final SubtitleRow r in subject.rows)
        if (SubtitleBusyKeys.rowBusy(activity, subject.target, r)) r.key,
    };
    final String? profileName = hideProfile
        ? null
        : profileDisplayName(
            subject.profileId,
            ref.watch(bazarrProfilesProvider(bazarr)),
          );
    final ProfileOwner? owner = subject.profileOwner;
    return SubtitlesBlock(
      rows: subject.rows,
      busyKeys: busy,
      hideProfile: hideProfile,
      raised: raised,
      profileName: profileName,
      onSearchLanguage: (SubtitleRow row) =>
          unawaited(_actions(context).searchLanguage(subject.target, row)),
      onRowMenu: (SubtitleRow row) => unawaited(
        openSubtitleRowMenu(context, _actions(context), subject, row),
      ),
      onSearchAll: () => unawaited(
        _actions(context).searchAllMissing(subject.target, subject.rows),
      ),
      onManual: () =>
          unawaited(openManualSearch(context, _actions(context), subject)),
      onUpload: () =>
          unawaited(openUploadSubtitle(context, _actions(context), subject)),
      onPressProfile: owner == null
          ? null
          : () => unawaited(
                openLanguageProfilePicker(
                  context,
                  _actions(context),
                  owner: owner,
                  current: subject.profileId,
                ),
              ),
    );
  }
}
