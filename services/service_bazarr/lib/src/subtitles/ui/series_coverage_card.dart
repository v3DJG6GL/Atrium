import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'subtitles_section.dart';

/// Per-language progress across a series: episodes that have the language
/// (a file or embedded) out of those that want it.
typedef CoverageTotal = ({CoverageLanguage language, int done, int total});

/// [CoverageTotal]s of [grid], one per language column.
List<CoverageTotal> coverageTotals(CoverageGrid grid) => <CoverageTotal>[
      for (int i = 0; i < grid.languages.length; i++) _totalOf(grid, i),
    ];

CoverageTotal _totalOf(CoverageGrid grid, int column) {
  int done = 0;
  int total = 0;
  for (final CoverageSeason s in grid.seasons) {
    for (final CoverageGridEpisode e in s.episodes) {
      final CoverageCell cell = e.cells[column];
      if (cell == CoverageCell.unwanted) {
        continue;
      }
      total++;
      if (cell != CoverageCell.missing) {
        done++;
      }
    }
  }
  return (language: grid.languages[column], done: done, total: total);
}

/// The season the coverage card opens on: the newest with gaps, else the
/// newest.
int? defaultCoverageSeason(CoverageGrid grid) {
  for (final CoverageSeason s in grid.seasons) {
    if (s.gaps > 0) {
      return s.season;
    }
  }
  return grid.seasons.isEmpty ? null : grid.seasons.first.season;
}

String _seasonLabel(int season) => season == 0 ? 'Specials' : 'S$season';

/// The Subtitles card of a Sonarr series page: per-language progress when
/// collapsed; expanded, a language × episode grid per season where every
/// cell opens that episode's subtitles, a Search for the season's gaps, and
/// the series' language profile.
class BazarrSeriesCoverageCard extends StatefulWidget {
  const BazarrSeriesCoverageCard({
    required this.grid,
    required this.onOpenEpisode,
    required this.onSearchSeason,
    this.profileName,
    this.onPressProfile,
    this.expanded = false,
    super.key,
  });

  final CoverageGrid grid;
  final ValueChanged<int> onOpenEpisode;
  final ValueChanged<int> onSearchSeason;

  /// Null: no profile.
  final String? profileName;
  final VoidCallback? onPressProfile;

  /// Start expanded.
  final bool expanded;

  @override
  State<BazarrSeriesCoverageCard> createState() =>
      _BazarrSeriesCoverageCardState();
}

class _BazarrSeriesCoverageCardState extends State<BazarrSeriesCoverageCard> {
  late bool _expanded = widget.expanded;

  // Picked once, so a season stays selected after a search fills its gaps.
  late int? _picked = defaultCoverageSeason(widget.grid);

  CoverageGrid? _totalsOf;
  List<CoverageTotal> _totals = const <CoverageTotal>[];

