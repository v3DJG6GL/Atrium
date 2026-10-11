import 'package:meta/meta.dart';

/// Language identification across services that each spell languages their
/// own way, so audio and subtitle tags can be compared and shown uniformly:
///
/// - Radarr/Sonarr `mediaInfo.audioLanguages` / `subtitles`: slash-joined
///   ffprobe stream tags, usually ISO 639-2 ("eng/ger"), sometimes /T ("deu")
///   or a name ("English").
/// - Radarr/Sonarr `originalLanguage.name`: an English name, with a few arr
///   specifics ("Portuguese (Brazil)", "Flemish").
/// - Bazarr: ISO 639-1 `code2` plus its own pseudo-codes for regional
///   variants (`pb` Brazilian Portuguese, `zt` Traditional Chinese, `ea`
///   Latin American Spanish).
///
/// Pure and dependency-free, so any module can reuse it.
@immutable
class Language {
  const Language({
    required this.code2,
    required this.code3,
    required this.name,
  });

  /// ISO 639-1, or Bazarr's pseudo-code for a regional variant.
  final String code2;

  /// ISO 639-2/B ("ger", "fre"), the form ffprobe and Bazarr's code3 use.
  final String code3;

  /// English name.
  final String name;

  /// Two languages are the same language when their [code2] matches.
  @override
  bool operator ==(Object other) => other is Language && other.code2 == code2;

  @override
  int get hashCode => code2.hashCode;

  @override
  String toString() => 'Language($code2, $code3, $name)';
}

// [code2, code3 (639-2/B), 639-2/T if different, English name, ...aliases]
const List<List<String?>> _rows = [
  ['af', 'afr', null, 'Afrikaans'],
  ['sq', 'alb', 'sqi', 'Albanian'],
  ['am', 'amh', null, 'Amharic'],
  ['ar', 'ara', null, 'Arabic'],
  ['hy', 'arm', 'hye', 'Armenian'],
  ['az', 'aze', null, 'Azerbaijani'],
  ['eu', 'baq', 'eus', 'Basque'],
  ['be', 'bel', null, 'Belarusian'],
  ['bn', 'ben', null, 'Bengali', 'Bangla'],
  ['bs', 'bos', null, 'Bosnian'],
  ['bg', 'bul', null, 'Bulgarian'],
  ['my', 'bur', 'mya', 'Burmese'],
  ['ca', 'cat', null, 'Catalan'],
  [
    'zh',
    'chi',
    'zho',
    'Chinese',
    'Chinese (Simplified)',
    'Mandarin',
    'Cantonese',
  ],
  ['zt', 'zht', null, 'Chinese (Traditional)', 'Chinese Traditional'],
  ['hr', 'hrv', null, 'Croatian'],
  ['cs', 'cze', 'ces', 'Czech'],
  ['da', 'dan', null, 'Danish'],
  ['nl', 'dut', 'nld', 'Dutch', 'Flemish'],
  ['en', 'eng', null, 'English'],
  ['eo', 'epo', null, 'Esperanto'],
  ['et', 'est', null, 'Estonian'],
  ['fa', 'per', 'fas', 'Persian', 'Farsi'],
  ['fi', 'fin', null, 'Finnish'],
  ['fr', 'fre', 'fra', 'French', 'French (Canada)'],
  ['gl', 'glg', null, 'Galician'],
  ['ka', 'geo', 'kat', 'Georgian'],
  ['de', 'ger', 'deu', 'German'],
  ['el', 'gre', 'ell', 'Greek', 'Greek, Modern'],
  ['gu', 'guj', null, 'Gujarati'],
  ['he', 'heb', null, 'Hebrew'],
  ['hi', 'hin', null, 'Hindi'],
  ['hu', 'hun', null, 'Hungarian'],
  ['is', 'ice', 'isl', 'Icelandic'],
  ['id', 'ind', null, 'Indonesian'],
  ['ga', 'gle', null, 'Irish'],
  ['it', 'ita', null, 'Italian'],
  ['ja', 'jpn', null, 'Japanese'],
  ['kn', 'kan', null, 'Kannada'],
  ['kk', 'kaz', null, 'Kazakh'],
  ['km', 'khm', null, 'Khmer'],
  ['ko', 'kor', null, 'Korean'],
  ['ku', 'kur', null, 'Kurdish'],
  ['lo', 'lao', null, 'Lao'],
  ['la', 'lat', null, 'Latin'],
  ['lv', 'lav', null, 'Latvian'],
  ['lt', 'lit', null, 'Lithuanian'],
  ['lb', 'ltz', null, 'Luxembourgish'],
  ['mk', 'mac', 'mkd', 'Macedonian'],
  ['ms', 'may', 'msa', 'Malay'],
  ['ml', 'mal', null, 'Malayalam'],
  ['mt', 'mlt', null, 'Maltese'],
  ['mr', 'mar', null, 'Marathi'],
  ['mn', 'mon', null, 'Mongolian'],
  ['ne', 'nep', null, 'Nepali'],
  ['no', 'nor', null, 'Norwegian', 'Norwegian Bokmal', 'Norwegian Bokmål'],
  ['nb', 'nob', null, 'Norwegian Bokmål'],
  ['nn', 'nno', null, 'Norwegian Nynorsk'],
  ['pl', 'pol', null, 'Polish'],
  ['pt', 'por', null, 'Portuguese', 'Portuguese (Portugal)'],
  [
    'pb',
    'pob',
    null,
    'Portuguese (Brazil)',
    'Brazilian Portuguese',
    'Portuguese (Brazilian)',
  ],
  ['pa', 'pan', null, 'Punjabi', 'Panjabi'],
  ['ro', 'rum', 'ron', 'Romanian', 'Moldavian'],
  ['ru', 'rus', null, 'Russian'],
  ['sr', 'srp', null, 'Serbian'],
  ['si', 'sin', null, 'Sinhala', 'Sinhalese'],
  ['sk', 'slo', 'slk', 'Slovak'],
  ['sl', 'slv', null, 'Slovenian', 'Slovene'],
  ['so', 'som', null, 'Somali'],
  ['es', 'spa', null, 'Spanish', 'Castilian', 'Spanish (Spain)'],
  [
    'ea',
    'spl',
    null,
    'Spanish (Latino)',
    'Latin American Spanish',
    'Spanish (Latin America)',
  ],
  ['sw', 'swa', null, 'Swahili'],
  ['sv', 'swe', null, 'Swedish'],
  ['tl', 'tgl', null, 'Tagalog', 'Filipino'],
  ['ta', 'tam', null, 'Tamil'],
  ['te', 'tel', null, 'Telugu'],
  ['th', 'tha', null, 'Thai'],
  ['tr', 'tur', null, 'Turkish'],
  ['uk', 'ukr', null, 'Ukrainian'],
  ['ur', 'urd', null, 'Urdu'],
  ['uz', 'uzb', null, 'Uzbek'],
  ['vi', 'vie', null, 'Vietnamese'],
  ['cy', 'wel', 'cym', 'Welsh'],
  ['yi', 'yid', null, 'Yiddish'],
  ['zu', 'zul', null, 'Zulu'],
];

