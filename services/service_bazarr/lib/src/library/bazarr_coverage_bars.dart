import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import 'bazarr_library_logic.dart';

/// The "available" tint of a coverage bar's filter: green, so it doesn't
/// blend into the bar.
Color coverageAvailableColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade700;

/// Per-language coverage across the movie library, one compact bar per
/// language a profile asks for. A tap cycles a bar through three filters:
/// the movies missing the language (its chip turns into the dashed
/// "missing" chip), the movies with it available, then off. The label says
/// which is on.
class BazarrCoverageBars extends StatelessWidget {
  const BazarrCoverageBars({
    required this.coverage,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final List<LanguageCoverage> coverage;
  final LanguageFilter? selected;

  /// Called with the tapped language's code.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (coverage.isEmpty) {
      return const SizedBox.shrink();
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      padding: const EdgeInsets.only(left: Insets.sm + 2),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.closed_caption_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(Insets.xs + 2),
              child: Row(
                children: <Widget>[
                  for (final LanguageCoverage c in coverage)
                    Padding(
                      padding: const EdgeInsets.only(right: Insets.xs),
                      child: _CoverageBar(
                        coverage: c,
                        show: selected?.code2 == c.code2
                            ? selected?.show
                            : null,
                        onTap: () => onTap(c.code2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverageBar extends StatelessWidget {
  const _CoverageBar({
    required this.coverage,
    required this.show,
    required this.onTap,
  });

  final LanguageCoverage coverage;
  final LanguageShow? show;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final LanguageCoverage c = coverage;
    final int pct = coveragePercent(c.have, c.total);
    final String name = normalizeLanguage(c.code2)?.name ?? c.code2;
    final Color missingColor = subtitleMissingColor(scheme);
    final Color availableColor = coverageAvailableColor(scheme);
    final String now = switch (show) {
      LanguageShow.missing =>
        'Showing movies missing it; tap to show movies with it available',
      LanguageShow.have => 'Showing movies with it available; tap to clear',
      null => 'Tap to show movies missing it',
    };
    final Color? tint = switch (show) {
      LanguageShow.missing => missingColor.withValues(alpha: 0.15),
      LanguageShow.have => availableColor.withValues(alpha: 0.15),
      null => null,
    };
    return Semantics(
      button: true,
      selected: show != null,
      label: '$name: ${c.have} of ${c.total} movies have it, '
          '${c.missing} missing. $now',
      excludeSemantics: true,
      child: Material(
        color: tint ?? Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          key: ValueKey<String>('coverage-${c.code2}'),
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.sm,
              vertical: Insets.xs + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SubtitleTrackChip(
                  code2: c.code2,
                  state: show == LanguageShow.missing
                      ? SubtitleState.missing
                      : SubtitleState.present,
                  size: TagSize.sm,
                  languageName: name,
                ),
                const SizedBox(width: Insets.xs + 2),
                SizedBox(
                  width: 40,
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: Insets.xs + 2),
                switch (show) {
                  LanguageShow.missing => _FilterPill(
                      icon: Icons.radio_button_unchecked,
                      label: '${c.missing} missing',
                      color: missingColor,
                    ),
                  LanguageShow.have => _FilterPill(
                      icon: Icons.check,
                      label: '${c.have} available',
                      color: availableColor,
                    ),
                  null => Text(
                      '$pct%',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A filter's label as a tinted pill, so it reads as a state rather than as
/// the bar's value.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: Insets.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
