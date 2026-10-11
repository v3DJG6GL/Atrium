import 'dart:collection';

import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

import '../models/bazarr_models.dart';
import '../subtitles/bazarr_subtitle_params.dart';

/// Bazarr history view logic: what each action means, when it happened, and
/// how movie and episode history merge into one day-grouped list. Pure.

/// What a history entry did, from Bazarr's `HistoryAction` enum
/// (frontend/src/components/bazarr/HistoryIcon.tsx).
enum HistoryActionKind {
  deleted,
  downloaded,
  manual,
  upgraded,
  uploaded,
  synced,
  translated,
  extracted,
  unknown,
}

/// An action's kind and its label.
typedef HistoryActionMeta = ({HistoryActionKind kind, String label});

const Map<int, HistoryActionMeta> _actions = <int, HistoryActionMeta>{
  0: (kind: HistoryActionKind.deleted, label: 'Deleted'),
  1: (kind: HistoryActionKind.downloaded, label: 'Downloaded'),
  2: (kind: HistoryActionKind.manual, label: 'Downloaded manually'),
  3: (kind: HistoryActionKind.upgraded, label: 'Upgraded'),
  4: (kind: HistoryActionKind.uploaded, label: 'Uploaded'),
  5: (kind: HistoryActionKind.synced, label: 'Synced'),
  6: (kind: HistoryActionKind.translated, label: 'Translated'),
  7: (kind: HistoryActionKind.extracted, label: 'Extracted'),
};

/// The kind and label of Bazarr's action code [action]; "Changed" for a code
/// this app doesn't know.
HistoryActionMeta historyActionMeta(int action) =>
    _actions[action] ?? (kind: HistoryActionKind.unknown, label: 'Changed');

final RegExp _isoPrefix = RegExp(r'^\d{4}-\d{2}-\d{2}T');
final RegExp _localeTimestamp = RegExp(
  r'^(\d{1,2})([/.])(\d{1,2})\2(\d{2}|\d{4})[ ,]+(\d{1,2}):(\d{2})'
  r'(?::(\d{2}))?\s*([AaPp][Mm])?$',
);

/// When an entry happened, in local time.
///
/// Bazarr only sends `parsed_timestamp`, formatted with Python's
/// locale-dependent "%x %X": "10/09/26 14:22:05" in the C locale Docker
/// images run, "10/09/2026 02:22:05 PM" in en_US, "09.10.2026 14:22:05" in
/// de_DE. ISO strings are accepted too. Anything else is null and lands in an
/// "Earlier" group rather than being guessed at.
DateTime? parseBazarrTimestamp(String? raw) {
  if (raw == null) {
    return null;
  }
  final String value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  if (_isoPrefix.hasMatch(value)) {
    return DateTime.tryParse(value)?.toLocal();
  }
  final RegExpMatch? m = _localeTimestamp.firstMatch(value);
  if (m == null) {
    return null;
  }
  final String a = m.group(1)!;
  final String sep = m.group(2)!;
  final String b = m.group(3)!;
  final String y = m.group(4)!;
  // Slashes are month-first (US / C locale); dots are day-first (European).
  final int month = int.parse(sep == '/' ? a : b);
  final int day = int.parse(sep == '/' ? b : a);
  int year = int.parse(y);
  if (y.length == 2) {
    year += 2000;
  }
  int hour = int.parse(m.group(5)!);
  final int minute = int.parse(m.group(6)!);
  final int second = int.parse(m.group(7) ?? '0');
  final String? ampm = m.group(8);
  if (ampm != null) {
    final bool pm = ampm.toLowerCase() == 'pm';
    if (pm && hour < 12) {
      hour += 12;
    }
    if (!pm && hour == 12) {
      hour = 0;
    }
  }
  if (hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  final DateTime date = DateTime(year, month, day, hour, minute, second);
  // DateTime rolls an invalid date over (month 13 → January next year), so a
  // date that doesn't come back as written wasn't one.
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// Which history stream an entry comes from.
enum HistoryKind { movie, episode }

/// Whether each stream still has pages to load (or, for
/// [historyStreamsToPage]'s result, should be paged).
typedef HistoryStreamFlags = ({bool movies, bool episodes});

/// One history item, tagged with its stream, a key unique in the merged
/// list, and when it happened (null when that's unknown).
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.key,
    required this.kind,
    required this.item,
    required this.at,
  });

  final String key;
  final HistoryKind kind;
  final BazarrHistoryItem item;
  final DateTime? at;

  @override
  bool operator ==(Object other) =>
      other is HistoryEntry &&
      other.key == key &&
      other.kind == kind &&
      other.item == item &&
      other.at == at;

  @override
  int get hashCode => Object.hash(key, kind, item, at);

  @override
  String toString() => 'HistoryEntry($key)';
}