/// Every spelling (lowercased) to its language; the first row to claim a key
/// wins.
final Map<String, Language> _byKey = _buildIndex();

Map<String, Language> _buildIndex() {
  final map = <String, Language>{};
  for (final row in _rows) {
    final lang = Language(code2: row[0]!, code3: row[1]!, name: row[3]!);
    for (final key in row) {
      if (key == null || key.isEmpty) continue;
      map.putIfAbsent(key.toLowerCase(), () => lang);
    }
  }
  return map;
}

/// Region-tagged forms ("pt-BR", "zh_TW", "es-419") that map to a variant.
const Map<String, String> _regionVariants = {
  'pt-br': 'pb',
  'zh-tw': 'zt',
  'zh-hant': 'zt',
  'zh-hk': 'zt',
  'es-419': 'ea',
  'es-mx': 'ea',
};

final Map<String, String> _variantBase = {
  for (final e in _regionVariants.entries) e.value: e.key.split('-').first,
  // The arrs say "Norwegian" (no); files tag the written standard (nob/nno).
  'nb': 'no',
  'nn': 'no',
};

/// The language a variant belongs to: "pb" → "pt", "ea" → "es", "nb" → "no".
String baseLanguageCode(String code2) => _variantBase[code2] ?? code2;

/// Identify a language from any of the spellings above. Null for an empty,
/// unknown or "undetermined" (`und`) tag, so callers can drop it.
Language? normalizeLanguage(String? input) {
  final raw = input?.trim().toLowerCase();
  if (raw == null ||
      raw.isEmpty ||
      raw == 'und' ||
      raw == 'unknown' ||
      raw == 'zxx') {
    return null;
  }

  final direct = _byKey[raw];
  if (direct != null) return direct;

  // Like JS `replace('_', '-')`: only the first underscore.
  final region = raw.replaceFirst('_', '-');
  final variant = _regionVariants[region];
  if (variant != null) return _byKey[variant];
  // "en-US", "de-CH": fall back to the base language.
  final base = region.split('-').first;
  return base != raw ? _byKey[base] : null;
}

/// Parse a slash- or comma-joined language list ("English/English/German"),
/// dropping unknowns and duplicates while keeping first-seen order: one entry
/// per language, however many tracks carry it.
List<Language> parseLanguageList(String? list) {
  if (list == null || list.isEmpty) return const [];
  final seen = <String>{};
  final out = <Language>[];
  for (final part in list.split(RegExp('[/,]'))) {
    final lang = normalizeLanguage(part);
    if (lang != null && seen.add(lang.code2)) out.add(lang);
  }
  return out;
}
