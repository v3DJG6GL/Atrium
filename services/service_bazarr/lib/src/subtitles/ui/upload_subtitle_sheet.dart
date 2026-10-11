import 'dart:typed_data';

import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bazarr_subtitle_params.dart';
import '../subtitle_ui_text.dart';
import 'subtitle_sheet.dart';

/// The largest subtitle file the upload sheet accepts.
const int maxSubtitleUploadBytes = 5 * 1024 * 1024;

/// A file picked for upload: its name, size and a way to read it.
@immutable
class PickedSubtitleFile {
  const PickedSubtitleFile({
    required this.name,
    required this.size,
    required this.readBytes,
  });

  final String name;

  /// In bytes.
  final int size;
  final Future<Uint8List> Function() readBytes;
}

/// Opens the platform's file picker; null when cancelled.
typedef SubtitleFilePicker = Future<PickedSubtitleFile?> Function();

/// The device's file picker. Any type: iOS has no type for most subtitle
/// formats, so the extension is checked afterwards.
Future<PickedSubtitleFile?> pickSubtitleFileFromDevice() async {
  final PlatformFile? file = await FilePicker.pickFile();
  if (file == null) {
    return null;
  }
  return PickedSubtitleFile(
    name: file.name,
    size: file.size,
    readBytes: file.readAsBytes,
  );
}

/// The file picker the upload sheet uses; tests override it.
final Provider<SubtitleFilePicker> subtitleFilePickerProvider =
    Provider<SubtitleFilePicker>((Ref ref) => pickSubtitleFileFromDevice);

/// Opens "Upload subtitle" for the movie or episode [title]. [onUpload]
/// sends the file and throws on failure (shown in the sheet); resolves with
/// the uploaded language's name once it succeeded, or null when dismissed.
Future<String?> showUploadSubtitleSheet(
  BuildContext context, {
  required String title,
  required List<UploadLanguage> Function(WidgetRef ref) languages,
  required SubtitleFilePicker picker,
  required Future<void> Function(
    LanguageChoice language,
    String fileName,
    Uint8List bytes,
  ) onUpload,
}) =>
    showSubtitleSheet<String>(
      context,
      builder: (BuildContext _) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) =>
            UploadSubtitleSheet(
          title: title,
          languages: languages(ref),
          picker: picker,
          onUpload: onUpload,
        ),
      ),
    );

/// Upload a subtitle: choose the file, then its language and whether it is
/// forced or hearing impaired, prefilled from the file name
/// ("Film.de.forced.srt").
class UploadSubtitleSheet extends StatefulWidget {
  const UploadSubtitleSheet({
    required this.title,
    required this.languages,
    required this.picker,
    required this.onUpload,
    super.key,
  });

  /// The movie or "Series · S01E02".
  final String title;

  /// Offered languages, profile languages first.
  final List<UploadLanguage> languages;
  final SubtitleFilePicker picker;
  final Future<void> Function(
    LanguageChoice language,
    String fileName,
    Uint8List bytes,
  ) onUpload;

  @override
  State<UploadSubtitleSheet> createState() => _UploadSubtitleSheetState();
}

class _UploadSubtitleSheetState extends State<UploadSubtitleSheet> {
  String? _fileName;
  Uint8List? _bytes;
  String? _code2;
  bool _forced = false;
  bool _hi = false;
  bool _busy = false;
  bool _picking = false;
  String? _error;

