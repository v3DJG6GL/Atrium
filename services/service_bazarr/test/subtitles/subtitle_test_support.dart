import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/src/bazarr_api.dart';
import 'package:service_bazarr/src/bazarr_providers.dart';
import 'package:service_bazarr/src/link/bazarr_link_providers.dart';
import 'package:service_bazarr/src/models/bazarr_models.dart';
import 'package:service_bazarr/src/subtitles/bazarr_activity.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitle_params.dart';
import 'package:service_bazarr/src/subtitles/bazarr_subtitle_providers.dart';

import '../support/fake_scheduler.dart';

// Shared fixtures for the subtitle UI tests.

const Instance bazarr = Instance(
  id: 'b1',
  name: 'Bazarr',
  kind: ServiceKind.bazarr,
  localUrl: 'http://bazarr:6767',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'k'),
);

const Instance radarr = Instance(
  id: 'r1',
  name: 'Movies',
  kind: ServiceKind.radarr,
  localUrl: 'http://radarr:7878',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'k'),
);

const Instance sonarr = Instance(
  id: 's1',
  name: 'Shows',
  kind: ServiceKind.sonarr,
  localUrl: 'http://sonarr:8989',
  externalUrl: '',
  urlMode: UrlMode.auto,
  auth: InstanceAuthApiKey(apiKey: 'k'),
);

const BazarrSubtitle germanFile = BazarrSubtitle(
  name: 'German',
  code2: 'de',
  code3: 'ger',
  path: '/movies/Film (2024)/Film.de.srt',
  fileSize: 86016,
);

const BazarrSubtitle englishEmbedded = BazarrSubtitle(
  name: 'English',
  code2: 'en',
  code3: 'eng',
  id: 7,
  embeddedTrackId: 3,
);

const BazarrSubtitle frenchMissing =
    BazarrSubtitle(name: 'French', code2: 'fr', code3: 'fre');

const BazarrMovie movieFixture = BazarrMovie(
  radarrId: 42,
  title: 'Film',
  profileId: 1,
  subtitles: <BazarrSubtitle>[germanFile, englishEmbedded],
  missingSubtitles: <BazarrSubtitle>[frenchMissing],
  audioLanguage: <BazarrLanguage>[
    BazarrLanguage(name: 'English', code2: 'en', code3: 'eng'),
  ],
);

const List<BazarrLanguageProfile> profilesFixture = <BazarrLanguageProfile>[
  BazarrLanguageProfile(
    profileId: 1,
    name: 'Default',
    items: <BazarrProfileItem>[
      BazarrProfileItem(id: 1, language: 'en'),
      BazarrProfileItem(id: 2, language: 'de', hi: 'True'),
    ],
  ),
];

const List<BazarrLanguage> languagesFixture = <BazarrLanguage>[
  BazarrLanguage(name: 'English', code2: 'en', code3: 'eng', enabled: true),
  BazarrLanguage(name: 'French', code2: 'fr', code3: 'fre', enabled: true),
  BazarrLanguage(name: 'German', code2: 'de', code3: 'ger', enabled: true),
  BazarrLanguage(name: 'Italian', code2: 'it', code3: 'ita'),
];

BazarrEpisode episode(
  int id,
  int season,
  int number, {
  List<BazarrSubtitle> subtitles = const <BazarrSubtitle>[],
  List<BazarrSubtitle> missing = const <BazarrSubtitle>[],
}) =>
    BazarrEpisode(
      sonarrEpisodeId: id,
      sonarrSeriesId: 9,
      title: 'Episode $number',
      season: season,
      episode: number,
      subtitles: subtitles,
      missingSubtitles: missing,
    );

const BazarrSubtitle englishFile = BazarrSubtitle(
  name: 'English',
  code2: 'en',
  code3: 'eng',
  path: '/tv/Show/S01E01.en.srt',
);

const BazarrSubtitle englishMissing =
    BazarrSubtitle(name: 'English', code2: 'en', code3: 'eng');

/// Season 1 complete but for episode 2; season 2 with gaps in 1 and 3.
final List<BazarrEpisode> episodesFixture = <BazarrEpisode>[
  episode(101, 1, 1, subtitles: <BazarrSubtitle>[englishFile]),
  episode(102, 1, 2, missing: <BazarrSubtitle>[englishMissing]),
  episode(201, 2, 1, missing: <BazarrSubtitle>[englishMissing]),
  episode(202, 2, 2, subtitles: <BazarrSubtitle>[englishFile]),
  episode(203, 2, 3, missing: <BazarrSubtitle>[englishMissing]),
];

const BazarrSeries seriesFixture = BazarrSeries(
  sonarrSeriesId: 9,
  title: 'Show',
  profileId: 2,
);

