# Bazarr subtitles in Radarr and Sonarr: porting plan

> Status: step 1 (linking and foundation) built on `feat/bazarr-links`,
> step 2 (subtitles on the Radarr and Sonarr pages) on
> `feat/bazarr-arr-subtitles` (2026-10-12); step 3 follows. Source of the design: the
> Dashboarr work tracked in RenzoBeux/Dashboarr#478 (PRs #468, #479-#483),
> integrated on `v3DJG6GL/Dashboarr:integration/bazarr-subtitles` (d7d880e).
> This document keeps Dashboarr's decisions and states where Atrium has to
> differ. Mockups: the "Atrium × Bazarr" design canvas.

## Scope, in shipping order

| Step | Dashboarr PR | What lands in Atrium |
|---|---|---|
| 0 | #468, #479 | Bazarr API fixes (204 with a JSON content type, per-language episode search), the searching state with an m:ss timer |
| 1 | #480 | Bazarr links to one Radarr and one Sonarr (detected, set by hand, or off); shared subtitle widgets |
| 2 | #481 | Subtitles card on the movie page; coverage card, episode language lines, season gap badges and the episode subtitles sheet on the series page; manual search, upload, timing, translate, clean-up, delete, language profile |
| 3 | #482 | Bazarr tab becomes Library (Movies/Series, coverage bars, All/Missing/Complete/No profile, list/poster) and a paged History with a detail sheet; Missing replaces Wanted |
| 4 | #483 | Library search matcher (accents, sort title, trailing year) shared by Radarr, Sonarr and Bazarr |

## Architecture

Service packages never import each other (CONTRIBUTING.md). The pages that
show subtitles belong to `service_radarr` and `service_sonarr`, the data and
actions to `service_bazarr`. A new core package carries what both sides
share:

- `packages/core_subtitles` (new, depends on core_models, core_ui, riverpod)
  - `language_codes.dart`: the Dashboarr language table (code2, code3 B/T,
    names, aliases, Bazarr pseudo-codes `pb`, `zt`, `ea`), `normalizeLanguage`,
    `baseLanguageCode`, `parseLanguageList`.
  - `subtitle_view_models.dart`: `SubtitleChip`, `AudioTag`,
    `SubtitleRowState { present, embedded, missing }`, `CoverageCell`.
  - Widgets: `SubtitleTrackChip`, `AudioPill`, `OverflowTag`,
    `LanguageLines` (audio left, subtitles right, "+N" when they don't fit),
    `SeasonGapBadge`.
  - `SubtitlesBridge`, an abstract class with a default no-op provider:
    `movieSection(Instance radarr, RadarrMovieRef)`,
    `seriesCoverage(Instance sonarr, int seriesId)`,
    `episodeLanguages(Instance sonarr, int seriesId)` (a provider of
    per-episode chips), `openEpisodeSubtitles(...)`, `searchMissing(...)`.
- `service_bazarr` implements the bridge with its own API, providers and
  sheets.
- `app/lib/src/bootstrap.dart` overrides the bridge provider with the Bazarr
  implementation, which is the same composition pattern Activity and the
  dashboard already use.
- Radarr and Sonarr depend on `core_subtitles` only, and render nothing when
  the bridge says no Bazarr serves the instance.

## 1. Linking

**Model.** Add to `Instance` a generic
`@Default(<String, String>{}) Map<String, String> links`, keyed by the target
kind (`"radarr"`, `"sonarr"`). It is used only on Bazarr instances.

| Stored value | Meaning |
|---|---|
| key absent | automatic: use the detected instance |
| an instance id | set by you; wins over detection |
| `"none"` | off; no detection, no fallback |

Effective state per kind: `off`, `manual` (or `stale` when the id no longer
exists), `detected`, `none`.

**Detection.** `GET api/system/settings`, read only:

- `general.use_radarr` / `general.use_sonarr`, which must be strictly `true`
- `radarr.apikey`, `radarr.ip`, `radarr.port` (and the same for `sonarr.*`)

The algorithm:

1. Keep candidates whose API key equals Bazarr's (trimmed, case-sensitive).
2. If there is more than one, narrow by port (the explicit port of the local
   or external URL).
3. Then narrow by host (scheme, path, userinfo and port stripped,
   lowercased).
4. Otherwise take the first in instance order.

The settings response carries every provider password. Parse it inside one
function that returns only `{radarr: {instanceId, address}, sonarr: …}`, keep
the result in memory, and never log the response body (check the Dio log
interceptor).

**When detection runs.** It is one provider per Bazarr, keyed by
`(bazarrId, fingerprint)`. The fingerprint is the Radarr and Sonarr ids, each
with `:nokey` appended when the instance has no key; keys never go into the
provider argument.

- Saving a Bazarr's credentials invalidates detection.
- "Detect again" refreshes the result and never changes a stored choice.
- Pull-to-refresh on the Bazarr tab does not re-detect.

**Picking by hand.**

- Picking the detected instance stores nothing (it stays automatic), unless
  another Bazarr claims it.
- Picking any other instance stores its id and clears the same manual claim
  on every other Bazarr, so there is only ever one owner.
- "None" stores `"none"`.

**Which Bazarr serves a Radarr or Sonarr.** A manual claim wins over a
detected one; between equals, the first in instance order. If none claims
it, show no subtitle UI.

**Which arr a Bazarr's ids belong to** (used for posters and "Open movie"):

- the linked instance;
- if the link is off, none;
- otherwise only when exactly one Radarr or Sonarr exists.

Never fall back to the active instance, because ids are per instance.

**Atrium-specific changes:**

- `ProfileRepository.importProfile` gives every instance a new id. Remap
  `links` through the old-to-new id map. Leave `"none"` as it is, and drop
  links whose target didn't come along.
- On instance delete, remove links pointing at it. Dashboarr leaves them
  stale.
- Atrium has no per-instance enabled flag, so every instance in the active
  profile is a candidate.
- Settings UI: a "Connected apps" section on the Bazarr instance form, a
  kind-conditional section like the existing Polling one.

## 2. Bazarr API (add to `bazarr_api.dart`)

| Call | Route | Notes |
|---|---|---|
| status | GET `api/system/status` | `bazarr_version`, cached for 1 h |
| active jobs | GET `api/system/jobs?status=pending` and `=running` in parallel | null on 404/405 or an HTML 200 (old Bazarr), meaning "use timed refresh" |
| enabled languages | GET `api/system/languages` | filter `enabled` |
| movie | GET `api/movies?radarrid[]=` | literal brackets; first item or null |
| series item | GET `api/series?seriesid[]=` | first item or null |
| episodes | GET `api/episodes?seriesid[]=` | |
| search one language | PATCH `api/movies/subtitles`, `api/episodes/subtitles` | query `radarrid` or `seriesid`+`episodeid`, `language`, `forced`, `hi` as "True"/"False" |
| search missing | PATCH `api/movies` or `api/series` | JSON `{radarrid or seriesid, action: "search-missing"}` |
| search whole library | PATCH `api/movies` or `api/series` | JSON `{action: "search-wanted"}`, confirm first |
| upload | POST `api/{movies,episodes}/subtitles` | multipart, `forced`/`hi` lowercase "true"/"false" |
| delete | DELETE `api/{movies,episodes}/subtitles` | query; `path` exactly as Bazarr reported it |
| manual search | GET `api/providers/{movies,episodes}` | 180 s, `CancelToken`, no retry, results discarded after 60 s |
| manual download | POST `api/providers/{movies,episodes}` | JSON body (the token is several KB); echo the result's own flag strings; `original_format` defaults to "False" |
| tools | PATCH `api/subtitles` | `action`, `language`, `type`, `id` (episode id or radarr id), `forced`/`hi` "True"/"False", `path` for a file or `subtitles_id` for an embedded track |
| language profile | POST `api/movies` or `api/series` | query `profileid`, `""` for none (`"none"` answers 404) |
| blacklist | POST `api/{movies,episodes}/blacklist` | query `provider`, `subs_id`, `language`, `subtitles_path`; Bazarr deletes, blocks and searches again |
| history | GET `api/{movies,episodes}/history` | add `start`; page size 50 |

Request rules:

- A 204 or 205 response is an empty success even when labelled JSON; check
  that Dio's transformer doesn't throw on it.
- Action timeouts are 90 s, because before 1.5.6 the request blocks until
  the work is done.
- Season searches go out at most 4 at a time, and fail only when every one
  failed.

**Version gates.**

| Feature | Minimum Bazarr |
|---|---|
| job queue | 1.5.6 |
| extract an embedded track | 1.6.1 |
| translate an embedded track | 1.6.2 |

- An unknown version opens no gate.
- Tool rows show "Checking Bazarr version…", "Couldn't read Bazarr's version"
  or "Needs Bazarr X or later".
- Embedded tracks without an id show "Bazarr hasn't indexed this track yet".
- Version comparison: a pre-release equals its release, and missing parts
  count as 0.

## 3. Watching Bazarr's job queue

Bazarr never says which job an action started, so watch the whole queue. Use
one keepAlive notifier per Bazarr instance, so it outlives the screen that
started it.

- **`track(providers, maxDuration)`:**
  - refresh at once;
  - merge the providers into the watched set;
  - extend the deadline (never shorten it);
  - poll every 2 s.
- **On each poll:**
  - a job that left the queue triggers a midway refresh;
  - two empty polls in a row, or reaching the deadline, finish the watch with
    one final refresh;
  - a thrown poll is ignored.
- **Old Bazarr** (null queue): refresh at 3 s, 10 s and 30 s instead.
- **Durations:** the default deadline is 2 min; "Search all missing" uses
  30 min.
- **Riverpod:**
  - A midway refresh must not restart a provider that is already loading;
    skip any whose `isLoading`/`isRefreshing` is set.
  - The final refresh invalidates everything.
  - Expose `jobsActive` for busy rows.
- **Busy rows:** a row is busy from the tap until the queue drains or its
  request fails, counted per request. Reset everything when the instance
  changes. Nothing is shown optimistically except busy rows and the
  "blacklisted" mark.

## 4. Subtitle model (pure Dart, port the tests)

- **Rows** (`buildSubtitleRows`):
  - one per subtitle and one per missing language;
  - `path` set means present, `path` null means embedded;
  - order: missing, then present, then embedded, each by language name;
  - stable keys `code|fh|path`, or `track<id>` with `#n` for id-less tracks.
- **Chips:**
  - one per code + forced + HI combination;
  - the best state wins (present > embedded > missing);
  - coverage = chips that are not missing ÷ all chips.
- **Audio:**
  - the arr file's `mediaInfo.audioLanguages` first, Bazarr's
    `audio_language` when the file's list is empty or `und`;
  - original language: an exact match first, then the base code (pb→pt,
    zt→zh, ea→es, nb/nn→no).
- **Series coverage grid:**
  - columns are the profile's items (or every language seen when there is no
    profile);
  - cells are missing, present, embedded or unwanted;
  - a plain column accepts an HI subtitle, an HI column accepts only HI;
  - seasons newest first.
