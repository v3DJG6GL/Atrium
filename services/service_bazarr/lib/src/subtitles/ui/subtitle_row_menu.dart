import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bazarr_subtitle_params.dart';
import '../bazarr_version.dart';
import '../subtitle_actions.dart';
import '../subtitle_ui_text.dart';
import 'subtitle_sheet.dart';

/// What the row menu of a subtitle asks for. The host runs it once the menu
/// has closed.
enum SubtitleRowAction { sync, timing, translate, cleanup, delete, extract }

/// One entry of a subtitle's row menu.
@immutable
class SubtitleRowMenuEntry {
  const SubtitleRowMenuEntry({
    required this.action,
    required this.label,
    required this.icon,
    this.subtitle,
    this.enabled = true,
    this.danger = false,
  });

  final SubtitleRowAction action;
  final String label;
  final IconData icon;
  final String? subtitle;
  final bool enabled;
  final bool danger;
}

/// The row menu of [row]: sync, timing, translate, clean up and delete for
/// an external file; translate and extract for an embedded track, gated by
/// [version] and by whether Bazarr has indexed the track.
List<SubtitleRowMenuEntry> subtitleRowMenuEntries(
  SubtitleRow row,
  BazarrVersionInfo version,
) {
  final SubtitleTrack? track = row.track;
  if (track == null || row.state == SubtitleState.missing) {
    return const <SubtitleRowMenuEntry>[];
  }
  if (!track.isFile) {
    // Both tools address the track by Bazarr's subtitle id, which a
    // supporting version can still lack for a track it hasn't indexed.
    final bool hasId = track.id != null;
    SubtitleRowMenuEntry gated(
      SubtitleRowAction action,
      String label,
      IconData icon,
      BazarrFeature feature,
      String available,
    ) {
      final String? gate = version.gateNote(feature);
      final String? note = gate ?? (hasId ? null : embeddedNotIndexedNote);
      return SubtitleRowMenuEntry(
        action: action,
        label: label,
        icon: icon,
        subtitle: note ?? available,
        enabled: note == null,
      );
    }

    return <SubtitleRowMenuEntry>[
      gated(
        SubtitleRowAction.translate,
        'Translate…',
        Icons.translate,
        BazarrFeature.translateEmbedded,
        'Extracts the track, then translates it',
      ),
      gated(
        SubtitleRowAction.extract,
        'Extract to file',
        Icons.file_download_outlined,
        BazarrFeature.extract,
        'Saves this track next to the video',
      ),
    ];
  }
  final bool srt = isModifiable(bazarrSubtitleOf(track));
  return <SubtitleRowMenuEntry>[
    const SubtitleRowMenuEntry(
      action: SubtitleRowAction.sync,
      label: 'Sync to audio',
      icon: Icons.graphic_eq,
      subtitle: 'Re-times lines against the audio track',
    ),
    SubtitleRowMenuEntry(
      action: SubtitleRowAction.timing,
      label: 'Adjust timing…',
      icon: Icons.timer_outlined,
      subtitle: srt
          ? 'Shift by any amount or fix the frame rate'
          : 'Only for .srt files',
      enabled: srt,
    ),
    const SubtitleRowMenuEntry(
      action: SubtitleRowAction.translate,
      label: 'Translate…',
      icon: Icons.translate,
      subtitle: "Machine translation with Bazarr's translator",
    ),
    SubtitleRowMenuEntry(
      action: SubtitleRowAction.cleanup,
      label: 'Clean up…',
      icon: Icons.auto_fix_high_outlined,
      subtitle: srt
          ? 'Hearing-impaired tags, OCR and common fixes'
          : 'Only for .srt files',
      enabled: srt,
    ),
    const SubtitleRowMenuEntry(
      action: SubtitleRowAction.delete,
      label: 'Delete subtitle',
      icon: Icons.delete_outline,
      danger: true,
    ),
  ];
}

/// Shows the row menu of [row], gated by [bazarr]'s version; resolves with
/// the picked action, or null.
Future<SubtitleRowAction?> showSubtitleRowMenu(
  BuildContext context, {
  required SubtitleRow row,
  required Instance bazarr,
}) =>
    showSubtitleSheet<SubtitleRowAction>(
      context,
      builder: (BuildContext _) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) =>
            SubtitleRowMenu(
          row: row,
          version: ref.watch(bazarrVersionInfoProvider(bazarr)),
        ),
      ),
    );

/// The row menu sheet's content.
class SubtitleRowMenu extends StatelessWidget {
  const SubtitleRowMenu({
    required this.row,
    required this.version,
    super.key,
  });

  final SubtitleRow row;
  final BazarrVersionInfo version;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? path = row.track?.path;
    return SubtitleSheetFrame(
      title: subtitleMenuTitle(row),
      subtitle: path != null && path.isNotEmpty
          ? subtitleFileName(path)
          : 'Embedded track',
      scrollable: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Insets.sm),
        children: <Widget>[
          for (final SubtitleRowMenuEntry e
              in subtitleRowMenuEntries(row, version))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Insets.xl),
              enabled: e.enabled,
              leading: Icon(
                e.icon,
                color: e.danger && e.enabled ? scheme.error : null,
              ),
              title: Text(
                e.label,
                style: e.danger ? TextStyle(color: scheme.error) : null,
              ),
              subtitle: e.subtitle == null ? null : Text(e.subtitle!),
              onTap: () => Navigator.of(context).pop(e.action),
            ),
        ],
      ),
    );
  }
}