const List<BazarrLanguageProfile> seriesProfiles = <BazarrLanguageProfile>[
  BazarrLanguageProfile(
    profileId: 2,
    name: 'English',
    items: <BazarrProfileItem>[BazarrProfileItem(id: 1, language: 'en')],
  ),
];

/// A [BazarrApi] that records actions; each answers [answer] (immediately
/// by default; a never-completing future keeps a row busy).
class FakeSubtitlesApi extends BazarrApi {
  FakeSubtitlesApi() : super(Dio());

  final List<String> calls = <String>[];
  Future<void> Function() answer = () async {};
  void Function() onGetMovie = () {};

  @override
  Future<BazarrMovie?> getMovie(int radarrId) async {
    onGetMovie();
    return movieFixture;
  }

  Future<void> _record(String call) {
    calls.add(call);
    return answer();
  }

  @override
  Future<List<int>?> getActiveJobIds() async => <int>[];

  @override
  Future<void> searchLanguage(
    SubtitleTarget target,
    LanguageChoice language,
  ) =>
      _record('search ${target.key} ${language.code2}');

  @override
  Future<void> searchMissingMovie(int radarrId) =>
      _record('search-missing m$radarrId');

  @override
  Future<void> searchMissingSeries(int seriesId) =>
      _record('search-missing s$seriesId');

  @override
  Future<void> deleteSubtitle(SubtitleTarget target, BazarrSubtitle sub) =>
      _record('delete ${target.key} ${sub.path}');

  @override
  Future<void> runSubtitleTool(
    SubtitleTarget target,
    BazarrSubtitle subtitle,
    SubtitleToolAction action,
  ) =>
      _record('tool ${target.key} ${action.action}');

  @override
  Future<void> uploadSubtitle(
    SubtitleTarget target,
    LanguageChoice language,
    MultipartFile file,
  ) =>
      _record('upload ${target.key} ${language.code2} ${file.filename}');

  @override
  Future<void> setLanguageProfile({
    int? radarrId,
    int? seriesId,
    int? profileId,
  }) =>
      _record('profile ${radarrId ?? seriesId} $profileId');
}

/// Overrides for a profile with [bazarr] serving [radarr] and [sonarr].
List<Override> subtitleOverrides({
  required FakeSubtitlesApi api,
  required FakeScheduler scheduler,
  bool linked = true,
  bool overrideItems = true,
  String version = '1.6.2',
  FutureOr<BazarrMovie?> Function()? movie,
  FutureOr<BazarrSeries?> Function()? series,
  FutureOr<List<BazarrEpisode>> Function()? episodes,
  FutureOr<List<BazarrLanguageProfile>> Function()? profiles,
}) =>
    <Override>[
      activeInstancesProvider.overrideWithValue(
        const <Instance>[bazarr, radarr, sonarr],
      ),
      bazarrForArrProvider.overrideWith(
        (Ref ref, Instance arr) => linked ? bazarr : null,
      ),
      bazarrApiProvider.overrideWith((Ref ref, Instance _) async => api),
      bazarrSystemStatusProvider.overrideWith(
        (Ref ref, Instance _) async =>
            BazarrSystemStatus(bazarrVersion: version),
      ),
      bazarrJobWatchConfigProvider.overrideWithValue(
        JobWatchConfig(
          schedule: scheduler.schedule,
          now: () => scheduler.now,
        ),
      ),
      bazarrProfilesProvider.overrideWith(
        (Ref ref, Instance _) async => (profiles ?? () => profilesFixture)(),
      ),
      bazarrLanguagesProvider.overrideWith(
        (Ref ref, Instance _) async => languagesFixture,
      ),
      if (overrideItems) ...<Override>[
        bazarrMovieItemProvider.overrideWith(
          (Ref ref, BazarrItemKey _) async => (movie ?? () => movieFixture)(),
        ),
        bazarrSeriesItemProvider.overrideWith(
          (Ref ref, BazarrItemKey _) async => (series ?? () => seriesFixture)(),
        ),
        bazarrEpisodesProvider.overrideWith(
          (Ref ref, BazarrEpisodesArgs _) async =>
              (episodes ?? () => episodesFixture)(),
        ),
      ],
    ];

/// Pumps [child] in a scrolling page under [overrides].
Future<void> pumpPage(
  WidgetTester tester,
  Widget child, {
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: (int _, Object __) => null,
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          body: ListView(padding: Insets.page, children: <Widget>[child]),
        ),
      ),
    ),
  );
}

/// Lets sheets and dialogs animate away without waiting for busy spinners
/// (which spin until Bazarr's job queue drains).
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// A future that never completes.
Future<T> never<T>() => Completer<T>().future;
