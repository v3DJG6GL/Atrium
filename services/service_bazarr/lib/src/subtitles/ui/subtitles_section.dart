import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

// The pieces around a subtitles section on the Radarr and Sonarr pages:
// heading, loading, unreachable and not-listed states.

/// "Subtitles" with the serving Bazarr's name on the right, and a cloud-off
/// icon when Bazarr couldn't be reached but older data is shown.
class SubtitlesSectionHeader extends StatelessWidget {
  const SubtitlesSectionHeader({
    required this.bazarrName,
    this.unreachable = false,
    super.key,
  });

  final String bazarrName;

  /// The latest refresh failed; the data shown is older.
  final bool unreachable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Row(
        children: <Widget>[
          Text(
            'Subtitles',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: Insets.md),
          // Spacer plus a Flexible name would split the free space and leave
          // the name mid-row; this keeps it at the end.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (unreachable)
                  Padding(
                    padding: const EdgeInsets.only(right: Insets.xs),
                    child: Tooltip(
                      message: "Couldn't reach $bazarrName.",
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 16,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                Flexible(
                  child: Semantics(
                    label: 'Subtitles come from $bazarrName',
                    excludeSemantics: true,
                    child: Text(
                      bazarrName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The tonal box the section's states sit in.
class SubtitlesStateBox extends StatelessWidget {
  const SubtitlesStateBox({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: child,
      );
}

/// A 52 px placeholder while Bazarr's data loads.
class SubtitlesSkeleton extends StatelessWidget {
  const SubtitlesSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      );
}

/// "Couldn't reach {Bazarr}." with Retry, when its data never loaded.
class SubtitlesUnreachable extends StatelessWidget {
  const SubtitlesUnreachable({
    required this.bazarrName,
    required this.onRetry,
    super.key,
  });

  final String bazarrName;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SubtitlesStateBox(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              "Couldn't reach $bazarrName.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Bazarr hasn't synced this movie or series from Radarr/Sonarr yet.
class SubtitlesNotListed extends StatelessWidget {
  const SubtitlesNotListed({
    required this.bazarrName,
    this.series = false,
    super.key,
  });

  final String bazarrName;

  /// A series rather than a movie.
  final bool series;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SubtitlesStateBox(
      child: Text(
        series
            ? "$bazarrName doesn't list this series yet. It picks up new "
                'Sonarr series on its next sync.'
            : "$bazarrName doesn't list this movie yet. It picks up new "
                'Radarr movies on its next sync.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// "Language profile" with the profile's name and a chevron; null
/// [profileName] reads "None".
class LanguageProfileRow extends StatelessWidget {
  const LanguageProfileRow({
    required this.profileName,
    this.onPressed,
    super.key,
  });

  final String? profileName;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: onPressed != null,
      label: 'Language profile: ${profileName ?? 'none'}',
      excludeSemantics: true,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg,
            vertical: Insets.md,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Language profile',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(profileName ?? 'None', style: theme.textTheme.bodySmall),
              if (onPressed != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
