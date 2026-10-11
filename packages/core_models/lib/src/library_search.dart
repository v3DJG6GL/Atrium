// Client-side text matching over the *arr libraries that are already loaded,
// ported from Dashboarr's lib/library-search.ts. Radarr movies, Sonarr series
// and Bazarr's lists all reduce to [LibraryMatchFields] through an adapter.
//
// Everything here is pure and generic over the item type.

/// The fields of a library item the matcher reads.
class LibraryMatchFields {
  const LibraryMatchFields({required this.title, this.sortTitle, this.year});

  /// For Radarr, Sonarr and Bazarr items, which report year 0 for titles with
  /// no date yet: that year is left out so a trailing year in the query
  /// doesn't hide them.
  const LibraryMatchFields.arr({
    required this.title,
    this.sortTitle,
    int? year,
  }) : year = year != null && year > 0 ? year : null;

  final String title;

  /// The *arr sort title, which already drops leading articles. Matching it
  /// too is what makes "office" hit "The Office" without a stopword list.
  final String? sortTitle;

  final int? year;
}

/// One row of a merged search list: a library item or a lookup result.
sealed class MergedSearchRow<L, K> {
  const MergedSearchRow();
}

/// A library item promoted to the top of a merged search list.
final class LibrarySearchRow<L, K> extends MergedSearchRow<L, K> {
  const LibrarySearchRow(this.item);

  final L item;
}

/// A lookup result in a merged search list.
final class LookupSearchRow<L, K> extends MergedSearchRow<L, K> {
  const LookupSearchRow(this.item);

  final K item;
}

/// Default cap on promoted library rows, so a broad query can't bury the
/// lookup.
const int defaultLibraryMatchLimit = 20;

const int _scoreExact = 100;
const int _scorePrefix = 80;
const int _scoreWordBoundary = 60;
const int _scoreSubstring = 40;
const int _scoreTokens = 20;
const int _yearAdjust = 10;

// Punctuation is listed explicitly rather than as "everything that isn't
// [a-z0-9]" so non-latin titles (CJK, Cyrillic, Greek) survive normalization
// instead of being blanked out.
final RegExp _punctuation =
    RegExp(r'''[._\-–—:;,!?'"“”‘’`´()[\]{}<>/\\|&+*#@~^$%=]+''');
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _trailingYear = RegExp(r'^(.*\S)\s+(\d{4})$');