- **Library classification:**
  - movie: no profile, then missing, then complete;
  - series: no profile, then missing (before checking files), then complete,
    otherwise "no files" (only counted under All).
- **Movie language coverage:**
  - the wanted languages follow the profile's audio rules
    (`audio_exclude`, `audio_only_include`) against Bazarr's audio list;
  - have = has a subtitle and is not listed as missing;
  - missing = listed as missing;
  - a movie can be neither once the cutoff is met.
- **Upload file names:**
  - read only the trailing run of tags;
  - at most one language;
  - forced tags: `forced`, `foreign`;
  - HI tags: `hi`, `sdh`, `cc`;
  - a lone `hi` means Hindi.
- **Tools:**
  - shift sends `shift_offset(h=,m=,s=,ms=)` with every component negated
    for a negative shift;
  - frame rate sends `change_FPS(from=,to=)`;
  - timing and clean-up only for `.srt` files;
  - clean-up mods are `remove_HI`, `remove_tags`, `emoji`, `OCR_fixes`,
    `common`, `fix_uppercase` and `reverse_rtl`.
- **History:**
  - two streams merged and deduplicated on kind, time, id, action, language,
    flags, `subs_id` and path;
  - hold back entries older than the oldest loaded entry of a stream that has
    more;
  - day groups: Today, Yesterday, a date, Earlier;
  - parse ISO, `M/D/Y h:mm[:ss] [AM|PM]` and `D.M.Y` timestamps;
  - action codes:

    | Code | Label |
    |---|---|
    | 0 | deleted |
    | 1 | downloaded |
    | 2 | downloaded manually |
    | 3 | upgraded |
    | 4 | uploaded |
    | 5 | synced |
    | 6 | translated |
    | 7 | extracted |

    The current Atrium model comment is wrong about these.

