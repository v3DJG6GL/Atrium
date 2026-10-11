import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bazarr_models.dart';
import '../bazarr_subtitle_params.dart';
import 'manual_search_detail_sheet.dart';
import 'manual_search_filter_sheet.dart';
import 'manual_search_helpers.dart';
import 'manual_search_providers.dart';
import 'manual_search_result_card.dart';

/// Bazarr's manual subtitle search for one movie or episode.
///
/// Bazarr searches every language in the item's profile at once, so the
/// language is a filter on the results, not a search parameter. Picking a
/// result opens its details; Download hands it to Bazarr and returns to the
/// page the search came from.
class BazarrManualSearchScreen extends ConsumerStatefulWidget {
  const BazarrManualSearchScreen({
    required this.bazarr,
    required this.target,
    required this.title,
    super.key,
  });

  final Instance bazarr;
  final SubtitleTarget target;

  /// What is searched: a movie title or "S01E02".
  final String title;

  @override
  ConsumerState<BazarrManualSearchScreen> createState() =>
      _BazarrManualSearchScreenState();
}

class _BazarrManualSearchScreenState
    extends ConsumerState<BazarrManualSearchScreen> {
  String _language = allLanguages;
  ManualSearchSort _sort = ManualSearchSort.best;

  // When the current search started, for the searching state's timer.
  DateTime _searchStarted = DateTime.now();

  // Re-renders the "12s ago" status.
  late final Timer _ticker;

  BazarrManualSearchArgs get _args =>
      (bazarr: widget.bazarr, target: widget.target);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _restart() {
    setState(() => _searchStarted = DateTime.now());
    ref.invalidate(bazarrManualSearchProvider(_args));
  }

  Future<void> _refresh() async {
    _restart();
    try {
      await ref.read(bazarrManualSearchProvider(_args).future);
    } on Object {
      // The error state shows it.
    }
  }

  Future<void> _openFilters(List<BazarrSubtitleSearchResult> results) =>
      showManualSearchFilterSheet(
        context,
        total: results.length,
        languages: languageCounts(results),
        language: _language,
        sort: _sort,
        onLanguage: (String l) {
          if (mounted) {
            setState(() => _language = l);
          }
        },
        onSort: (ManualSearchSort s) {
          if (mounted) {
            setState(() => _sort = s);
          }
        },
      );

  Future<void> _openResult(BazarrSubtitleSearchResult result) async {
    final bool downloaded = await showManualSearchDetailSheet(
      context,
      bazarr: widget.bazarr,
      target: widget.target,
      result: result,
    );
    if (downloaded && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<BazarrSubtitleSearchResult>> value =
        ref.watch(bazarrManualSearchProvider(_args));
    final Widget body;
    if (value.isLoading && !value.hasValue) {
      body = SearchingIndicator(since: _searchStarted, onRestart: _restart);
    } else if (value.hasError && !value.isLoading) {
      final Object error = value.error!;
      body = ErrorView(
        title: 'Search failed',
        message: _errorMessage(error),
        onRetry: _restart,
      );
    } else {
      body = _results(value.requireValue, refreshing: value.isLoading);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Subtitles · ${widget.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: body,
    );
  }

  Widget _results(
    List<BazarrSubtitleSearchResult> results, {
    required bool refreshing,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // A language that a fresh search no longer returns would hide everything.
    final String language = _language == allLanguages ||
            results.any(
              (BazarrSubtitleSearchResult r) => r.language == _language,
            )
        ? _language
        : allLanguages;
    final List<BazarrSubtitleSearchResult> items =
        filterAndSortResults(results, language: language, sort: _sort);
    final DateTime? arrived = bazarrManualSearchArrivedAt(results);
    final bool filtered =
        language != allLanguages || _sort != ManualSearchSort.best;

    final Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.lg,
        Insets.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                resultCountLabel(items.length, results.length),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              if (arrived != null) ...<Widget>[
                const SizedBox(width: Insets.xs),
                Text(
                  '· ${relativeTimeLabel(arrived, DateTime.now())}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
              if (refreshing) ...<Widget>[
                const SizedBox(width: Insets.sm),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: ExpressiveProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          if (results.isNotEmpty) ...<Widget>[
            const SizedBox(height: Insets.sm),
            ActionChip(
              avatar: Icon(
                Icons.tune_rounded,
                size: 18,
                color: filtered
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              label: Text(
                '${languageFilterName(language)} · ${_sort.label}',
              ),
              backgroundColor: filtered ? scheme.secondaryContainer : null,
              side: filtered ? BorderSide.none : null,
              labelStyle: filtered
                  ? TextStyle(color: scheme.onSecondaryContainer)
                  : null,
              onPressed: () => _openFilters(results),
            ),
          ],
        ],
      ),
    );

    final Widget list;
    if (items.isEmpty) {
      final Widget empty = results.isEmpty
          ? const EmptyView(
              icon: Icons.search_off_rounded,
              title: 'No subtitles found',
              message: "No provider had a match for this file's languages. "
                  'Pull to search again.',
            )
          : EmptyView(
              icon: Icons.search_off_rounded,
              title: 'No results in this language',
              action: OutlinedButton(
                onPressed: () => setState(() => _language = allLanguages),
                child: const Text('Clear filters'),
              ),
            );
      list = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: empty),
            ),
          ],
        ),
      );
    } else {
      list = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.xs,
          Insets.lg,
          Insets.xxl,
        ),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int i) => ManualSearchResultCard(
          key: ValueKey<String>(resultKey(items[i])),
          result: items[i],
          onTap: () => _openResult(items[i]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Expanded(child: EasyRefresh(onRefresh: _refresh, child: list)),
      ],
    );
  }
}

String _errorMessage(Object error) => switch (error) {
      NetworkTimeoutException() =>
        'The search timed out. Providers may be slow or rate-limited. '
            'Try again.',
      NetworkException(:final String message) when message.isNotEmpty =>
        message,
      _ => error.toString(),
    };
