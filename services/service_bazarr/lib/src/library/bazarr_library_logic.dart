import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../models/bazarr_models.dart';

// The Bazarr library's logic: what state each movie or series is in, the
// filter chip counts, and per-language coverage. Pure.

/// Which movies or series the Library lists.
enum BazarrLibraryKind { movies, series }

/// The Library's filter chips.
enum LibraryFilter {
  all('All'),
  missing('Missing'),
  complete('Complete'),
  noProfile('No profile');

  const LibraryFilter(this.label);

  final String label;
}

/// A movie's or series' subtitle state.
///
/// [noFiles]: a series with no episode on disk has nothing to subtitle, so it
/// is neither complete nor missing. It has no chip and shows only under All.
enum LibraryItemState { missing, complete, noProfile, noFiles }

/// A movie's subtitle state. No profile wins: nothing is wanted.
LibraryItemState classifyMovie(BazarrMovie movie) {
  if (movie.profileId == null) {
    return LibraryItemState.noProfile;
  }
  return movie.missingSubtitles.isNotEmpty
      ? LibraryItemState.missing
      : LibraryItemState.complete;
}

/// A series' subtitle state. Missing before no files: an episode Bazarr can
/// search for stays listed under Missing even if the series' file count lags
/// behind.
LibraryItemState classifySeries(BazarrSeries series) {
  if (series.profileId == null) {
    return LibraryItemState.noProfile;
  }
  if (series.episodeMissingCount > 0) {
    return LibraryItemState.missing;
  }
  return series.episodeFileCount > 0
      ? LibraryItemState.complete
      : LibraryItemState.noFiles;
}

/// How many items each filter chip lists.
@immutable
class LibraryCounts {
  const LibraryCounts({
    this.all = 0,
    this.missing = 0,
    this.complete = 0,
    this.noProfile = 0,
  });

  final int all;
  final int missing;
  final int complete;
  final int noProfile;

  int of(LibraryFilter filter) => switch (filter) {
        LibraryFilter.all => all,
        LibraryFilter.missing => missing,
        LibraryFilter.complete => complete,
        LibraryFilter.noProfile => noProfile,
      };

  @override
  bool operator ==(Object other) =>
      other is LibraryCounts &&
      other.all == all &&
      other.missing == missing &&
      other.complete == complete &&
      other.noProfile == noProfile;

  @override
  int get hashCode => Object.hash(all, missing, complete, noProfile);

  @override
  String toString() => 'LibraryCounts(all: $all, missing: $missing, '
      'complete: $complete, noProfile: $noProfile)';
}

/// The chip counts of [items].
LibraryCounts filterCounts<T>(
  List<T> items,
  LibraryItemState Function(T item) classify,
) {
  int missing = 0;
  int complete = 0;
  int noProfile = 0;
  for (final T item in items) {
    switch (classify(item)) {
      case LibraryItemState.missing:
        missing++;
      case LibraryItemState.complete:
        complete++;
      case LibraryItemState.noProfile:
        noProfile++;
      case LibraryItemState.noFiles:
      // No chip of its own: counted under All only.
    }
  }
  return LibraryCounts(
    all: items.length,
    missing: missing,
    complete: complete,
    noProfile: noProfile,
  );
}

/// One language's coverage across the movie library.
@immutable
class LanguageCoverage {
  const LanguageCoverage({
    required this.code2,
    this.have = 0,
    this.missing = 0,
    this.total = 0,
  });

  final String code2;

  /// Movies whose profile wants the language and that have a subtitle in it
  /// (a file or an embedded track) that Bazarr doesn't still list as missing.
  final int have;

  /// Movies whose profile wants the language and Bazarr lists it as missing.
  final int missing;

  /// Movies whose profile wants the language, after the profile's audio
  /// rules (exclude if matching / only include if matching audio).
  final int total;

  @override
  bool operator ==(Object other) =>
      other is LanguageCoverage &&
      other.code2 == code2 &&
      other.have == have &&
      other.missing == missing &&
      other.total == total;

  @override
  int get hashCode => Object.hash(code2, have, missing, total);

  @override
  String toString() => 'LanguageCoverage($code2, have: $have, '
      'missing: $missing, total: $total)';
}

bool _missesLanguage(BazarrMovie movie, String code2) =>
    movie.missingSubtitles.any((BazarrSubtitle s) => s.code2 == code2);