/// What identifies a history item within its stream.
String historyEntryKey(HistoryKind kind, BazarrHistoryItem item) {
  final BazarrSubtitle? language = item.language;
  return <Object>[
    kind.name,
    if (item.parsedTimestamp.isNotEmpty)
      item.parsedTimestamp
    else
      item.timestamp,
    item.radarrId ?? item.sonarrEpisodeId ?? '',
    item.action,
    language?.code2 ?? '',
    // A batch can sync or delete "en" and "en forced" in the same second.
    if (language?.forced ?? false) 'f' else '',
    if (language?.hi ?? false) 'h' else '',
    item.subsId ?? '',
    item.subtitlesPath ?? '',
  ].join('|');
}

/// A stream's oldest loaded time in milliseconds — not simply its last
/// entry: offset paging shifts when entries arrive between page fetches, so a
/// later page can end on a brand-new entry. Null when nothing is dated.
int? _oldestAt(Iterable<DateTime?> times) {
  int? oldest;
  for (final DateTime? t in times) {
    if (t == null) {
      continue;
    }
    final int ms = t.millisecondsSinceEpoch;
    if (oldest == null || ms < oldest) {
      oldest = ms;
    }
  }
  return oldest;
}

int? _maxOf(int? a, int? b) {
  if (a == null) {
    return b;
  }
  if (b == null) {
    return a;
  }
  return a > b ? a : b;
}

/// Merges movie and episode history (each newest first, possibly paged) into
/// one newest-first list, undated entries last. When a stream still has more
/// pages, dated entries older than its oldest loaded one are held back — they
/// might sort below entries of that stream not yet loaded — so "All" never
/// shows an out-of-order gap.
List<HistoryEntry> mergeHistoryStreams(
  List<BazarrHistoryItem> movies,
  List<BazarrHistoryItem> episodes,
  HistoryStreamFlags more,
) {
  // Offset paging can hand back an entry twice (a new download shifts every
  // page by one before a refetch completes), so entries are deduplicated on
  // what identifies them.
  final Set<String> seen = <String>{};
  List<HistoryEntry> tag(HistoryKind kind, List<BazarrHistoryItem> list) {
    final List<HistoryEntry> out = <HistoryEntry>[];
    for (final BazarrHistoryItem item in list) {
      final String key = historyEntryKey(kind, item);
      if (!seen.add(key)) {
        continue;
      }
      out.add(
        HistoryEntry(
          key: key,
          kind: kind,
          item: item,
          at: parseBazarrTimestamp(item.parsedTimestamp),
        ),
      );
    }
    return out;
  }

  final List<HistoryEntry> m = tag(HistoryKind.movie, movies);
  final List<HistoryEntry> e = tag(HistoryKind.episode, episodes);

  int? cutoff;
  if (more.movies) {
    cutoff = _maxOf(cutoff, _oldestAt(m.map((HistoryEntry x) => x.at)));
  }
  if (more.episodes) {
    cutoff = _maxOf(cutoff, _oldestAt(e.map((HistoryEntry x) => x.at)));
  }

  final List<HistoryEntry> merged = <HistoryEntry>[
    for (final HistoryEntry entry in <HistoryEntry>[...m, ...e])
      if (cutoff == null ||
          entry.at == null ||
          entry.at!.millisecondsSinceEpoch >= cutoff)
        entry,
  ];
  // List.sort isn't stable; sort on (time, original position) so equal times
  // keep movies before episodes and each stream's own order.
  final Map<HistoryEntry, int> position = Map<HistoryEntry, int>.identity();
  for (int i = 0; i < merged.length; i++) {
    position[merged[i]] = i;
  }
  merged.sort((HistoryEntry x, HistoryEntry y) {
    final DateTime? xa = x.at;
    final DateTime? ya = y.at;
    if (xa != null && ya != null) {
      final int byTime = ya.compareTo(xa);
      if (byTime != 0) {
        return byTime;
      }
    } else if (xa != null) {
      return -1;
    } else if (ya != null) {
      return 1;
    }
    return position[x]!.compareTo(position[y]!);
  });
  return merged;
}

/// Which streams "load more" should page: those holding the merge cutoff
/// (the newest oldest-loaded entry among streams with more pages), since
/// paging the other one only adds entries that stay held back. With no
/// cutoff (no stream with more pages has a dated entry) every stream with
/// more pages is paged.
HistoryStreamFlags historyStreamsToPage(
  List<BazarrHistoryItem> movies,
  List<BazarrHistoryItem> episodes,
  HistoryStreamFlags more,
) {
  int? oldest(List<BazarrHistoryItem> list) => _oldestAt(
        list.map(
          (BazarrHistoryItem x) => parseBazarrTimestamp(x.parsedTimestamp),
        ),
      );
  final int? m = more.movies ? oldest(movies) : null;
  final int? e = more.episodes ? oldest(episodes) : null;
  final int? cutoff = _maxOf(m, e);
  if (cutoff == null) {
    return more;
  }
  return (
    movies: more.movies && m == cutoff,
    episodes: more.episodes && e == cutoff,
  );
}

