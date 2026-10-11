import 'package:core_subtitles/core_subtitles.dart';
import 'package:meta/meta.dart';

import '../../models/bazarr_models.dart';

/// The language filter value that shows every result.
const String allLanguages = 'all';

/// How the manual search results are ordered.
enum ManualSearchSort {
  /// Highest score first.
  best('Best match'),

  /// Provider name A to Z, then highest score first.
  provider('Provider');

  const ManualSearchSort(this.label);

  final String label;
}

/// How good a score is, for the score badge's colour.
enum ScoreBand { high, mid, low }

/// Bazarr scores manual results as a percentage of the best possible match:
/// 90 and up is [ScoreBand.high], 70 and up [ScoreBand.mid].
ScoreBand scoreBand(num score) {
  if (score >= 90) {
    return ScoreBand.high;
  }
  if (score >= 70) {
    return ScoreBand.mid;
  }
  return ScoreBand.low;
}

/// "87%".
String scoreLabel(num score) => '${score.round()}%';

/// A result's language, for display: the chip code and the English name.
/// Unknown codes fall back to Bazarr's own spelling.
@immutable
class ResultLanguage {
  const ResultLanguage(this.code2, this.name);

  final String code2;
  final String name;
}

/// The display language of a raw Bazarr language value ("de", "pb", …).
ResultLanguage resultLanguage(String raw) {
  final Language? lang = normalizeLanguage(raw);
  return ResultLanguage(lang?.code2 ?? raw, lang?.name ?? raw);
}

/// "True" (as Bazarr spells it) is set; anything else isn't.
bool isBazarrTrue(String value) => value.toLowerCase() == 'true';

/// A result's language with its flags: "German, forced, hearing impaired".
String resultLanguageLine(BazarrSubtitleSearchResult r) =>
    '${resultLanguage(r.language).name}'
    '${isBazarrTrue(r.forced) ? ', forced' : ''}'
    '${isBazarrTrue(r.hearingImpaired) ? ', hearing impaired' : ''}';

/// One language filter option: Bazarr's raw value, its name and how many
/// results it has.
@immutable
class LanguageCount {
  const LanguageCount(this.language, this.name, this.count);

  /// Bazarr's raw language value, the filter key.
  final String language;
  final String name;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is LanguageCount &&
      other.language == language &&
      other.name == name &&
      other.count == count;

  @override
  int get hashCode => Object.hash(language, name, count);

  @override
  String toString() => 'LanguageCount($language, $name, $count)';
}

/// The languages present in [results], in order of first appearance, with
/// their result counts.
List<LanguageCount> languageCounts(List<BazarrSubtitleSearchResult> results) {
  final Map<String, int> counts = <String, int>{};
  for (final BazarrSubtitleSearchResult r in results) {
    counts[r.language] = (counts[r.language] ?? 0) + 1;
  }
  return <LanguageCount>[
    for (final MapEntry<String, int> e in counts.entries)
      LanguageCount(e.key, resultLanguage(e.key).name, e.value),
  ];
}

/// The name shown for a language filter value: "All languages" or the
/// language's name.
String languageFilterName(String language) =>
    language == allLanguages ? 'All languages' : resultLanguage(language).name;

/// [results] limited to [language] ([allLanguages] keeps everything) and
/// ordered by [sort]. Ties keep Bazarr's order.
List<BazarrSubtitleSearchResult> filterAndSortResults(
  List<BazarrSubtitleSearchResult> results, {
  required String language,
  required ManualSearchSort sort,
}) {
  final List<(int, BazarrSubtitleSearchResult)> indexed =
      <(int, BazarrSubtitleSearchResult)>[
    for (int i = 0; i < results.length; i++)
      if (language == allLanguages || results[i].language == language)
        (i, results[i]),
  ];
  indexed.sort((
    (int, BazarrSubtitleSearchResult) a,
    (int, BazarrSubtitleSearchResult) b,
  ) {
    int c = 0;
    if (sort == ManualSearchSort.provider) {
      c = a.$2.provider.toLowerCase().compareTo(b.$2.provider.toLowerCase());
    }
    if (c == 0) {
      c = b.$2.score.compareTo(a.$2.score);
    }
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return <BazarrSubtitleSearchResult>[
    for (final (int, BazarrSubtitleSearchResult) e in indexed) e.$2,
  ];
}

/// "5 results", "2 of 5 results", "1 result".
String resultCountLabel(int shown, int total) =>
    '$shown${shown != total ? ' of $total' : ''} '
    'result${total == 1 ? '' : 's'}';

/// Provider match keys arrive snake_case: "release_group" → "Release group".
String humanizeMatchKey(String key) {
  final String spaced = key.replaceAll('_', ' ').trim();
  if (spaced.isEmpty) {
    return spaced;
  }
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// "just now" (under 10 s), "12s ago", "3m ago", "1h ago".
String relativeTimeLabel(DateTime at, DateTime now) {
  final Duration d = now.difference(at);
  final int seconds = d.isNegative ? 0 : d.inSeconds;
  if (seconds < 10) {
    return 'just now';
  }
  if (seconds < 60) {
    return '${seconds}s ago';
  }
  final int minutes = seconds ~/ 60;
  if (minutes < 60) {
    return '${minutes}m ago';
  }
  return '${minutes ~/ 60}h ago';
}

/// A stable key for a result row.
String resultKey(BazarrSubtitleSearchResult r) => '${r.provider}:${r.subtitle}';