// A track Bazarr doesn't accept (e.g. only a forced English subtitle when the
// profile wants regular English) leaves the language listed as missing; it
// isn't had, so "have" and "missing" never overlap.
bool _hasLanguage(BazarrMovie movie, String code2) =>
    !_missesLanguage(movie, code2) &&
    movie.subtitles.any((BazarrSubtitle s) => s.code2 == code2);

/// One language a profile asks for.
///
/// Bazarr skips a profile item "exclude if matching audio" when one of the
/// movie's audio tracks is in its language, and one "only include if
/// matching audio" when none is. A language is wanted while any of its items
/// isn't skipped.
@immutable
class ProfileLanguage {
  const ProfileLanguage({
    required this.code2,
    required this.ifAudioMatches,
    required this.ifAudioDiffers,
  });

  final String code2;

  /// Some item for the language still applies when the audio is in it.
  final bool ifAudioMatches;

  /// Some item for the language still applies when the audio isn't in it.
  final bool ifAudioDiffers;

  @override
  bool operator ==(Object other) =>
      other is ProfileLanguage &&
      other.code2 == code2 &&
      other.ifAudioMatches == ifAudioMatches &&
      other.ifAudioDiffers == ifAudioDiffers;

  @override
  int get hashCode => Object.hash(code2, ifAudioMatches, ifAudioDiffers);

  @override
  String toString() => 'ProfileLanguage($code2, '
      'ifAudioMatches: $ifAudioMatches, ifAudioDiffers: $ifAudioDiffers)';
}

/// The languages each language profile asks for, by profile id.
typedef ProfileLanguages = Map<int, List<ProfileLanguage>>;

/// The languages of every profile in [profiles], one entry per language
/// however many items name it.
ProfileLanguages profileLanguageMap(List<BazarrLanguageProfile> profiles) =>
    <int, List<ProfileLanguage>>{
      for (final BazarrLanguageProfile p in profiles)
        p.profileId: _languagesOf(p),
    };

List<ProfileLanguage> _languagesOf(BazarrLanguageProfile profile) {
  final Map<String, ({bool matches, bool differs})> langs =
      <String, ({bool matches, bool differs})>{};
  for (final BazarrProfileItem item in profile.items) {
    final ({bool matches, bool differs}) lang =
        langs[item.language] ?? (matches: false, differs: false);
    langs[item.language] = (
      matches: lang.matches || item.audioExclude != 'True',
      differs: lang.differs || item.audioOnlyInclude != 'True',
    );
  }
  return <ProfileLanguage>[
    for (final MapEntry<String, ({bool matches, bool differs})> e
        in langs.entries)
      ProfileLanguage(
        code2: e.key,
        ifAudioMatches: e.value.matches,
        ifAudioDiffers: e.value.differs,
      ),
  ];
}

/// The languages [movie]'s profile wants for it, given its audio tracks.
///
/// Bazarr's own audio languages, not Radarr's file probe the rows show: they
/// are what Bazarr applied the audio rules to when it listed missing.
List<String> wantedLanguages(
  BazarrMovie movie,
  ProfileLanguages profileLanguages,
) {
  final int? profileId = movie.profileId;
  if (profileId == null) {
    return const <String>[];
  }
  final List<BazarrLanguage> audio = movie.audioLanguage;
  return <String>[
    for (final ProfileLanguage l
        in profileLanguages[profileId] ?? const <ProfileLanguage>[])
      if (audio.any((BazarrLanguage a) => a.code2 == l.code2)
          ? l.ifAudioMatches
          : l.ifAudioDiffers)
        l.code2,
  ];
}

/// Per-language coverage across [movies]: for every language any profile
/// asks for, how many of the movies wanting it have it and how many Bazarr
/// still lists as missing it. Ordered by how many movies want it, so the
/// languages that matter most come first.
///
/// Coverage counts what is actually there, not "not missing": Bazarr empties
/// `missing_subtitles` once a profile's cutoff is met, so a movie can be
/// neither — it doesn't have the language and Bazarr won't look for it. That
/// movie lowers the share without appearing under "missing". A language the
/// profile skips for the movie's audio isn't wanted, so that movie isn't
/// counted for it at all.
///
/// Takes the same [profileLanguages] as [filterMovies], so a bar and its list
/// can't disagree.
List<LanguageCoverage> computeLanguageCoverage(
  List<BazarrMovie> movies,
  ProfileLanguages profileLanguages,
) {
  final Map<String, ({int have, int missing, int total})> totals =
      <String, ({int have, int missing, int total})>{};
  for (final BazarrMovie movie in movies) {
    for (final String code2 in wantedLanguages(movie, profileLanguages)) {
      final ({int have, int missing, int total}) entry =
          totals[code2] ?? (have: 0, missing: 0, total: 0);
      totals[code2] = (
        have: entry.have + (_hasLanguage(movie, code2) ? 1 : 0),
        missing: entry.missing + (_missesLanguage(movie, code2) ? 1 : 0),
        total: entry.total + 1,
      );
    }
  }
  final List<LanguageCoverage> out = <LanguageCoverage>[
    for (final MapEntry<String, ({int have, int missing, int total})> e
        in totals.entries)
      LanguageCoverage(
        code2: e.key,
        have: e.value.have,
        missing: e.value.missing,
        total: e.value.total,
      ),
  ];
  out.sort((LanguageCoverage a, LanguageCoverage b) {
    final int byTotal = b.total.compareTo(a.total);
    return byTotal != 0 ? byTotal : a.code2.compareTo(b.code2);
  });
  return out;
}

