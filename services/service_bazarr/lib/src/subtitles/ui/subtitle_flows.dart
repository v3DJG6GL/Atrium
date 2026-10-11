import 'dart:async';
import 'dart:typed_data';

import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bazarr_providers.dart';
import '../../models/bazarr_models.dart';
import '../bazarr_subtitle_params.dart';
import '../manual_search/open_manual_search.dart';
import '../subtitle_actions.dart';
import '../subtitle_ui_text.dart';
import 'delete_subtitle_dialog.dart';
import 'picker_sheet.dart';
import 'subtitle_row_menu.dart';
import 'subtitle_sheet.dart';
import 'subtitle_timing_sheet.dart';
import 'upload_subtitle_sheet.dart';

// The sheet flows behind a subtitle list. Each sheet resolves with what was
// picked; the host then opens the next one, after checking it is still
// mounted, so no two sheets animate at once.

/// The movie or episode a subtitle list belongs to.
@immutable
class SubtitleSubject {
  const SubtitleSubject({
    required this.target,
    required this.rows,
    required this.title,
    required this.searchTitle,
    this.videoFps,
    this.profileId,
    this.profileOwner,
  });

  final SubtitleTarget target;

  /// Its subtitle rows (see `buildSubtitleRows`).
  final List<SubtitleRow> rows;

  /// The movie title or "Series · S01E02", for sheet subtitles.
  final String title;

  /// What the manual search names: the movie title or "S01E02".
  final String searchTitle;

  /// The video's frame rate, for the timing sheet.
  final double? videoFps;

  /// The language profile in effect (a series' for an episode).
  final int? profileId;

  /// Whose profile the profile row changes; null hides the chevron.
  final ProfileOwner? profileOwner;
}

/// The row menu of [row], then whatever it chains into.
Future<void> openSubtitleRowMenu(
  BuildContext context,
  SubtitleActions actions,
  SubtitleSubject subject,
  SubtitleRow row,
) async {
  final SubtitleRowAction? action = await showSubtitleRowMenu(
    context,
    row: row,
    bazarr: actions.bazarr,
  );
  if (action == null || !context.mounted) {
    return;
  }
  final SubtitleTarget target = subject.target;
  switch (action) {
    case SubtitleRowAction.sync:
      unawaited(
        actions.runTool(
          target,
          row,
          const SubtitleToolAction.sync(),
          started: 'Syncing ${row.name} to the audio…',
        ),
      );
    case SubtitleRowAction.extract:
      unawaited(
        actions.runTool(
          target,
          row,
          const SubtitleToolAction.extract(),
          started: 'Extracting the ${row.name} track…',
        ),
      );
    case SubtitleRowAction.timing:
      await _openTiming(context, actions, subject, row);
    case SubtitleRowAction.translate:
      await _openTranslate(context, actions, subject, row);
    case SubtitleRowAction.cleanup:
      await _openCleanup(context, actions, subject, row);
    case SubtitleRowAction.delete:
      final bool ok = await confirmDeleteSubtitle(context, row);
      if (ok) {
        unawaited(actions.delete(target, row));
      }
  }
}

Future<void> _openTiming(
  BuildContext context,
  SubtitleActions actions,
  SubtitleSubject subject,
  SubtitleRow row,
) async {
  final String? done = await showSubtitleTimingSheet(
    context,
    subtitle: '${row.name} · ${subtitleFileName(row.track?.path ?? '')}',
    videoFps: subject.videoFps,
    onApply: (SubtitleToolAction action) =>
        actions.applyTool(subject.target, row, action),
  );
  if (done != null) {
    actions.notify('$done: ${row.name}');
  }
}