// Canonical decompositions (NFD minus the combining marks) of the Latin-1
// Supplement, Latin Extended-A/B, Greek and Coptic, Cyrillic, Latin Extended
// Additional and Greek Extended blocks: _foldFrom[i] folds to _foldTo[i].
// Generated from Python's unicodedata; Dart has no String.normalize.
const String _foldFrom = 'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéê'
    'ëìíîïñòóôõöùúûüýÿĀāĂăĄąĆćĈĉĊċČčĎďĒēĔ'
    'ĕĖėĘęĚěĜĝĞğĠġĢģĤĥĨĩĪīĬĭĮįİĴĵĶķĹĺĻļĽľ'
    'ŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŨũŪūŬŭ'
    'ŮůŰűŲųŴŵŶŷŸŹźŻżŽžƠơƯưǍǎǏǐǑǒǓǔǕǖǗǘǙǚǛ'
    'ǜǞǟǠǡǢǣǦǧǨǩǪǫǬǭǮǯǰǴǵǸǹǺǻǼǽǾǿȀȁȂȃȄȅȆȇ'
    'ȈȉȊȋȌȍȎȏȐȑȒȓȔȕȖȗȘșȚțȞȟȦȧȨȩȪȫȬȭȮȯȰȱȲȳ'
    'ʹ;΅Ά·ΈΉΊΌΎΏΐΪΫάέήίΰϊϋόύώϓϔЀЁЃЇЌЍЎЙйѐ'
    'ёѓїќѝўѶѷӁӂӐӑӒӓӖӗӚӛӜӝӞӟӢӣӤӥӦӧӪӫӬӭӮӯӰӱ'
    'ӲӳӴӵӸӹḀḁḂḃḄḅḆḇḈḉḊḋḌḍḎḏḐḑḒḓḔḕḖḗḘḙḚḛḜḝ'
    'ḞḟḠḡḢḣḤḥḦḧḨḩḪḫḬḭḮḯḰḱḲḳḴḵḶḷḸḹḺḻḼḽḾḿṀṁ'
    'ṂṃṄṅṆṇṈṉṊṋṌṍṎṏṐṑṒṓṔṕṖṗṘṙṚṛṜṝṞṟṠṡṢṣṤṥ'
    'ṦṧṨṩṪṫṬṭṮṯṰṱṲṳṴṵṶṷṸṹṺṻṼṽṾṿẀẁẂẃẄẅẆẇẈẉ'
    'ẊẋẌẍẎẏẐẑẒẓẔẕẖẗẘẙẛẠạẢảẤấẦầẨẩẪẫẬậẮắẰằẲ'
    'ẳẴẵẶặẸẹẺẻẼẽẾếỀềỂểỄễỆệỈỉỊịỌọỎỏỐốỒồỔổỖ'
    'ỗỘộỚớỜờỞởỠỡỢợỤụỦủỨứỪừỬửỮữỰựỲỳỴỵỶỷỸỹἀ'
    'ἁἂἃἄἅἆἇἈἉἊἋἌἍἎἏἐἑἒἓἔἕἘἙἚἛἜἝἠἡἢἣἤἥἦἧἨ'
    'ἩἪἫἬἭἮἯἰἱἲἳἴἵἶἷἸἹἺἻἼἽἾἿὀὁὂὃὄὅὈὉὊὋὌὍὐ'
    'ὑὒὓὔὕὖὗὙὛὝὟὠὡὢὣὤὥὦὧὨὩὪὫὬὭὮὯὰάὲέὴήὶίὸ'
    'όὺύὼώᾀᾁᾂᾃᾄᾅᾆᾇᾈᾉᾊᾋᾌᾍᾎᾏᾐᾑᾒᾓᾔᾕᾖᾗᾘᾙᾚᾛᾜᾝᾞ'
    'ᾟᾠᾡᾢᾣᾤᾥᾦᾧᾨᾩᾪᾫᾬᾭᾮᾯᾰᾱᾲᾳᾴᾶᾷᾸᾹᾺΆᾼι῁ῂῃῄῆῇ'
    'ῈΈῊΉῌ῍῎῏ῐῑῒΐῖῗῘῙῚΊ῝῞῟ῠῡῢΰῤῥῦῧῨῩῪΎῬ῭΅'
    '`ῲῳῴῶῷῸΌῺΏῼ´';