/// What a coverage bar's filter lists.
enum LanguageShow { missing, have }

/// A coverage bar's filter: the movies missing the language, or the movies
/// that have it. Both count the way the bar does — only movies whose profile
/// wants the language — so the list length matches the bar's number.
@immutable
class LanguageFilter {
  const LanguageFilter(this.code2, this.show);

  final String code2;
  final LanguageShow show;

  @override
  bool operator ==(Object other) =>
      other is LanguageFilter && other.code2 == code2 && other.show == show;

  @override
  int get hashCode => Object.hash(code2, show);

  @override
  String toString() => 'LanguageFilter($code2, ${show.name})';
}

/// A tap on a coverage bar cycles off → missing → have → off; another
/// language starts at missing.
LanguageFilter? nextLanguageFilter(LanguageFilter? current, String code2) {
  if (current == null || current.code2 != code2) {
    return LanguageFilter(code2, LanguageShow.missing);
  }
  return current.show == LanguageShow.missing
      ? LanguageFilter(code2, LanguageShow.have)
      : null;
}

bool _matchesLanguage(
  BazarrMovie movie,
  LanguageFilter language,
  ProfileLanguages profileLanguages,
) {
  // Only a language the profile still wants: a stale missing language
  // isn't listed.
  if (!wantedLanguages(movie, profileLanguages).contains(language.code2)) {
    return false;
  }
  return language.show == LanguageShow.missing
      ? _missesLanguage(movie, language.code2)
      : _hasLanguage(movie, language.code2);
}

/// Applies the filter chip (and an optional [language] filter from a
/// coverage bar) to [movies].
List<BazarrMovie> filterMovies(
  List<BazarrMovie> movies,
  LibraryFilter filter, {
  LanguageFilter? language,
  ProfileLanguages profileLanguages = const <int, List<ProfileLanguage>>{},
}) =>
    <BazarrMovie>[
      for (final BazarrMovie m in movies)
        if ((language == null ||
                _matchesLanguage(m, language, profileLanguages)) &&
            _passes(filter, classifyMovie(m)))
          m,
    ];

/// Applies the filter chip to [series].
List<BazarrSeries> filterSeries(
  List<BazarrSeries> series,
  LibraryFilter filter,
) =>
    filter == LibraryFilter.all
        ? List<BazarrSeries>.of(series)
        : <BazarrSeries>[
            for (final BazarrSeries s in series)
              if (_passes(filter, classifySeries(s))) s,
          ];

bool _passes(LibraryFilter filter, LibraryItemState state) =>
    switch (filter) {
      LibraryFilter.all => true,
      LibraryFilter.missing => state == LibraryItemState.missing,
      LibraryFilter.complete => state == LibraryItemState.complete,
      LibraryFilter.noProfile => state == LibraryItemState.noProfile,
    };

/// Downloaded episodes with every wanted subtitle.
int seriesSubtitledCount(BazarrSeries series) =>
    math.max(0, series.episodeFileCount - series.episodeMissingCount);

/// Share of a series' downloaded episodes with every wanted subtitle (0–1).
double seriesCoverage(BazarrSeries series) {
  if (series.episodeFileCount <= 0) {
    return 0;
  }
  return seriesSubtitledCount(series) / series.episodeFileCount;
}

/// A coverage bar's percentage: 0 only when none, 100 only when all, else
/// 1–99, so 199 of 200 doesn't read as complete nor 1 of 200 as absent.
int coveragePercent(int have, int total) {
  if (have <= 0 || total <= 0) {
    return 0;
  }
  if (have >= total) {
    return 100;
  }
  return ((have / total) * 100).round().clamp(1, 99);
}