Future<void> _openTranslate(
  BuildContext context,
  SubtitleActions actions,
  SubtitleSubject subject,
  SubtitleRow row,
) async {
  List<PickerOption<String>> options = const <PickerOption<String>>[];
  final String? code2 = await showSubtitleSheet<String>(
    context,
    builder: (BuildContext _) => Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? _) {
        final AsyncValue<List<BazarrLanguage>> languages =
            ref.watch(bazarrLanguagesProvider(actions.bazarr));
        options = translateOptions(
          sourceCode2: row.code2,
          rows: subject.rows,
          enabled: (languages.value ?? const <BazarrLanguage>[])
              .where((BazarrLanguage l) => l.enabled),
        );
        return PickerSheet<String>(
          title: 'Translate ${row.name}',
          options: options,
          loading: !languages.hasValue && !languages.hasError,
          emptyTitle: 'No other languages',
          emptyMessage: "Enable more languages in Bazarr's settings to "
              'translate into them.',
        );
      },
    ),
  );
  if (code2 == null) {
    return;
  }
  final String name = options
          .where((PickerOption<String> o) => o.value == code2)
          .firstOrNull
          ?.label ??
      uploadLanguageName(code2);
  unawaited(
    actions.runTool(
      subject.target,
      row,
      SubtitleToolAction.translate(code2),
      started: 'Translating ${row.name} to $name…',
    ),
  );
}

Future<void> _openCleanup(
  BuildContext context,
  SubtitleActions actions,
  SubtitleSubject subject,
  SubtitleRow row,
) async {
  final String? mod = await showSubtitleSheet<String>(
    context,
    builder: (BuildContext _) => PickerSheet<String>(
      title: 'Clean up ${row.name}',
      searchable: false,
      options: <PickerOption<String>>[
        for (final CleanupMod m in cleanupMods)
          PickerOption<String>(
            value: m.id,
            label: m.label,
            description: m.description,
          ),
      ],
    ),
  );
  if (mod == null) {
    return;
  }
  final String label =
      cleanupMods.where((CleanupMod m) => m.id == mod).firstOrNull?.label ??
          mod;
  unawaited(
    actions.runTool(
      subject.target,
      row,
      SubtitleToolAction.mod(mod),
      started: '$label: ${row.name}',
    ),
  );
}

/// The language profile picker of [owner], currently [current].
Future<void> openLanguageProfilePicker(
  BuildContext context,
  SubtitleActions actions, {
  required ProfileOwner owner,
  required int? current,
}) async {
  List<BazarrLanguageProfile>? loaded;
  final int? value = await showSubtitleSheet<int>(
    context,
    builder: (BuildContext _) => Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? _) {
        final AsyncValue<List<BazarrLanguageProfile>> profiles =
            ref.watch(bazarrProfilesProvider(actions.bazarr));
        loaded = profiles.value;
        return PickerSheet<int>(
          title: 'Language profile',
          options: profileOptions(profiles.value),
          selected: <int>{current ?? noProfileValue},
          searchable: false,
          loading: !profiles.hasValue && !profiles.hasError,
          emptyTitle: "Couldn't load the profiles",
          emptyMessage: "Bazarr didn't answer. Close this and try again.",
        );
      },
    ),
  );
  if (value == null) {
    return;
  }
  final int? next = value == noProfileValue ? null : value;
  if (next == current) {
    return;
  }
  unawaited(
    actions.setProfile(
      owner,
      next,
      name: findProfile(loaded, next)?.name ?? 'None',
    ),
  );
}

/// The upload sheet for [subject].
Future<void> openUploadSubtitle(
  BuildContext context,
  SubtitleActions actions,
  SubtitleSubject subject,
) async {
  final String? language = await showUploadSubtitleSheet(
    context,
    title: subject.title,
    picker: actions.container.read(subtitleFilePickerProvider),
    languages: (WidgetRef ref) {
      final List<BazarrLanguageProfile>? profiles =
          ref.watch(bazarrProfilesProvider(actions.bazarr)).value;
      final List<BazarrLanguage> languages =
          ref.watch(bazarrLanguagesProvider(actions.bazarr)).value ??
              const <BazarrLanguage>[];
      return uploadLanguages(
        profile: findProfile(profiles, subject.profileId),
        enabled: languages.where((BazarrLanguage l) => l.enabled),
      );
    },
    onUpload: (LanguageChoice choice, String fileName, Uint8List bytes) =>
        actions.upload(
      subject.target,
      choice,
      fileName: fileName,
      bytes: bytes,
    ),
  );
  if (language != null) {
    actions.notify('Uploaded $language subtitle');
  }
}

/// Bazarr's manual search for [subject].
Future<void> openManualSearch(
  BuildContext context,
  SubtitleActions actions,
  SubtitleSubject subject,
) =>
    openBazarrManualSearch(
      context,
      bazarr: actions.bazarr,
      target: subject.target,
      title: subject.searchTitle,
    );
