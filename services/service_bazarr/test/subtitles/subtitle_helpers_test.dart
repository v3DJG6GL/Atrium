import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitle_mapping.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitle_providers.dart';
import 'package:service_bazarr/src/subtitles/bazarr_version.dart';
import 'package:service_bazarr/src/subtitles/subtitle_actions.dart';
import 'package:service_bazarr/src/subtitles/subtitle_ui_text.dart';
import 'package:service_bazarr/src/subtitles/ui/delete_subtitle_dialog.dart';
import 'package:service_bazarr/src/subtitles/ui/series_coverage_card.dart';
import 'package:service_bazarr/src/subtitles/ui/subtitle_row_menu.dart';
import 'package:service_bazarr/src/subtitles/ui/subtitle_timing_sheet.dart';

import 'subtitle_test_support.dart';

BazarrVersionInfo versionInfo(String? version, {bool failed = false}) {
  final BazarrVersionState state = bazarrVersionState(
    version: version,
    hasStatus: version != null,
    failed: failed,
  );
  return BazarrVersionInfo(
    state: state,
    capabilities: BazarrCapabilities.forVersion(
      state == BazarrVersionState.known ? version : null,
    ),
    version: version,
  );
}

void main() {
  final List<SubtitleRow> rows = movieFixture.subtitleRows();
  SubtitleRow row(String code2) =>
      rows.firstWhere((SubtitleRow r) => r.code2 == code2);

  group('formatOffset', () {
    test('one decimal on a multiple of 100 ms, else three', () {
      expect(formatOffset(0), '0.0 s');
      expect(formatOffset(1500), '+1.5 s');
      expect(formatOffset(-250), '\u22120.250 s');
      expect(formatOffset(-300), '\u22120.3 s');
      expect(formatOffset(60000), '+60.0 s');
    });
  });

  group('describeSubtitleRow', () {
    test('external file with format and size', () {
      expect(describeSubtitleRow(row('de')), 'External · SRT · 84 KB');
    });

    test('embedded track with and without a number', () {
      expect(describeSubtitleRow(row('en')), 'Embedded track 3');
      final SubtitleRow bare = buildSubtitleRows(
        subtitles: <SubtitleTrack>[
          const SubtitleTrack(code2: 'en', name: 'English'),
        ],
      ).single;
      expect(describeSubtitleRow(bare), 'Embedded');
    });

    test('missing with flags', () {
      final SubtitleRow missing = buildSubtitleRows(
        missing: <SubtitleTrack>[
          const SubtitleTrack(
            code2: 'de',
            name: 'German',
            forced: true,
            hi: true,
          ),
        ],
      ).single;
      expect(
        describeSubtitleRow(missing),
        'Forced · Hearing impaired · Missing',
      );
    });
  });

  test('file names of POSIX and Windows paths', () {
    expect(subtitleFileName('/movies/Film/Film.de.srt'), 'Film.de.srt');
    expect(subtitleFileName(r'D:\Movies\Film\Film.en.srt'), 'Film.en.srt');
  });

  test('file sizes', () {
    expect(formatFileSize(512), '512 B');
    expect(formatFileSize(86016), '84 KB');
    expect(formatFileSize(1258291), '1.2 MB');
  });

  test('menu titles carry the flags', () {
    const SubtitleRow r = SubtitleRow(
      key: 'k',
      code2: 'de',
      name: 'German',
      forced: true,
      hi: false,
      state: SubtitleState.present,
    );
    expect(subtitleMenuTitle(r), 'German (forced)');
  });

  test('delete message', () {
    expect(
      deleteSubtitleMessage(row('de')),
      'Delete the German subtitle file? If the language profile asks for '
      'it, Bazarr searches for it again.',
    );
  });

  group('profiles', () {
    test('description by codes, HI marked', () {
      expect(profileDescription(profilesFixture.single), 'EN + DE HI');
    });

    test('display name states', () {
      const AsyncValue<List<BazarrLanguageProfile>> loaded =
          AsyncData<List<BazarrLanguageProfile>>(profilesFixture);
      expect(profileDisplayName(null, loaded), isNull);
      expect(profileDisplayName(1, loaded), 'Default');
      expect(profileDisplayName(5, loaded), 'Unknown profile');
      expect(
        profileDisplayName(
          1,
          const AsyncLoading<List<BazarrLanguageProfile>>(),
        ),
        '…',
      );
      expect(
        profileDisplayName(
          1,
          AsyncError<List<BazarrLanguageProfile>>(
            StateError('x'),
            StackTrace.empty,
          ),
        ),
        'Unavailable',
      );
    });

    test('options end with None; none when the list failed', () {
      final List<PickerOption<int>> options = profileOptions(profilesFixture);
      expect(options.map((PickerOption<int> o) => o.label), <String>[
        'Default',
        'None',
      ]);
      expect(options.last.value, noProfileValue);
      expect(profileOptions(null), isEmpty);
    });

    test('coverage columns from profile items', () {
      final List<CoverageLanguage> columns =
          profileColumns(profilesFixture.single);
      expect(columns.map((CoverageLanguage c) => c.key), <String>[
        'en|',
        'de|h',
      ]);
    });
  });

  group('translateOptions', () {
    test('missing languages first, then enabled ones, never the source', () {
      final List<PickerOption<String>> options = translateOptions(
        sourceCode2: 'de',
        rows: rows,
        enabled: languagesFixture.where((BazarrLanguage l) => l.enabled),
      );
      expect(options.map((PickerOption<String> o) => o.value), <String>[
        'fr',
        'en',
      ]);
      expect(options.first.description, 'Missing in the profile');
      expect(options.last.description, isNull);
    });

    test('a language missing twice is offered once', () {
      final List<SubtitleRow> twice = buildSubtitleRows(
        missing: <SubtitleTrack>[
          const SubtitleTrack(code2: 'fr', name: 'French'),
          const SubtitleTrack(code2: 'fr', name: 'French', forced: true),
        ],
      );
      expect(
        translateOptions(
          sourceCode2: 'en',
          rows: twice,
          enabled: const <BazarrLanguage>[],
        ).length,
        1,
      );
    });
  });

  group('uploadLanguages', () {
    test('profile languages first, then enabled, each once', () {
      final List<UploadLanguage> langs = uploadLanguages(
        profile: profilesFixture.single,
        enabled: languagesFixture.where((BazarrLanguage l) => l.enabled),
      );
      expect(langs.map((UploadLanguage l) => l.code2), <String>[
        'en',
        'de',
        'fr',
      ]);
      expect(langs.first.name, 'English');
    });

    test('names fall back to the language table', () {
      expect(
        uploadLanguages(profile: profilesFixture.single).last.name,
        'German',
      );
      expect(uploadLanguageName('xx'), 'xx');
    });
  });

  group('row menu', () {
    test('external .srt: every tool, timing and clean-up enabled', () {
      final List<SubtitleRowMenuEntry> entries =
          subtitleRowMenuEntries(row('de'), versionInfo('1.6.2'));
      expect(entries.map((SubtitleRowMenuEntry e) => e.label), <String>[
        'Sync to audio',
        'Adjust timing…',
        'Translate…',
        'Clean up…',
        'Delete subtitle',
      ]);
      expect(entries.every((SubtitleRowMenuEntry e) => e.enabled), isTrue);
    });

    test('external non-srt: timing and clean-up off', () {
      final SubtitleRow ass = buildSubtitleRows(
        subtitles: <SubtitleTrack>[
          const SubtitleTrack(code2: 'de', name: 'German', path: '/a.de.ass'),
        ],
      ).single;
      final List<SubtitleRowMenuEntry> entries =
          subtitleRowMenuEntries(ass, versionInfo('1.6.2'));
      expect(
        entries
            .where((SubtitleRowMenuEntry e) => !e.enabled)
            .map((SubtitleRowMenuEntry e) => e.subtitle),
        <String>['Only for .srt files', 'Only for .srt files'],
      );
    });

    test('embedded: gated by version', () {
      List<SubtitleRowMenuEntry> at(BazarrVersionInfo v) =>
          subtitleRowMenuEntries(row('en'), v);
      final List<SubtitleRowMenuEntry> old = at(versionInfo('1.6.1'));
      expect(old.first.subtitle, 'Needs Bazarr 1.6.2 or later');
      expect(old.first.enabled, isFalse);
      expect(old.last.subtitle, 'Saves this track next to the video');
      expect(old.last.enabled, isTrue);

      expect(
        at(versionInfo(null)).first.subtitle,
        'Checking Bazarr version…',
      );
      expect(
        at(versionInfo(null, failed: true)).first.subtitle,
        "Couldn't read Bazarr's version",
      );
      expect(
        at(versionInfo('1.6.2')).first.subtitle,
        'Extracts the track, then translates it',
      );
    });
  });

  group('timing defaults', () {
    test('a 25 fps video converts from 23.976', () {
      expect(defaultFrameRates(25), (from: 23.976, to: 25));
    });

    test('an unlisted rate plays at 23.976, made for 25', () {
      expect(defaultFrameRates(12.5), (from: 25, to: 23.976));
      expect(defaultFrameRates(null), (from: 25, to: 23.976));
      expect(knownFrameRate(23.9761), 23.976);
    });
  });

  group('runConcurrently', () {
    test('at most four at a time; fails only when all fail', () async {
      int running = 0;
      int peak = 0;
      await runConcurrently<int>(
        List<int>.generate(10, (int i) => i),
        (int i) async {
          running++;
          peak = running > peak ? running : peak;
          await Future<void>.delayed(Duration.zero);
          running--;
          if (i.isEven) {
            throw StateError('$i');
          }
        },
      );
      expect(peak, 4);
      await expectLater(
        runConcurrently<int>(
          <int>[1, 2],
          (int i) async => throw StateError('all'),
        ),
        throwsStateError,
      );
    });
  });

  group('series episodes', () {
    final BazarrSeriesEpisodes view = BazarrSeriesEpisodes(
      episodesFixture.reversed.toList(),
    );

    test('in airing order, with gaps per season', () {
      expect(
        view.episodes.map((BazarrEpisode e) => e.sonarrEpisodeId),
        <int>[101, 102, 201, 202, 203],
      );
      expect(view.gapsBySeason, <int, int>{1: 1, 2: 2});
      expect(view.gapOrder, <int>[102, 201, 203]);
    });

    test('steps to the neighbouring gaps', () {
      expect(view.previousGap(201)?.sonarrEpisodeId, 102);
      expect(view.nextGap(201)?.sonarrEpisodeId, 203);
      expect(view.nextGap(202)?.sonarrEpisodeId, 203);
      expect(view.previousGap(102), isNull);
      expect(view.nextGap(203), isNull);
    });
  });

  group('coverage grid', () {
    final CoverageGrid grid = buildCoverageGrid(
      episodesFixture.map((BazarrEpisode e) => e.toCoverageEpisode()),
      profileColumns: profileColumns(seriesProfiles.single),
    );

    test('opens on the newest season with gaps', () {
      expect(defaultCoverageSeason(grid), 2);
      final CoverageGrid noGaps = buildCoverageGrid(
        <CoverageEpisode>[
          const CoverageEpisode(episodeId: 1, season: 1, episode: 1),
          const CoverageEpisode(episodeId: 2, season: 3, episode: 1),
        ],
        profileColumns: <CoverageLanguage>[],
      );
      expect(defaultCoverageSeason(noGaps), 3);
    });

    test('totals skip unwanted cells', () {
      final List<CoverageTotal> totals = coverageTotals(grid);
      expect(totals.single.done, 2);
      expect(totals.single.total, 5);
    });

    test('maps taps to episodes', () {
      final CoverageSeason season2 = grid.seasons.first;
      const double y =
          CoverageGridMetrics.rowsTop + CoverageGridMetrics.cell / 2;
      expect(coverageCellAt(season2, 1, const Offset(9, y)), 201);
      expect(
        coverageCellAt(
          season2,
          1,
          const Offset(CoverageGridMetrics.columnStep * 2 + 9, y),
        ),
        203,
      );
      expect(coverageCellAt(season2, 1, const Offset(9, 4)), isNull);
      expect(coverageCellAt(season2, 1, const Offset(500, y)), isNull);
    });

    test('cell labels', () {
      final CoverageSeason season2 = grid.seasons.first;
      expect(
        coverageCellLabel(
          season2.episodes.first,
          CoverageLanguage.of('de', forced: true, hi: true),
          CoverageCell.missing,
        ),
        'Episode 1, DE forced HI: missing',
      );
    });
  });
}
