import 'language_codes.dart';

// Subtitle file name handling for uploads: which extensions Bazarr accepts,
// and what a conventional name ("Film.de.forced.srt",
// "Show.S01E02.en.sdh.srt") says about language and flags, to prefill the
// upload form.

/// The extensions Bazarr accepts (subliminal's `SUBTITLE_EXTENSIONS`).
const List<String> subtitleExtensions = [
  '.srt',
  '.sub',
  '.smi',
  '.txt',
  '.ssa',
  '.ass',
  '.mpl',
  '.vtt',
];

/// Whether [name] ends in one of [subtitleExtensions], in any case.
bool hasSubtitleExtension(String name) {
  final lower = name.toLowerCase();
  return subtitleExtensions.any(lower.endsWith);
}

const Set<String> _forcedTags = {'forced', 'foreign'};
const Set<String> _hiTags = {'hi', 'sdh', 'cc'};

/// Read language, forced and HI tags from the dot-separated parts before the
/// extension. Tags may come in any order after the title; the language is the
/// last part that names one, searched only through the trailing run of tags
/// (so a title word such as "No" or "It" isn't read as a language). "hi"
/// doubles as Hindi's code, so it only counts as the HI flag when another
/// part names the language.
({String? code2, bool forced, bool hi}) parseSubtitleFilename(String name) {
  final split = name.split('.');
  final parts = [
    for (final p in split.sublist(0, split.length - 1)) p.toLowerCase(),
  ];
  // The title itself is never a tag.
  final tags = parts.length > 1 ? parts.sublist(1) : const <String>[];

  // Walk back over the trailing run of tags: flags in any order around at
  // most one language. Anything before it is title ("A.Foreign.Affair").
  String? code2;
  var start = tags.length;
  for (var i = tags.length - 1; i >= 0; i--) {
    final t = tags[i];
    if (!_forcedTags.contains(t) && !_hiTags.contains(t)) {
      final lang = code2 == null && t.length >= 2 ? normalizeLanguage(t) : null;
      if (lang == null) break;
      code2 = lang.code2;
    }
    start = i;
  }
  final run = tags.sublist(start);
  final forced = run.any(_forcedTags.contains);
  final hi = run.any(
    (t) => _hiTags.contains(t) && (t != 'hi' || code2 != null),
  );
  if (code2 == null && run.contains('hi')) {
    // A lone "hi" is more likely Hindi than a flag on an unnamed language;
    // "sdh"/"cc" or a second "hi" (Bazarr's own Film.hi.hi.srt) flag Hindi
    // HI.
    return (
      code2: 'hi',
      forced: forced,
      hi: run.where((t) => t == 'hi').length > 1 ||
          run.any((t) => t == 'sdh' || t == 'cc'),
    );
  }
  return (code2: code2, forced: forced, hi: hi);
}