  List<CoverageTotal> get _currentTotals {
    if (!identical(_totalsOf, widget.grid)) {
      _totalsOf = widget.grid;
      _totals = coverageTotals(widget.grid);
    }
    return _totals;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CoverageGrid grid = widget.grid;
    final Widget card;
    if (grid.languages.isEmpty) {
      // Nothing to chart, but the profile is how the series gets languages.
      card = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.md,
              Insets.lg,
              Insets.xs,
            ),
            child: Text(
              'No subtitle languages wanted yet. Pick a language profile so '
              'Bazarr looks for them.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          LanguageProfileRow(
            profileName: widget.profileName,
            onPressed: widget.onPressProfile,
          ),
        ],
      );
    } else {
      card = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _header(context),
          if (_expanded) ..._body(context),
        ],
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: card,
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  Widget _header(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Semantics(
      button: true,
      expanded: _expanded,
      label: 'Subtitle coverage',
      onTap: _toggle,
      child: InkWell(
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.md,
            Insets.md,
            Insets.lg,
            Insets.md,
          ),
          child: Row(
            spacing: Insets.sm,
            children: <Widget>[
              AnimatedRotation(
                turns: _expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child:
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: Insets.xs),
                  child: Wrap(
                    spacing: Insets.md,
                    runSpacing: Insets.sm,
                    children: <Widget>[
                      for (final CoverageTotal t in _currentTotals)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 6,
                          children: <Widget>[
                            SubtitleTrackChip(
                              code2: t.language.code2,
                              state: SubtitleState.present,
                              forced: t.language.forced,
                              hi: t.language.hi,
                              size: TagSize.sm,
                              ringColor: scheme.surfaceContainerHigh,
                            ),
                            SizedBox(
                              width: 32,
                              height: 4,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: t.total > 0 ? t.done / t.total : 0,
                                  backgroundColor:
                                      scheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            Text(
                              '${t.done}/${t.total}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CoverageGrid grid = widget.grid;
    final List<CoverageSeason> seasons = grid.seasons;
    CoverageSeason? season;
    for (final CoverageSeason s in seasons) {
      if (s.season == _picked) {
        season = s;
        break;
      }
    }
    season ??= seasons.isEmpty ? null : seasons.first;
    final CoverageSeason? shown = season;
    final Widget divider = Divider(
      height: 1,
      thickness: 1,
      color: scheme.surfaceContainerHighest,
    );
    return <Widget>[
      divider,
      if (seasons.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.md,
            Insets.md,
            Insets.md,
            0,
          ),
          child: seasons.length <= 3
              ? SegmentedButton<int>(
                  segments: <ButtonSegment<int>>[
                    for (final CoverageSeason s in seasons)
                      ButtonSegment<int>(
                        value: s.season,
                        label: Text(_seasonLabel(s.season)),
                      ),
                  ],
                  selected: <int>{if (shown != null) shown.season},
                  emptySelectionAllowed: shown == null,
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<int> s) {
                    if (s.isNotEmpty) {
                      setState(() => _picked = s.single);
                    }
                  },
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: Insets.sm,
                    children: <Widget>[
                      for (final CoverageSeason s in seasons)
                        ChoiceChip(
                          label: Text(_seasonLabel(s.season)),
                          selected: s.season == shown?.season,
                          onSelected: (_) => setState(() => _picked = s.season),
                        ),
                    ],
                  ),
                ),
        ),
      if (shown != null)
        _SeasonGrid(
          key: ValueKey<int>(shown.season),
          season: shown,
          languages: grid.languages,
          onOpenEpisode: widget.onOpenEpisode,
        ),
      divider,
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        child: FilledButton.tonalIcon(
          onPressed: shown == null || shown.gaps == 0
              ? null
              : () => widget.onSearchSeason(shown.season),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: Text(
            shown != null && shown.gaps > 0
                ? 'Search ${shown.gaps} episode${shown.gaps == 1 ? '' : 's'}'
                : 'Nothing missing',
          ),
        ),
      ),
      divider,
      LanguageProfileRow(
        profileName: widget.profileName,
        onPressed: widget.onPressProfile,
      ),
    ];
  }
}

/// Grid measurements.
abstract final class CoverageGridMetrics {
  static const double cell = 18;
  static const double columnGap = 4;
  static const double rowGap = 6;
  static const double header = 16;

  /// Top edge of the language rows.
  static const double rowsTop = header + rowGap;

  /// Width of one column, gap included.
  static const double columnStep = cell + columnGap;

  /// Height of one language row, gap included.
  static const double rowStep = cell + rowGap;
}

class _SeasonGrid extends StatelessWidget {
  const _SeasonGrid({
    required this.season,
    required this.languages,
    required this.onOpenEpisode,
    super.key,
  });

  final CoverageSeason season;
  final List<CoverageLanguage> languages;
  final ValueChanged<int> onOpenEpisode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    if (season.episodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        child: Text(
          'No downloaded episodes in this season.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final int n = season.episodes.length;
    final Size size = Size(
      n * CoverageGridMetrics.cell + (n - 1) * CoverageGridMetrics.columnGap,
      CoverageGridMetrics.rowsTop +
          languages.length * CoverageGridMetrics.cell +
          (languages.length - 1) * CoverageGridMetrics.rowGap,
    );
    return Padding(
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The language column stays put while the episode cells scroll.
          Padding(
            padding: const EdgeInsets.only(right: Insets.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: CoverageGridMetrics.rowGap,
              children: <Widget>[
                const SizedBox(height: CoverageGridMetrics.header),
                for (final CoverageLanguage l in languages)
                  SizedBox(
                    height: CoverageGridMetrics.cell,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SubtitleTrackChip(
                          code2: l.code2,
                          state: SubtitleState.present,
                          forced: l.forced,
                          hi: l.hi,
                          size: TagSize.xs,
                          ringColor: scheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                key: const ValueKey<String>('coverage-grid'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails d) {
                  final int? id = coverageCellAt(
                    season,
                    languages.length,
                    d.localPosition,
                  );
                  if (id != null) {
                    onOpenEpisode(id);
                  }
                },
                child: CustomPaint(
                  size: size,
                  painter: _CoveragePainter(
                    season: season,
                    languages: languages,
                    present: scheme.primary,
                    embedded: scheme.outlineVariant,
                    missing: subtitleMissingColor(scheme),
                    dot: scheme.outlineVariant,
                    numberStyle:
                        (theme.textTheme.labelSmall ?? const TextStyle())
                            .copyWith(
                      fontSize: 9.6,
                      color: scheme.onSurfaceVariant,
                    ),
                    onOpenEpisode: onOpenEpisode,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Sonarr episode id of the tappable cell at [p] (grid coordinates), or
/// null: outside any cell, or a language the episode doesn't want.
int? coverageCellAt(CoverageSeason season, int languageCount, Offset p) {
  const double slop = CoverageGridMetrics.columnGap / 2;
  final double y = p.dy - CoverageGridMetrics.rowsTop;
  if (p.dx < 0 || y < -slop) {
    return null;
  }
  final int col = (p.dx + slop) ~/ CoverageGridMetrics.columnStep;
  final int row = (y + slop) ~/ CoverageGridMetrics.rowStep;
  if (col >= season.episodes.length || row >= languageCount) {
    return null;
  }
  final CoverageGridEpisode ep = season.episodes[col];
  if (ep.cells[row] == CoverageCell.unwanted) {
    return null;
  }
  return ep.episodeId;
}

const Map<CoverageCell, String> _cellLabels = <CoverageCell, String>{
  CoverageCell.present: 'subtitle file',
  CoverageCell.embedded: 'embedded track',
  CoverageCell.missing: 'missing',
  CoverageCell.unwanted: 'not wanted',
};

/// "Episode 3, DE forced: missing".
String coverageCellLabel(
  CoverageGridEpisode episode,
  CoverageLanguage language,
  CoverageCell cell,
) =>
    'Episode ${episode.episode}, ${language.code2.toUpperCase()}'
    '${language.forced ? ' forced' : ''}${language.hi ? ' HI' : ''}: '
    '${_cellLabels[cell]}';

class _CoveragePainter extends CustomPainter {
  _CoveragePainter({
    required this.season,
    required this.languages,
    required this.present,
    required this.embedded,
    required this.missing,
    required this.dot,
    required this.numberStyle,
    required this.onOpenEpisode,
  });

  final CoverageSeason season;
  final List<CoverageLanguage> languages;
  final Color present;
  final Color embedded;
  final Color missing;
  final Color dot;
  final TextStyle numberStyle;
  final ValueChanged<int> onOpenEpisode;

  static const Radius _radius = Radius.circular(4);

  Rect _cellRect(int col, int row) => Rect.fromLTWH(
        col * CoverageGridMetrics.columnStep,
        CoverageGridMetrics.rowsTop + row * CoverageGridMetrics.rowStep,
        CoverageGridMetrics.cell,
        CoverageGridMetrics.cell,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint();
    final DashedRRectPainter dashed = DashedRRectPainter(
      color: missing,
      strokeWidth: 1.6,
      radius: _radius.x,
      dash: 3.2,
      gap: 2.4,
    );
    for (int col = 0; col < season.episodes.length; col++) {
      final CoverageGridEpisode ep = season.episodes[col];
      final TextPainter number = TextPainter(
        text: TextSpan(text: '${ep.episode}', style: numberStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      number.paint(
        canvas,
        Offset(
          col * CoverageGridMetrics.columnStep +
              (CoverageGridMetrics.cell - number.width) / 2,
          (CoverageGridMetrics.header - number.height) / 2,
        ),
      );
      number.dispose();
      for (int row = 0; row < languages.length; row++) {
        final Rect rect = _cellRect(col, row);
        switch (ep.cells[row]) {
          case CoverageCell.present:
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, _radius),
              fill..color = present,
            );
          case CoverageCell.embedded:
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, _radius),
              fill..color = embedded,
            );
          case CoverageCell.missing:
            canvas
              ..save()
              ..translate(rect.left, rect.top);
            dashed.paint(canvas, rect.size);
            canvas.restore();
          case CoverageCell.unwanted:
            canvas.drawCircle(rect.center, 2, fill..color = dot);
        }
      }
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
        return <CustomPainterSemantics>[
          for (int col = 0; col < season.episodes.length; col++)
            for (int row = 0; row < languages.length; row++)
              _semantics(col, row),
        ];
      };

  CustomPainterSemantics _semantics(int col, int row) {
    final CoverageGridEpisode ep = season.episodes[col];
    final CoverageCell cell = ep.cells[row];
    final bool tappable = cell != CoverageCell.unwanted;
    return CustomPainterSemantics(
      key: ValueKey<String>('${ep.episodeId}:$row'),
      rect: _cellRect(col, row),
      properties: SemanticsProperties(
        label: coverageCellLabel(ep, languages[row], cell),
        button: tappable,
        textDirection: TextDirection.ltr,
        onTap: tappable ? () => onOpenEpisode(ep.episodeId) : null,
      ),
    );
  }

  @override
  bool shouldRepaint(_CoveragePainter old) =>
      !identical(old.season, season) ||
      !identical(old.languages, languages) ||
      old.present != present ||
      old.embedded != embedded ||
      old.missing != missing ||
      old.dot != dot ||
      old.numberStyle != numberStyle;

  @override
  bool shouldRebuildSemantics(_CoveragePainter old) =>
      !identical(old.season, season) || !identical(old.languages, languages);
}