## 5. UI map (Dashboarr → Atrium, Material 3)

| Dashboarr | Atrium |
|---|---|
| Subtitle chip: primary fill (file), outlined neutral (embedded), dashed orange (missing); corner badge ear (HI) or "F" (forced) | `SubtitleTrackChip`: `primary`/`onPrimary`; `surfaceContainerHighest` + `outline`; dashed amber via `CustomPainter`; badge = `inverseSurface` dot ringed in the surface colour |
| Audio pill with house badge for the original | `AudioPill`: stadium outline, `Icons.home_rounded` badge |
| CollapsibleCard "Subtitles" with the Bazarr name on the right | Section header + tonal card with `AnimatedSize`; header shows the chips and "have/total" |
| Footer Search / Manual / Upload, profile row | Three `FilledButton.tonal` + a `ListTile` with the profile name and chevron |
| Row menu (Sync, Adjust timing…, Translate…, Clean up…, Delete) | Modal bottom sheet of `ListTile`s, delete in `error` colour |
| Timing sheet: Shift / Frame rate | `SegmentedButton`, nudge `IconButton.filledTonal`, step `ChoiceChip`s, footer `FilledButton` "Shift by +1.5 s" |
| Upload sheet | `file_picker` (already a dependency), language `ChoiceChip` row, mutually exclusive `SwitchListTile`s |
| SearchingIndicator rings + m:ss | Atrium's `ExpressiveProgressIndicator` (M3 Expressive loading indicator) + the m:ss timer + "Restart search" after 30 s |
| Manual result card + detail sheet | Card with release name, chip, score badge (≥90 tertiary, ≥70 neutral, else amber), provider, ✓/✗ counts; sheet with a stat grid, matched / didn't match chips, link, Download |
| Coverage grid | Season `SegmentedButton` (or `ChoiceChip`s past 3), a fixed language column plus a horizontally scrolling grid of 18 px cells that open the episode sheet |
| Episode row LanguageLines | Under Atrium's `_EpisodeRow` meta line; tap opens "S2E5 subtitles" |
| Episode subtitles sheet with previous/next gap buttons | Modal sheet; the existing episode sheet gains a "Subtitles" button |
| Season gap badge + "Search missing subtitles" in menus | `_SeasonCard` header badge; a season-row action; series overflow item |
| Bazarr tab Library/History | Tabs become Library, History, Blacklist, System, Settings; Library has a Movies/Series `SegmentedButton`, coverage bars, `FilterChip`s, list/poster toggle (Hive, per kind, default list) |

Copy follows Dashboarr word for word where it exists (see the PR specs).
Atrium's own conventions win on navigation (`pushScreen`, root-navigator
sheets) and tokens (`Insets`, `Radii`).

## 6. Atrium gaps this also closes

- Wanted rows can't be tapped (the ids are dropped). This is resolved by the
  Missing filter.
- History has no paging, handles only codes 0-3, and only parses slash dates.
- `BazarrMovie` lacks `audio_language`, and `BazarrProfileItem` lacks
  `audio_only_include`.
- Bazarr screens push with a raw `Navigator`; switch them to `pushScreen`.
- `site/src/data/services.js` promises syncing and audio profiles. That
  becomes true after step 2.

## Decisions (2026-10-11)

1. Library rows open the Radarr or Sonarr page (on its Subtitles section,
   or that episode's subtitles sheet from History) when the Bazarr has a
   linked instance for that kind. Without one, they open Atrium's own Bazarr
   movie or series detail screen, as today. The app layer composes this:
   `service_bazarr` asks a callback, which `app/` fills with the Radarr and
   Sonarr screens.
2. Wiring: a new `core_subtitles` package plus a bridge (approved).
3. Upload uses `file_picker`, which `app`, `service_qbittorrent`,
   `service_rtorrent` and `service_nzbget` already depend on, so it is
   already in the F-Droid build.