const String _foldTo = 'AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceee'
    'eiiiinooooouuuuyyAaAaAaCcCcCcCcDdEeE'
    'eEeEeEeGgGgGgGgHhIiIiIiIiIJjKkLlLlLl'
    'NnNnNnOoOoOoRrRrRrSsSsSsSsTtTtUuUuUu'
    'UuUuUuWwYyYZzZzZzOoUuAaIiOoUuUuUuUuU'
    'uAaAaÆæGgKkOoOoƷʒjGgNnAaÆæØøAaAaEeEe'
    'IiIiOoOoRrRrUuUuSsTtHhAaEeOoOoOoOoYy'
    'ʹ;¨Α·ΕΗΙΟΥΩιΙΥαεηιυιυουωϒϒЕЕГІКИУИие'
    'егікиуѴѵЖжАаАаЕеӘәЖжЗзИиИиОоӨөЭэУуУу'
    'УуЧчЫыAaBbBbBbCcDdDdDdDdDdEeEeEeEeEe'
    'FfGgHhHhHhHhHhIiIiKkKkKkLlLlLlLlMmMm'
    'MmNnNnNnNnOoOoOoOoPpPpRrRrRrRrSsSsSs'
    'SsSsTtTtTtTtUuUuUuUuUuVvVvWwWwWwWwWw'
    'XxXxYyZzZzZzhtwyſAaAaAaAaAaAaAaAaAaA'
    'aAaAaEeEeEeEeEeEeEeEeIiIiOoOoOoOoOoO'
    'oOoOoOoOoOoOoUuUuUuUuUuUuUuYyYyYyYyα'
    'αααααααΑΑΑΑΑΑΑΑεεεεεεΕΕΕΕΕΕηηηηηηηηΗ'
    'ΗΗΗΗΗΗΗιιιιιιιιΙΙΙΙΙΙΙΙοοοοοοΟΟΟΟΟΟυ'
    'υυυυυυυΥΥΥΥωωωωωωωωΩΩΩΩΩΩΩΩααεεηηιιο'
    'ουυωωααααααααΑΑΑΑΑΑΑΑηηηηηηηηΗΗΗΗΗΗΗ'
    'ΗωωωωωωωωΩΩΩΩΩΩΩΩαααααααΑΑΑΑΑι¨ηηηηη'
    'ΕΕΗΗΗ᾿᾿᾿ιιιιιιΙΙΙΙ῾῾῾υυυυρρυυΥΥΥΥΡ¨¨'
    '`ωωωωωΟΟΩΩΩ´';

final Map<int, int> _fold = _buildFold();

Map<int, int> _buildFold() {
  assert(_foldFrom.length == _foldTo.length, 'fold table out of step');
  return <int, int>{
    for (int i = 0; i < _foldFrom.length; i++)
      _foldFrom.codeUnitAt(i): _foldTo.codeUnitAt(i),
  };
}

bool _isCombiningMark(int rune) => rune >= 0x0300 && rune <= 0x036F;

/// Fold a title or query down to a comparable form: diacritics stripped,
/// lowercased, punctuation collapsed to single spaces. "Amélie" and "amelie"
/// both become "amelie"; "Marvel's Daredevil" becomes "marvel s daredevil".
String normalizeSearchText(String? input) {
  if (input == null || input.isEmpty) return '';
  final StringBuffer folded = StringBuffer();
  for (final int rune in input.runes) {
    if (_isCombiningMark(rune)) continue;
    folded.writeCharCode(_fold[rune] ?? rune);
  }
  return folded
      .toString()
      .toLowerCase()
      .replaceAll(_punctuation, ' ')
      .replaceAll(_whitespace, ' ')
      .trim();
}

/// A query split into the text to match and an optional trailing year.
typedef LibraryQuery = ({String text, int? year});

/// Split a trailing 4-digit year off the query ("inception 2010"), leaving
/// the rest as the text to match. A bare year stays text: "2012" should still
/// find the movie called 2012.
LibraryQuery parseLibraryQuery(String query) {
  final String text = normalizeSearchText(query);
  final RegExpMatch? match = _trailingYear.firstMatch(text);
  if (match == null) return (text: text, year: null);
  final int year = int.parse(match.group(2)!);
  if (year < 1870 || year > 2200) return (text: text, year: null);
  return (text: match.group(1)!, year: year);
}

List<String> _tokens(String text) =>
    text.split(' ').where((String t) => t.isNotEmpty).toList();

int _scoreHaystack(String haystack, String text, List<String> tokens) {
  if (haystack.isEmpty) return 0;
  if (haystack == text) return _scoreExact;
  if (haystack.startsWith(text)) return _scorePrefix;
  final int idx = haystack.indexOf(text);
  if (idx > 0) {
    // A match that begins a word ("the dark KNIGHT rises") reads as far more
    // relevant than one buried mid-word ("mooNKNIGHT").
    return haystack[idx - 1] == ' ' ? _scoreWordBoundary : _scoreSubstring;
  }
  // Last resort: every word of the query is somewhere in the title, out of
  // order.
  return tokens.length > 1 && tokens.every(haystack.contains)
      ? _scoreTokens
      : 0;
}

