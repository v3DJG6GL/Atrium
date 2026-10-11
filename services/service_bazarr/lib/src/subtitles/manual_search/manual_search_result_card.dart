import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../models/bazarr_models.dart';
import 'manual_search_helpers.dart';

/// "87%": a manual-search score, tinted by how good it is.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({required this.score, super.key});

  final num score;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color amber = subtitleMissingColor(scheme);
    final (Color fill, Color text) = switch (scoreBand(score)) {
      ScoreBand.high => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      ScoreBand.mid => (scheme.surfaceContainerHighest, scheme.onSurface),
      ScoreBand.low => (amber.withValues(alpha: 0.16), amber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        scoreLabel(score),
        style: theme.textTheme.labelSmall?.copyWith(
          color: text,
          fontWeight: FontWeight.w700,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The language chip of a result, with its forced / hearing-impaired badge.
class ResultLanguageChip extends StatelessWidget {
  const ResultLanguageChip({
    required this.result,
    this.size = TagSize.sm,
    this.ringColor,
    super.key,
  });

  final BazarrSubtitleSearchResult result;
  final TagSize size;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final ResultLanguage lang = resultLanguage(result.language);
    return SubtitleTrackChip(
      code2: lang.code2,
      languageName: lang.name,
      state: SubtitleState.present,
      forced: isBazarrTrue(result.forced),
      hi: isBazarrTrue(result.hearingImpaired),
      size: size,
      ringColor: ringColor,
    );
  }
}

/// One manual-search candidate: release name, language chip, score,
/// provider, and how many attributes matched and didn't.
class ManualSearchResultCard extends StatelessWidget {
  const ManualSearchResultCard({
    required this.result,
    required this.onTap,
    super.key,
  });

  final BazarrSubtitleSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? meta =
        theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final List<String> releases = result.releaseInfo;
    final String release =
        releases.isNotEmpty ? releases.first : 'Unnamed release';
    final int more = releases.length - 1;
    final String? uploader = result.uploader;
    final Color cardColor = scheme.surfaceContainerHigh;
    return Semantics(
      container: true,
      button: true,
      onTap: onTap,
      label: '${resultLanguage(result.language).name} subtitle from '
          '${result.provider}, ${result.score.round()} percent match',
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.only(bottom: Insets.sm),
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: release,
                          children: <InlineSpan>[
                            if (more > 0)
                              TextSpan(
                                text: ' +$more',
                                style: TextStyle(color: scheme.outline),
                              ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: scheme.outline,
                    ),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.sm + 2,
                  runSpacing: Insets.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    ResultLanguageChip(result: result, ringColor: cardColor),
                    ScoreBadge(score: result.score),
                    Text(result.provider, style: meta),
                  ],
                ),
                const SizedBox(height: Insets.xs + 2),
                Row(
                  children: <Widget>[
                    Icon(Icons.check, size: 14, color: scheme.tertiary),
                    const SizedBox(width: Insets.xxs),
                    Text('${result.matches.length}', style: meta),
                    if (result.dontMatches.isNotEmpty) ...<Widget>[
                      const SizedBox(width: Insets.sm),
                      Icon(Icons.close, size: 14, color: scheme.error),
                      const SizedBox(width: Insets.xxs),
                      Text('${result.dontMatches.length}', style: meta),
                    ],
                    if (uploader != null && uploader.isNotEmpty) ...<Widget>[
                      const SizedBox(width: Insets.md),
                      Flexible(
                        child: Text(
                          uploader,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: meta?.copyWith(color: scheme.outline),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