  Future<void> _pick() async {
    if (_picking) {
      return;
    }
    setState(() {
      _picking = true;
      _error = null;
    });
    PickedSubtitleFile? file;
    String? error;
    Uint8List? bytes;
    try {
      file = await widget.picker();
      if (file != null) {
        if (!hasSubtitleExtension(file.name)) {
          error = '${file.name} isn\'t a subtitle file. Pick an .srt, .ass '
              'or .vtt file.';
        } else if (file.size > maxSubtitleUploadBytes) {
          error = '${file.name} is larger than 5 MB.';
        } else {
          bytes = await file.readBytes();
          if (bytes.length > maxSubtitleUploadBytes) {
            error = '${file.name} is larger than 5 MB.';
            bytes = null;
          }
        }
      }
    } on Object {
      error = "Couldn't open the file picker";
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _picking = false;
      _error = error;
      if (file != null && bytes != null) {
        _fileName = file.name;
        _bytes = bytes;
        final ({String? code2, bool forced, bool hi}) parsed =
            parseSubtitleFilename(file.name);
        _code2 = parsed.code2 ??
            (widget.languages.isEmpty ? null : widget.languages.first.code2);
        _forced = parsed.forced;
        _hi = parsed.hi && !parsed.forced;
      }
    });
  }

  Future<void> _upload() async {
    final String? code2 = _code2;
    final String? fileName = _fileName;
    final Uint8List? bytes = _bytes;
    if (code2 == null || fileName == null || bytes == null) {
      return;
    }
    final String name = _options()
            .where((UploadLanguage l) => l.code2 == code2)
            .firstOrNull
            ?.name ??
        code2;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onUpload(
        LanguageChoice(code2: code2, forced: _forced, hi: _hi),
        fileName,
        bytes,
      );
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't upload the subtitle";
        });
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(name);
    }
  }

  /// The offered languages, plus the file's own when the list lacks it.
  List<UploadLanguage> _options() {
    final String? code2 = _code2;
    if (code2 == null ||
        widget.languages.any((UploadLanguage l) => l.code2 == code2)) {
      return widget.languages;
    }
    return <UploadLanguage>[
      ...widget.languages,
      (code2: code2, name: uploadLanguageName(code2)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? fileName = _fileName;
    final bool ready = _code2 != null && _bytes != null && !_busy;
    return SubtitleSheetFrame(
      title: 'Upload subtitle',
      subtitle: widget.title,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_error != null) SheetErrorText(_error!),
          FilledButton(
            onPressed: ready ? _upload : null,
            child: Text(_busy ? 'Uploading…' : 'Upload'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            label:
                fileName == null ? 'Choose a file' : 'Change file, $fileName',
            excludeSemantics: true,
            child: InkWell(
              onTap: _busy ? null : _pick,
              borderRadius: BorderRadius.circular(Radii.lg),
              child: CustomPaint(
                foregroundPainter: DashedRRectPainter(
                  color: scheme.outline,
                  strokeWidth: 1.6,
                  radius: Radii.lg,
                  dash: 5,
                  gap: 4,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.lg,
                    vertical: Insets.md,
                  ),
                  child: Row(
                    spacing: Insets.md,
                    children: <Widget>[
                      Icon(
                        Icons.description_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                      Expanded(
                        child: Text(
                          fileName ?? 'Choose a .srt, .ass or .vtt file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: fileName == null
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (_picking)
                        const SmallSpinner()
                      else if (fileName != null)
                        Text(
                          'Change',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: scheme.primary),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Insets.lg),
          const SheetLabel('Language'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: Insets.sm,
              children: <Widget>[
                for (final UploadLanguage l in _options())
                  ChoiceChip(
                    label: Text(l.name),
                    selected: _code2 == l.code2,
                    onSelected:
                        _busy ? null : (_) => setState(() => _code2 = l.code2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          // Bazarr stores one flag per subtitle: forced and HI exclude each
          // other.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Forced'),
            subtitle: const Text('Only the foreign-language parts'),
            value: _forced,
            onChanged: _busy
                ? null
                : (bool v) => setState(() {
                      _forced = v;
                      if (v) {
                        _hi = false;
                      }
                    }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hearing impaired'),
            subtitle: const Text('Includes sound descriptions'),
            value: _hi,
            onChanged: _busy
                ? null
                : (bool v) => setState(() {
                      _hi = v;
                      if (v) {
                        _forced = false;
                      }
                    }),
          ),
        ],
      ),
    );
  }
}