int _scoreEntry<T>(
  LibraryIndexEntry<T> entry,
  String text,
  List<String> tokens,
) {
  final int title = _scoreHaystack(entry.title, text, tokens);
  final int sortTitle = _scoreHaystack(entry.sortTitle, text, tokens);
  return title > sortTitle ? title : sortTitle;
}

/// One library item with its haystacks pre-normalized.
class LibraryIndexEntry<T> {
  const LibraryIndexEntry({
    required this.item,
    required this.fields,
    required this.title,
    required this.sortTitle,
  });

  final T item;
  final LibraryMatchFields fields;

  /// [LibraryMatchFields.title], normalized.
  final String title;

  /// [LibraryMatchFields.sortTitle], normalized; empty when there is none.
  final String sortTitle;
}

/// A whole library, pre-normalized so a keystroke doesn't re-fold a few
/// thousand titles. Build it once per library list.
class LibraryIndex<T> {
  const LibraryIndex(this.entries);

  const LibraryIndex.empty() : entries = const <Never>[];

  /// In the order of the list the index was built from.
  final List<LibraryIndexEntry<T>> entries;

  bool get isEmpty => entries.isEmpty;

  int get length => entries.length;
}

/// Pre-normalize a whole library. A null list (nothing loaded yet) gives an
/// empty index.
LibraryIndex<T> buildLibraryIndex<T>(
  Iterable<T>? items,
  LibraryMatchFields Function(T item) toFields,
) {
  if (items == null) return LibraryIndex<T>.empty();
  return LibraryIndex<T>(
    List<LibraryIndexEntry<T>>.unmodifiable(
      items.map((T item) {
        final LibraryMatchFields fields = toFields(item);
        final String? sortTitle = fields.sortTitle;
        return LibraryIndexEntry<T>(
          item: item,
          fields: fields,
          title: normalizeSearchText(fields.title),
          sortTitle: sortTitle == null || sortTitle.isEmpty
              ? ''
              : normalizeSearchText(sortTitle),
        );
      }),
    ),
  );
}

/// Rank a pre-built index against a query, best match first. Returns at most
/// [limit] items; an empty or unmatched query returns nothing.
List<T> matchLibraryIndex<T>(
  LibraryIndex<T> index,
  String query, {
  int limit = defaultLibraryMatchLimit,
}) {
  if (index.isEmpty || limit <= 0) return <T>[];
  final LibraryQuery parsed = parseLibraryQuery(query);
  final String text = parsed.text;
  final int? year = parsed.year;
  if (text.isEmpty) return <T>[];
  final List<String> tokens = _tokens(text);

  final List<(LibraryIndexEntry<T>, int, int)> scored =
      <(LibraryIndexEntry<T>, int, int)>[];
  for (int i = 0; i < index.entries.length; i++) {
    final LibraryIndexEntry<T> entry = index.entries[i];
    int score = _scoreEntry(entry, text, tokens);
    if (score == 0) continue;
    final int? itemYear = entry.fields.year;
    if (year != null && itemYear != null) {
      score += itemYear == year ? _yearAdjust : -_yearAdjust;
    }
    scored.add((entry, score, i));
  }

  scored.sort((
    (LibraryIndexEntry<T>, int, int) a,
    (LibraryIndexEntry<T>, int, int) b,
  ) {
    final (LibraryIndexEntry<T> entryA, int scoreA, int orderA) = a;
    final (LibraryIndexEntry<T> entryB, int scoreB, int orderB) = b;
    if (scoreA != scoreB) return scoreB - scoreA;
    // Shorter title first: "Alien" should outrank "Alien vs. Predator".
    final int lenA = entryA.title.length;
    final int lenB = entryB.title.length;
    if (lenA != lenB) return lenA - lenB;
    final int yearA = entryA.fields.year ?? 0;
    final int yearB = entryB.fields.year ?? 0;
    if (yearA != yearB) return yearB - yearA;
    final int byTitle = entryA.fields.title
        .toLowerCase()
        .compareTo(entryB.fields.title.toLowerCase());
    if (byTitle != 0) return byTitle;
    // Dart's sort isn't stable; keep the library's order for full ties.
    return orderA - orderB;
  });

  return <T>[
    for (final (LibraryIndexEntry<T>, int, int) row in scored.take(limit))
      row.$1.item,
  ];
}

