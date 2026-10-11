import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../bazarr_api.dart';
import '../../models/bazarr_models.dart';
import '../bazarr_activity.dart';
import '../bazarr_subtitle_params.dart';
import 'manual_search_helpers.dart';
import 'manual_search_providers.dart';
import 'manual_search_result_card.dart';

/// Opens the details of one manual-search [result]. Resolves to true once
/// Bazarr accepted the download (the caller then leaves the search).
Future<bool> showManualSearchDetailSheet(
  BuildContext context, {
  required Instance bazarr,
  required SubtitleTarget target,
  required BazarrSubtitleSearchResult result,
}) async {
  final bool? downloaded = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (BuildContext context) => ManualSearchDetailSheet(
      bazarr: bazarr,
      target: target,
      result: result,
    ),
  );
  return downloaded ?? false;
}

/// Every release name a candidate matches, what matched and what didn't, its
/// uploader and link, and the Download button.
class ManualSearchDetailSheet extends ConsumerStatefulWidget {
  const ManualSearchDetailSheet({
    required this.bazarr,
    required this.target,
    required this.result,
    super.key,
  });

  final Instance bazarr;
  final SubtitleTarget target;
  final BazarrSubtitleSearchResult result;

  @override
  ConsumerState<ManualSearchDetailSheet> createState() =>
      _ManualSearchDetailSheetState();
}

class _ManualSearchDetailSheetState
    extends ConsumerState<ManualSearchDetailSheet> {
  bool _downloading = false;
  bool _failed = false;

  Future<void> _download() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final BazarrSubtitleSearchResult result = widget.result;
    final SubtitleTarget target = widget.target;
    setState(() {
      _downloading = true;
      _failed = false;
    });
    try {
      await ref.read(bazarrActivityProvider(widget.bazarr.id).notifier).run(
            '${target.key}:manual',
            (BazarrApi api) => api.downloadResult(target, result),
            refresh: bazarrManualSearchRefresh(widget.bazarr, target),
          );
    } on Object {
      if (mounted) {
        setState(() {
          _downloading = false;
          _failed = true;
        });
      }
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Downloading ${resultLanguage(result.language).name} subtitle…',
        ),
      ),
    );
    if (mounted) {
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final BazarrSubtitleSearchResult r = widget.result;
    final String? uploader =
        (r.uploader?.isNotEmpty ?? false) ? r.uploader : null;
    final String? url = (r.url?.isNotEmpty ?? false) ? r.url : null;
    final String format = r.originalFormat;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Subtitle details', style: theme.textTheme.titleLarge),
                const SizedBox(height: Insets.xxs),
                Text(
                  '${r.provider}${uploader != null ? ' · $uploader' : ''}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < r.releaseInfo.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Insets.xs),
                      child: SelectableText(
                        r.releaseInfo[i],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: i == 0
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: Insets.sm),
                  Wrap(
                    spacing: Insets.sm + 2,
                    runSpacing: Insets.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      ResultLanguageChip(
                        result: r,
                        size: TagSize.md,
                        ringColor: scheme.surfaceContainerLow,
                      ),
                      Text(
                        resultLanguageLine(r),
                        style: theme.textTheme.bodyMedium,
                      ),
                      ScoreBadge(score: r.score),
                    ],
                  ),
                  const SizedBox(height: Insets.lg),
                  _StatGrid(
                    stats: <(String, String)>[
                      ('Provider', r.provider),
                      ('Score', scoreLabel(r.score)),
                      if (uploader != null) ('Uploader', uploader),
                      if (format.isNotEmpty)
                        (
                          'Format',
                          isBazarrTrue(format)
                              ? 'Original'
                              : 'Converted to SRT',
                        ),
                    ],
                  ),
                  if (r.matches.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Insets.md),
                    _MatchGroup(
                      label: 'Matched',
                      keys: r.matches,
                      matched: true,
                    ),
                  ],
                  if (r.dontMatches.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Insets.md),
                    _MatchGroup(
                      label: "Didn't match",
                      keys: r.dontMatches,
                      matched: false,
                    ),
                  ],
                  if (url != null) ...<Widget>[
                    const SizedBox(height: Insets.md),
                    _LinkRow(url: url),
                  ],
                  const SizedBox(height: Insets.lg),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              Insets.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: Text(
                      "Couldn't download the subtitle",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.error),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _downloading ? null : _download,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: ExpressiveProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_downloading ? 'Downloading…' : 'Download'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label-over-value cells, two per row.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double cell = constraints.maxWidth / 2;
          return Wrap(
            runSpacing: Insets.sm,
            children: <Widget>[
              for (final (String label, String value) in stats)
                SizedBox(
                  width: cell,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Insets.xxs),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "Matched" / "Didn't match" and the attribute chips under it.
class _MatchGroup extends StatelessWidget {
  const _MatchGroup({
    required this.label,
    required this.keys,
    required this.matched,
  });

  final String label;
  final List<String> keys;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color fill =
        matched ? scheme.tertiaryContainer : scheme.errorContainer;
    final Color fg =
        matched ? scheme.onTertiaryContainer : scheme.onErrorContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Insets.xs + 2),
        Wrap(
          spacing: Insets.xs + 2,
          runSpacing: Insets.xs + 2,
          children: <Widget>[
            for (final String key in keys)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.sm,
                  vertical: Insets.xs,
                ),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      matched ? Icons.check : Icons.close,
                      size: 14,
                      color: fg,
                    ),
                    const SizedBox(width: Insets.xs),
                    Text(
                      humanizeMatchKey(key),
                      style: theme.textTheme.labelMedium?.copyWith(color: fg),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The result's page on the provider's site: tap to open it in the browser,
/// or copy it.
class _LinkRow extends StatefulWidget {
  const _LinkRow({required this.url});

  final String url;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _copied = false;
  bool _openFailed = false;
  Timer? _reset;

  Future<void> _open() async {
    bool launched = false;
    final Uri? uri = Uri.tryParse(widget.url);
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } on Object {
        launched = false;
      }
    }
    if (mounted) {
      setState(() => _openFailed = !launched);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                borderRadius: Radii.card,
                onTap: _open,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.open_in_new, size: 16, color: scheme.primary),
                      const SizedBox(width: Insets.xs),
                      Expanded(
                        child: Text(
                          widget.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: _copied ? 'Copied' : 'Copy link',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: _copy,
              icon: Icon(_copied ? Icons.check : Icons.copy_rounded),
            ),
          ],
        ),
        if (_openFailed)
          Text(
            "Couldn't open the link",
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
      ],
    );
  }
}
