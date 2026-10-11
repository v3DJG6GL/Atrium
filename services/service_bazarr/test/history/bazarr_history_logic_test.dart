import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/history/bazarr_history_logic.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';

BazarrHistoryItem item(
  String ts, {
  int action = 1,
  int? radarrId,
  int? sonarrSeriesId,
  int? sonarrEpisodeId,
  String? subsId,
  String? subtitlesPath,
  String provider = '',
  BazarrSubtitle? language,
  bool blacklisted = false,
}) =>
    BazarrHistoryItem(
      action: action,
      parsedTimestamp: ts,
      radarrId: radarrId,
      sonarrSeriesId: sonarrSeriesId,
      sonarrEpisodeId: sonarrEpisodeId,
      subsId: subsId,
      subtitlesPath: subtitlesPath,
      provider: provider,
      language: language,
      blacklisted: blacklisted,
    );

const HistoryStreamFlags none = (movies: false, episodes: false);

void main() {
  group('historyActionMeta', () {
    test("maps Bazarr's action codes", () {
      expect(historyActionMeta(1).kind, HistoryActionKind.downloaded);
      expect(historyActionMeta(3).kind, HistoryActionKind.upgraded);
      expect(historyActionMeta(7).label, 'Extracted');
      expect(historyActionMeta(42).kind, HistoryActionKind.unknown);
      expect(historyActionMeta(42).label, 'Changed');
    });
  });

  group('parseBazarrTimestamp', () {
    test('reads the C locale (month first, 2-digit year)', () {
      expect(
        parseBazarrTimestamp('10/09/26 14:22:05'),
        DateTime(2026, 10, 9, 14, 22, 5),
      );
    });

    test('reads en_US with AM/PM', () {
      expect(
        parseBazarrTimestamp('10/09/2026 02:22:05 PM'),
        DateTime(2026, 10, 9, 14, 22, 5),
      );
      expect(
        parseBazarrTimestamp('10/09/2026 12:05:00 AM'),
        DateTime(2026, 10, 9, 0, 5),
      );
    });

    test('reads day-first dotted dates', () {
      expect(
        parseBazarrTimestamp('09.10.2026 14:22:05'),
        DateTime(2026, 10, 9, 14, 22, 5),
      );
      // Day first: 13 is the day, so this is a valid December 13.
      expect(
        parseBazarrTimestamp('13.12.2026 08:00:00'),
        DateTime(2026, 12, 13, 8),
      );
      // The same digits with slashes read month first: no month 13.
      expect(parseBazarrTimestamp('13/12/2026 08:00:00'), isNull);
    });

    test('reads ISO', () {
      expect(
        parseBazarrTimestamp('2026-10-09T14:22:05Z')?.toUtc().toIso8601String(),
        '2026-10-09T14:22:05.000Z',
      );
      expect(parseBazarrTimestamp('2026-10-09T14:22:05Z')?.isUtc, isFalse);
    });

    test('gives up on anything else', () {
      expect(parseBazarrTimestamp('2 hours ago'), isNull);
      expect(parseBazarrTimestamp('13/45/26 10:00:00'), isNull);
      expect(parseBazarrTimestamp(null), isNull);
      expect(parseBazarrTimestamp(''), isNull);
    });

    test('rejects dates DateTime would roll over', () {
      // Month 13, day 45: DateTime(2026, 13, 45) is a real date in 2027.
      expect(parseBazarrTimestamp('13/45/26 10:00:00'), isNull);
      expect(parseBazarrTimestamp('02/30/2026 10:00:00'), isNull);
      expect(parseBazarrTimestamp('31.04.2026 10:00:00'), isNull);
    });
  });

  group('mergeHistoryStreams', () {
    final List<BazarrHistoryItem> movies = <BazarrHistoryItem>[
      item('10/09/26 14:00:00'),
      item('10/07/26 09:00:00'),
    ];
    final List<BazarrHistoryItem> episodes = <BazarrHistoryItem>[
      item('10/08/26 12:00:00'),
      item('10/01/26 12:00:00'),
    ];

    test('merges newest first', () {
      final List<HistoryEntry> merged =
          mergeHistoryStreams(movies, episodes, none);
      expect(
        merged.map(
          (HistoryEntry e) => '${e.kind.name}:${e.item.parsedTimestamp}',
        ),
        <String>[
          'movie:10/09/26 14:00:00',
          'episode:10/08/26 12:00:00',
          'movie:10/07/26 09:00:00',
          'episode:10/01/26 12:00:00',
        ],
      );
    });

    test('holds back entries older than a stream that has more pages', () {
      final List<HistoryEntry> merged = mergeHistoryStreams(
        movies,
        episodes,
        (movies: true, episodes: false),
      );
      // Movies stop at Oct 7 with more to load, so Oct 1 waits.
      expect(
        merged.map((HistoryEntry e) => e.item.parsedTimestamp),
        isNot(contains('10/01/26 12:00:00')),
      );
      expect(merged, hasLength(3));
    });

    test(
        "holds back from a stream's oldest entry, even when a newer one ends "
        'its pages', () {
      // Offset paging after new arrivals: the last page ends on a fresh entry.
      final List<BazarrHistoryItem> shifted = <BazarrHistoryItem>[
        item('10/09/26 14:00:00'),
        item('10/07/26 09:00:00'),
        item('10/10/26 08:00:00'),
      ];
      final List<HistoryEntry> merged = mergeHistoryStreams(
        shifted,
        episodes,
        (movies: true, episodes: false),
      );
      expect(merged.map((HistoryEntry x) => x.item.parsedTimestamp), <String>[
        '10/10/26 08:00:00',
        '10/09/26 14:00:00',
        '10/08/26 12:00:00',
        '10/07/26 09:00:00',
      ]);
    });

    test('drops an entry repeated across pages', () {
      final BazarrHistoryItem dup =
          item('10/08/26 12:00:00', sonarrEpisodeId: 7, subsId: 'x');
      final List<HistoryEntry> merged = mergeHistoryStreams(
        const <BazarrHistoryItem>[],
        <BazarrHistoryItem>[dup, dup.copyWith()],
        none,
      );
      expect(merged, hasLength(1));
    });

    test('keeps same-second entries for different variants of a language', () {
      const BazarrSubtitle en =
          BazarrSubtitle(name: 'English', code2: 'en', code3: 'eng');
      final List<HistoryEntry> merged = mergeHistoryStreams(
        <BazarrHistoryItem>[
          item('10/08/26 12:00:00', radarrId: 3, action: 5, language: en),
          item(
            '10/08/26 12:00:00',
            radarrId: 3,
            action: 5,
            language: en.copyWith(forced: true),
          ),
        ],
        const <BazarrHistoryItem>[],
        none,
      );
      expect(merged, hasLength(2));
    });

    test('keeps entries without a parseable time at the end', () {
      final List<HistoryEntry> merged = mergeHistoryStreams(
        <BazarrHistoryItem>[item('garbage')],
        episodes,
        none,
      );
      expect(merged.last.at, isNull);
      expect(merged.first.at, isNotNull);
    });

    test('keys entries apart across streams', () {
      final List<HistoryEntry> merged = mergeHistoryStreams(
        <BazarrHistoryItem>[item('10/08/26 12:00:00', radarrId: 7)],
        <BazarrHistoryItem>[item('10/08/26 12:00:00', sonarrEpisodeId: 7)],
        none,
      );
      expect(merged, hasLength(2));
    });
  });

  group('historyStreamsToPage', () {
    final List<BazarrHistoryItem> movies = <BazarrHistoryItem>[
      item('10/09/26 14:00:00'),
      item('10/07/26 09:00:00'),
    ];
    final List<BazarrHistoryItem> episodes = <BazarrHistoryItem>[
      item('10/08/26 12:00:00'),
      item('10/01/26 12:00:00'),
    ];
    const HistoryStreamFlags both = (movies: true, episodes: true);

    test('pages only the stream holding the cutoff', () {
      // Movies end Oct 7, episodes Oct 1: the list waits on movies.
      expect(
        historyStreamsToPage(movies, episodes, both),
        (movies: true, episodes: false),
      );
    });

    test('pages a stream only while it has more', () {
      expect(
        historyStreamsToPage(movies, episodes, (movies: false, episodes: true)),
        (movies: false, episodes: true),
      );
    });

    test('pages both on a tie or when no last entry has a time', () {
      expect(
        historyStreamsToPage(
          <BazarrHistoryItem>[item('10/01/26 12:00:00')],
          episodes,
          both,
        ),
        both,
      );
      expect(
        historyStreamsToPage(
          <BazarrHistoryItem>[item('garbage')],
          <BazarrHistoryItem>[item('nope')],
          both,
        ),
        both,
      );
    });
  });

  group('groupHistoryByDay', () {
    test('groups by local day with an Earlier bucket', () {
      final List<HistoryEntry> merged = mergeHistoryStreams(
        <BazarrHistoryItem>[
          item('10/09/26 14:00:00'),
          item('10/09/26 09:00:00'),
          item('nope'),
        ],
        const <BazarrHistoryItem>[],
        none,
      );
      final List<HistoryDayGroup> groups =
          groupHistoryByDay(merged, now: DateTime(2026, 10, 12));
      expect(
        groups.map((HistoryDayGroup g) => g.entries.length),
        <int>[2, 1],
      );
      expect(groups[1].label, 'Earlier');
      expect(groups[0].label, 'Fri, Oct 9');
    });

    test('labels today and yesterday', () {
      final List<HistoryEntry> merged = mergeHistoryStreams(
        <BazarrHistoryItem>[
          item('10/12/26 08:00:00'),
          item('10/11/26 23:59:00'),
          item('10/10/26 00:01:00'),
        ],
        const <BazarrHistoryItem>[],
        none,
      );
      final List<HistoryDayGroup> groups =
          groupHistoryByDay(merged, now: DateTime(2026, 10, 12, 9));
      expect(
        groups.map((HistoryDayGroup g) => g.label),
        <String>['Today', 'Yesterday', 'Sat, Oct 10'],
      );
    });
  });

  group('canBlacklist', () {
    HistoryEntry entry(
      HistoryKind kind, {
      int action = 1,
      bool blacklisted = false,
      String provider = 'opensubtitles',
      String? subsId = 'abc',
      String? subtitlesPath = '/m/a.en.srt',
      int? radarrId = 4,
      int? seriesId = 2,
      int? episodeId = 9,
    }) {
      final BazarrHistoryItem i = item(
        '10/09/26 14:00:00',
        action: action,
        blacklisted: blacklisted,
        provider: provider,
        subsId: subsId,
        subtitlesPath: subtitlesPath,
        radarrId: kind == HistoryKind.movie ? radarrId : null,
        sonarrSeriesId: kind == HistoryKind.episode ? seriesId : null,
        sonarrEpisodeId: kind == HistoryKind.episode ? episodeId : null,
      );
      return HistoryEntry(
        key: historyEntryKey(kind, i),
        kind: kind,
        item: i,
        at: parseBazarrTimestamp(i.parsedTimestamp),
      );
    }

    test('allows downloads, manual downloads and upgrades', () {
      for (final int action in <int>[1, 2, 3]) {
        expect(canBlacklist(entry(HistoryKind.movie, action: action)), isTrue);
        expect(
          canBlacklist(entry(HistoryKind.episode, action: action)),
          isTrue,
        );
      }
    });

    test('refuses other actions', () {
      for (final int action in <int>[0, 4, 5, 6, 7, 42]) {
        expect(
          canBlacklist(entry(HistoryKind.movie, action: action)),
          isFalse,
        );
      }
    });

    test('refuses an entry already blacklisted', () {
      expect(
        canBlacklist(entry(HistoryKind.movie, blacklisted: true)),
        isFalse,
      );
    });

    test('needs the provider', () {
      expect(canBlacklist(entry(HistoryKind.movie, provider: '')), isFalse);
    });

    test('needs the subtitle id', () {
      expect(canBlacklist(entry(HistoryKind.movie, subsId: null)), isFalse);
      expect(canBlacklist(entry(HistoryKind.movie, subsId: '')), isFalse);
    });

    test('needs the subtitle path', () {
      expect(
        canBlacklist(entry(HistoryKind.movie, subtitlesPath: null)),
        isFalse,
      );
      expect(
        canBlacklist(entry(HistoryKind.movie, subtitlesPath: '')),
        isFalse,
      );
    });

    test('needs the movie id', () {
      expect(canBlacklist(entry(HistoryKind.movie, radarrId: null)), isFalse);
    });

    test('needs the series and episode ids', () {
      expect(canBlacklist(entry(HistoryKind.episode, seriesId: null)), isFalse);
      expect(
        canBlacklist(entry(HistoryKind.episode, episodeId: null)),
        isFalse,
      );
    });
  });

  group('historyTitle', () {
    HistoryEntry entry(HistoryKind kind, BazarrHistoryItem i) =>
        HistoryEntry(key: 'k', kind: kind, item: i, at: null);

    test('names a movie, or says it is unknown', () {
      expect(
        historyTitle(
          entry(HistoryKind.movie, const BazarrHistoryItem(title: 'Dune')),
        ),
        'Dune',
      );
      expect(
        historyTitle(entry(HistoryKind.movie, const BazarrHistoryItem())),
        'Unknown movie',
      );
    });

    test('joins series, episode number and title', () {
      expect(
        historyTitle(
          entry(
            HistoryKind.episode,
            const BazarrHistoryItem(
              seriesTitle: 'Severance',
              episodeNumber: '1x02',
              episodeTitle: 'Half Loop',
            ),
          ),
        ),
        'Severance · 1x02 · Half Loop',
      );
      expect(
        historyTitle(
          entry(
            HistoryKind.episode,
            const BazarrHistoryItem(seriesTitle: 'Severance'),
          ),
        ),
        'Severance',
      );
      expect(
        historyTitle(entry(HistoryKind.episode, const BazarrHistoryItem())),
        'Unknown episode',
      );
    });
  });
}