/// Narrow a list: the items matching the query, in the index's own order (the
/// caller's sort), with no limit. An empty query keeps everything.
///
/// Uses the same matching as [matchLibraryIndex]: accents, punctuation and
/// word order don't matter, and a trailing year ("dune 2021") must match the
/// item's year when it has one. For in-list search over a library, where the
/// user's sort should stay put rather than reorder by relevance.
List<T> filterLibraryIndex<T>(LibraryIndex<T> index, String query) {
  final LibraryQuery parsed = parseLibraryQuery(query);
  final String text = parsed.text;
  final int? year = parsed.year;
  if (text.isEmpty) {
    return <T>[for (final LibraryIndexEntry<T> e in index.entries) e.item];
  }
  final List<String> tokens = _tokens(text);
  // The whole query, trailing number included: "blade runner 2049" is a
  // title, not "blade runner" from 2049.
  final String full = normalizeSearchText(query);
  final List<String> fullTokens = _tokens(full);
  final List<T> out = <T>[];
  for (final LibraryIndexEntry<T> entry in index.entries) {
    final bool matchesFull =
        year != null && _scoreEntry(entry, full, fullTokens) > 0;
    if (!matchesFull) {
      if (_scoreEntry(entry, text, tokens) == 0) continue;
      final int? itemYear = entry.fields.year;
      if (year != null && itemYear != null && itemYear != year) continue;
    }
    out.add(entry.item);
  }
  return out;
}

/// Convenience for callers that don't hold an index (and for tests).
List<T> matchLibraryItems<T>(
  Iterable<T>? items,
  String query,
  LibraryMatchFields Function(T item) toFields, {
  int limit = defaultLibraryMatchLimit,
}) =>
    matchLibraryIndex(
      buildLibraryIndex(items, toFields),
      query,
      limit: limit,
    );

/// Library matches first, then the lookup results with the promoted ones
/// removed. Dedup is against the rows actually shown, so an item cut by the
/// match limit still reaches the list through its lookup row.
List<MergedSearchRow<L, K>> mergeLibraryFirst<L, K, Id>({
  required List<L> libraryMatches,
  required List<K>? lookupResults,
  required Id Function(L item) libraryKey,
  required Id Function(K item) lookupKey,
}) {
  final Set<Id> promoted = <Id>{};
  final List<MergedSearchRow<L, K>> rows = <MergedSearchRow<L, K>>[];
  for (final L item in libraryMatches) {
    promoted.add(libraryKey(item));
    rows.add(LibrarySearchRow<L, K>(item));
  }
  for (final K item in lookupResults ?? <K>[]) {
    if (promoted.contains(lookupKey(item))) continue;
    rows.add(LookupSearchRow<L, K>(item));
  }
  return rows;
}

/// AND together the active predicates; null when none is active.
bool Function(T item)? combineFilters<T>(
  List<bool Function(T item)?> filters,
) {
  final List<bool Function(T item)> active = <bool Function(T item)>[
    for (final bool Function(T item)? f in filters)
      if (f != null) f,
  ];
  if (active.isEmpty) return null;
  if (active.length == 1) return active.single;
  return (T item) => active.every((bool Function(T item) f) => f(item));
}