/// Key of the day group holding undated entries.
const String earlierHistoryGroup = 'earlier';

/// One day's entries, newest first.
@immutable
class HistoryDayGroup {
  const HistoryDayGroup({
    required this.key,
    required this.label,
    required this.entries,
  });

  /// `yyyy-mm-dd` (local), or [earlierHistoryGroup].
  final String key;

  /// "Today", "Yesterday", "Mon, Oct 6" or "Earlier".
  final String label;
  final List<HistoryEntry> entries;
}

String _dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Day sections ("Today", "Yesterday", "Mon, Oct 6", "Earlier") of
/// [entries], in the order their days first appear.
List<HistoryDayGroup> groupHistoryByDay(
  List<HistoryEntry> entries, {
  DateTime? now,
}) {
  final DateTime today = now ?? DateTime.now();
  final String todayKey = _dayKey(today);
  final String yesterdayKey =
      _dayKey(DateTime(today.year, today.month, today.day - 1));
  final LinkedHashMap<String, List<HistoryEntry>> groups =
      LinkedHashMap<String, List<HistoryEntry>>();
  final Map<String, DateTime> days = <String, DateTime>{};
  for (final HistoryEntry entry in entries) {
    final DateTime? at = entry.at;
    final String key = at == null ? earlierHistoryGroup : _dayKey(at);
    if (at != null) {
      days[key] ??= at;
    }
    groups.putIfAbsent(key, () => <HistoryEntry>[]).add(entry);
  }
  return <HistoryDayGroup>[
    for (final MapEntry<String, List<HistoryEntry>> g in groups.entries)
      HistoryDayGroup(
        key: g.key,
        label: switch (g.key) {
          earlierHistoryGroup => 'Earlier',
          final String k when k == todayKey => 'Today',
          final String k when k == yesterdayKey => 'Yesterday',
          _ => DateFormat.MMMEd().format(days[g.key]!),
        },
        entries: g.value,
      ),
  ];
}

/// The movie or episode [entry] is about, or null when its ids are missing.
SubtitleTarget? historyTargetOf(HistoryEntry entry) {
  final BazarrHistoryItem item = entry.item;
  switch (entry.kind) {
    case HistoryKind.movie:
      final int? radarrId = item.radarrId;
      return radarrId != null && radarrId > 0 ? MovieTarget(radarrId) : null;
    case HistoryKind.episode:
      final int? seriesId = item.sonarrSeriesId;
      final int? episodeId = item.sonarrEpisodeId;
      return seriesId != null &&
              seriesId > 0 &&
              episodeId != null &&
              episodeId > 0
          ? EpisodeTarget(seriesId, episodeId)
          : null;
  }
}

/// Whether "Blacklist and search again" applies to [entry]: a download or
/// upgrade, not blacklisted yet, with everything the blacklist call needs.
bool canBlacklist(HistoryEntry entry) {
  final BazarrHistoryItem item = entry.item;
  final HistoryActionKind kind = historyActionMeta(item.action).kind;
  return (kind == HistoryActionKind.downloaded ||
          kind == HistoryActionKind.manual ||
          kind == HistoryActionKind.upgraded) &&
      !item.blacklisted &&
      item.provider.isNotEmpty &&
      (item.subsId?.isNotEmpty ?? false) &&
      (item.subtitlesPath?.isNotEmpty ?? false) &&
      historyTargetOf(entry) != null;
}

/// The movie title, or "Series · 1x02 · Episode title".
String historyTitle(HistoryEntry entry) {
  final BazarrHistoryItem item = entry.item;
  switch (entry.kind) {
    case HistoryKind.movie:
      return item.title.isNotEmpty ? item.title : 'Unknown movie';
    case HistoryKind.episode:
      final String joined = <String>[
        item.seriesTitle,
        item.episodeNumber,
        item.episodeTitle,
      ].where((String s) => s.isNotEmpty).join(' · ');
      return joined.isNotEmpty ? joined : 'Unknown episode';
  }
}

/// "Downloaded · opensubtitles · 93%": the action, provider and score.
String historySummary(BazarrHistoryItem item) => <String>[
      historyActionMeta(item.action).label,
      item.provider,
      item.score,
    ].where((String s) => s.isNotEmpty).join(' · ');
