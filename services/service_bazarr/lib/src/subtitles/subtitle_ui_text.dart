import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../models/bazarr_models.dart';
import 'bazarr_subtitle_providers.dart';

// Pure text and option helpers of the subtitle UI.

/// "+1.5 s", "−0.250 s", "0.0 s": a timing offset in milliseconds, with one
/// decimal when it is a multiple of 100 ms, else three.
String formatOffset(int ms) {
  final String sign = ms > 0
      ? '+'
      : ms < 0
          ? '−'
          : '';
  final double seconds = ms.abs() / 1000;
  return '$sign${seconds.toStringAsFixed(ms.abs() % 100 == 0 ? 1 : 3)} s';
}

/// "84 KB", "1.2 MB".
String formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final double kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.round()} KB';
  }
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

/// The file name of a path Bazarr reported, which may be a Windows path.
String subtitleFileName(String path) => path.split(RegExp(r'[\\/]')).last;

/// "S01E02".
String episodeCode(int? season, int? episode) =>
    'S${(season ?? 0).toString().padLeft(2, '0')}'
    'E${(episode ?? 0).toString().padLeft(2, '0')}';

/// "Forced · Hearing impaired · Missing", "Embedded track 4",
/// "External · SRT · 84 KB": a subtitle row's detail line.
String describeSubtitleRow(SubtitleRow row) {
  final List<String> parts = <String>[
    if (row.forced) 'Forced',
    if (row.hi) 'Hearing impaired',
  ];
  switch (row.state) {
    case SubtitleState.missing:
      parts.add('Missing');
    case SubtitleState.embedded:
      final int? track = row.track?.embeddedTrackId;
      parts.add(track != null ? 'Embedded track $track' : 'Embedded');
    case SubtitleState.present:
      parts.add('External');
      final String? ext = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false)
          .firstMatch(row.track?.path ?? '')
          ?.group(1);
      if (ext != null) {
        parts.add(ext.toUpperCase());
      }
      final int? size = row.track?.fileSize;
      if (size != null && size > 0) {
        parts.add(formatFileSize(size));
      }
  }
  return parts.join(' · ');
}

/// "German (forced)", "English (hearing impaired)": the row menu's title.
String subtitleMenuTitle(SubtitleRow row) => '${row.name}'
    '${row.forced ? ' (forced)' : ''}'
    '${row.hi ? ' (hearing impaired)' : ''}';

/// "EN + DE HI": the languages of a profile.
String profileDescription(BazarrLanguageProfile profile) => profile.items
    .map(
      (BazarrProfileItem i) =>
          '${i.language.toUpperCase()}${profileFlag(i.hi) ? ' HI' : ''}',
    )
    .join(' + ');

/// The language profile's name for the profile row: null when no profile
/// is set ("None"), "…" while the names load, "Unavailable" when they
/// failed, "Unknown profile" for an id no profile has.
String? profileDisplayName(
  int? profileId,
  AsyncValue<List<BazarrLanguageProfile>> profiles,
) {
  if (profileId == null) {
    return null;
  }
  final List<BazarrLanguageProfile>? list = profiles.value;
  if (list == null) {
    return profiles.hasError ? 'Unavailable' : '…';
  }
  for (final BazarrLanguageProfile p in list) {
    if (p.profileId == profileId) {
      return p.name;
    }
  }
  return 'Unknown profile';
}

/// One option of a [PickerSheet].
@immutable
class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.label,
    this.description,
  });

  final T value;
  final String label;
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is PickerOption<T> &&
      other.value == value &&
      other.label == label &&
      other.description == description;

  @override
  int get hashCode => Object.hash(value, label, description);

  @override
  String toString() => 'PickerOption($value, $label)';
}

/// What a subtitle can be translated into: the item's missing languages
/// first (one per language: a translation has no forced/HI variant), then
/// every other enabled language; never the subtitle's own.
List<PickerOption<String>> translateOptions({
  required String sourceCode2,
  required Iterable<SubtitleRow> rows,
  required Iterable<BazarrLanguage> enabled,
}) {
  final Set<String> seen = <String>{sourceCode2};
  return <PickerOption<String>>[
    for (final SubtitleRow r in rows)
      if (r.state == SubtitleState.missing && seen.add(r.code2))
        PickerOption<String>(
          value: r.code2,
          label: r.name,
          description: 'Missing in the profile',
        ),
    for (final BazarrLanguage l in enabled)
      if (seen.add(l.code2))
        PickerOption<String>(value: l.code2, label: l.name),
  ];
}

/// A language the upload sheet offers.
typedef UploadLanguage = ({String code2, String name});

/// The upload sheet's languages: the profile's first, then the enabled
/// ones, each once.
List<UploadLanguage> uploadLanguages({
  BazarrLanguageProfile? profile,
  Iterable<BazarrLanguage> enabled = const <BazarrLanguage>[],
}) {
  final Map<String, String> enabledNames = <String, String>{
    for (final BazarrLanguage l in enabled) l.code2: l.name,
  };
  final Set<String> seen = <String>{};
  final List<String> codes = <String>[
    for (final BazarrProfileItem i
        in profile?.items ?? const <BazarrProfileItem>[])
      if (i.language.isNotEmpty && seen.add(i.language)) i.language,
    for (final BazarrLanguage l in enabled)
      if (l.code2.isNotEmpty && seen.add(l.code2)) l.code2,
  ];
  return <UploadLanguage>[
    for (final String code2 in codes)
      (code2: code2, name: uploadLanguageName(code2, enabledNames)),
  ];
}

/// A language's name for the upload sheet: Bazarr's, else the language
/// table's, else the code.
String uploadLanguageName(String code2, [Map<String, String>? bazarrNames]) =>
    bazarrNames?[code2] ?? normalizeLanguage(code2)?.name ?? code2;

/// The language profile of a movie or series, among [profiles].
BazarrLanguageProfile? findProfile(
  Iterable<BazarrLanguageProfile>? profiles,
  int? profileId,
) {
  if (profileId == null || profiles == null) {
    return null;
  }
  for (final BazarrLanguageProfile p in profiles) {
    if (p.profileId == profileId) {
      return p;
    }
  }
  return null;
}

/// The profile options of the profile picker, "None" last; empty when the
/// profiles didn't load (an offer of only "None" would read as "no profiles
/// exist").
List<PickerOption<int>> profileOptions(
  List<BazarrLanguageProfile>? profiles,
) =>
    profiles == null
        ? const <PickerOption<int>>[]
        : <PickerOption<int>>[
            for (final BazarrLanguageProfile p in profiles)
              PickerOption<int>(
                value: p.profileId,
                label: p.name,
                description: profileDescription(p),
              ),
            const PickerOption<int>(
              value: noProfileValue,
              label: 'None',
              description: 'Bazarr stops looking for subtitles',
            ),
          ];

/// The profile picker's value for "no profile".
const int noProfileValue = -1;

/// The display name of a Bazarr instance, for "Couldn't reach …".
String bazarrDisplayName(Instance bazarr) =>
    bazarr.name.trim().isEmpty ? 'Bazarr' : bazarr.name;
