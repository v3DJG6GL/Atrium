import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bazarr_api.dart';
import '../models/bazarr_models.dart';
import '../subtitles/bazarr_activity.dart';
import '../subtitles/bazarr_subtitle_params.dart';
import '../subtitles/subtitle_actions.dart';
import 'bazarr_history_logic.dart';
import 'bazarr_history_providers.dart';
import 'history_detail_sheet.dart';
import 'history_row.dart';

/// How close to the end of the list the next page starts loading.
const double _loadMoreExtent = 600;

/// Bazarr's subtitle history: movie and episode activity merged newest
/// first, grouped by day, a page at a time. An entry opens a detail sheet
/// with what matched, the file, a way to open the movie or episode, and
/// "Blacklist and search again" for a download that turned out wrong.
class BazarrHistoryList extends ConsumerStatefulWidget {
  const BazarrHistoryList({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<BazarrHistoryList> createState() => _BazarrHistoryListState();
}

class _BazarrHistoryListState extends ConsumerState<BazarrHistoryList> {
  final ScrollController _scroll = ScrollController();
  bool _checkScheduled = false;

  Instance get _instance => widget.instance;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _scheduleFillCheck();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() => _maybeLoadMore(retryFailed: false);

  /// After a frame, loads the next page when the list doesn't fill the
  /// screen or already ends near the bottom: no scroll would ask for it. This
  /// also resumes paging once a refresh that blocked it settles.
  void _scheduleFillCheck() {
    if (_checkScheduled) {
      return;
    }
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) {
        _maybeLoadMore(retryFailed: false);
      }
    });
  }

  bool get _nearEnd {
    if (!_scroll.hasClients || _scroll.positions.length != 1) {
      return false;
    }
    final ScrollPosition position = _scroll.position;
    return !position.hasContentDimensions ||
        position.extentAfter < _loadMoreExtent;
  }

  /// Pages the streams the merged list waits on. A stream whose last page
  /// failed is retried only when [retryFailed] (the user scrolled to the
  /// end), so a broken page doesn't loop.
  void _maybeLoadMore({required bool retryFailed}) {
    if (!_nearEnd) {
      return;
    }
    final BazarrHistoryView view =
        ref.read(bazarrHistoryViewProvider(_instance));
    for (final HistoryKind kind in view.toPage) {
      if (!retryFailed && view.failedPages.contains(kind)) {
        continue;
      }
      unawaited(
        ref
            .read(
              bazarrHistoryStreamProvider((instance: _instance, kind: kind))
                  .notifier,
            )
            .loadMore(),
      );
    }
  }

  Future<void> _refresh() async {
    final BazarrHistoryFilter filter =
        ref.read(bazarrHistoryFilterProvider(_instance));
    final List<Future<BazarrHistoryStream>> loads =
        <Future<BazarrHistoryStream>>[];
    for (final HistoryKind kind in filter.kinds) {
      final BazarrHistoryStreamKey key = (instance: _instance, kind: kind);
      ref.invalidate(bazarrHistoryStreamProvider(key));
      loads.add(ref.read(bazarrHistoryStreamProvider(key).future));
    }
    try {
      await Future.wait(loads);
    } on Object {
      // The error shows in the list.
    }
  }

  void _setFilter(BazarrHistoryFilter filter) {
    ref.read(bazarrHistoryFilterProvider(_instance).notifier).set(filter);
    if (_scroll.hasClients && _scroll.positions.length == 1) {
      _scroll.jumpTo(0);
    }
  }

  Future<void> _openDetail(HistoryEntry entry) async {
    final HistoryDetailAction? action = await showHistoryDetailSheet(
      context,
      bazarr: _instance,
      entry: entry,
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case HistoryDetailAction.open:
        await openHistoryEntry(context, ref, _instance, entry);
      case HistoryDetailAction.blacklist:
        await blacklistHistoryEntry(context, ref, _instance, entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final BazarrHistoryView view =
        ref.watch(bazarrHistoryViewProvider(_instance));
    final Set<String> blacklisted =
        ref.watch(bazarrHistoryBlacklistedProvider(_instance));
    ref.listen<BazarrHistoryView>(
      bazarrHistoryViewProvider(_instance),
      (BazarrHistoryView? _, BazarrHistoryView __) => _scheduleFillCheck(),
    );
    final bool hasRows = view.rows.isNotEmpty;

    return EasyRefresh(
      header: const ClassicHeader(
        dragText: 'Pull to refresh',
        armedText: 'Release ready',
        readyText: 'Refreshing...',
        processingText: 'Refreshing...',
        processedText: 'Succeeded',
        failedText: 'Failed',
        messageText: 'Last updated at %T',
      ),
      onRefresh: _refresh,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (ScrollEndNotification _) {
          _maybeLoadMore(retryFailed: true);
          return false;
        },
        child: CustomScrollView(
          key: PageStorageKey<String>('bazarr-history-${_instance.id}'),
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: _FilterChips(
                filter: view.filter,
                onChanged: _setFilter,
              ),
            ),
            // With rows on screen the error never replaces them: on "All"
            // one stream can fail while the other loads, which must not pass
            // for the whole history.
            if (view.error != null && hasRows)
              const SliverToBoxAdapter(
                child: _Banner(message: "Some history couldn't load"),
              ),
            if (!hasRows)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyBody(
                  view: view,
                  onRetry: _refresh,
                ),
              )
            else
              SliverPadding(
                padding: Insets.pageH,
                sliver: SliverList.builder(
                  itemCount: view.rows.length,
                  itemBuilder: (BuildContext context, int i) =>
                      switch (view.rows[i]) {
                    BazarrHistoryDayRow(:final HistoryDayGroup group) =>
                      HistoryDayHeader(label: group.label),
                    BazarrHistoryEntryRow(:final HistoryEntry entry) =>
                      HistoryRow(
                        key: ValueKey<String>(entry.key),
                        entry: entry,
                        blacklisted: entry.item.blacklisted ||
                            blacklisted.contains(entry.key),
                        onTap: () => _openDetail(entry),
                      ),
                  },
                ),
              ),
            if (view.loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: Insets.lg),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: ExpressiveProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: Insets.lg)),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.filter, required this.onChanged});

  final BazarrHistoryFilter filter;
  final ValueChanged<BazarrHistoryFilter> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.sm,
          Insets.lg,
          Insets.xs,
        ),
        child: Row(
          children: <Widget>[
            for (final BazarrHistoryFilter f in BazarrHistoryFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: Insets.sm),
                child: FilterChip(
                  label: Text(f.label),
                  selected: f == filter,
                  showCheckmark: false,
                  onSelected: (bool _) => onChanged(f),
                ),
              ),
          ],
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.xs,
        Insets.lg,
        Insets.xs,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 18,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading, error or empty, whichever applies to a list without rows.
class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.view, required this.onRetry});

  final BazarrHistoryView view;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (view.waiting) {
      return const _Skeleton();
    }
    if (view.error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: Insets.xxl),
        child: ErrorView(
          message: "Couldn't load history",
          onRetry: onRetry,
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.only(top: Insets.xxl),
      child: EmptyView(
        icon: Icons.history,
        title: 'No subtitle activity yet',
        message: 'Downloads, uploads and changes show up here.',
      ),
    );
  }
}

/// Placeholder rows while the first pages load.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Semantics(
      label: 'Loading history',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.md,
          Insets.lg,
          0,
        ),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < 6; i++)
              Container(
                height: 60,
                margin: const EdgeInsets.only(bottom: Insets.sm),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Delete the English subtitle from opensubtitles for Dune, …?"
String blacklistConfirmMessage(HistoryEntry entry) {
  final String language = entry.item.language?.name ?? '';
  final String provider =
      entry.item.provider.isNotEmpty ? entry.item.provider : 'this provider';
  return 'Delete the ${language.isNotEmpty ? '$language ' : ''}subtitle '
      'from $provider for ${historyTitle(entry)}, block it from future '
      'searches, and look for a replacement?';
}

/// Asks, then blacklists [entry]'s subtitle and has Bazarr look for another.
/// The row shows as blacklisted right away and goes back if Bazarr refuses.
Future<void> blacklistHistoryEntry(
  BuildContext context,
  WidgetRef ref,
  Instance bazarr,
  HistoryEntry entry,
) async {
  final SubtitleTarget? target = historyTargetOf(entry);
  if (target == null || !canBlacklist(entry)) {
    return;
  }
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) {
      final ColorScheme scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: const Icon(Icons.block),
        title: const Text('Blacklist subtitle'),
        content: Text(blacklistConfirmMessage(entry)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Blacklist'),
          ),
        ],
      );
    },
  );
  if (ok != true || !context.mounted) {
    return;
  }
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  final List<WatchedProvider> refresh = <WatchedProvider>[
    ...SubtitleActions.of(context, bazarr: bazarr).refreshFor(target),
    ...bazarrHistoryRefresh(bazarr),
  ];
  final BazarrHistoryBlacklisted marks =
      ref.read(bazarrHistoryBlacklistedProvider(bazarr).notifier);
  final BazarrActivity activity =
      ref.read(bazarrActivityProvider(bazarr.id).notifier);
  final BazarrHistoryItem item = entry.item;
  marks.add(entry.key);
  void show(String message) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  try {
    await activity.run<void>(
      '${target.key}:blacklist',
      (BazarrApi api) => api.blacklistSubtitle(
        target,
        provider: item.provider,
        subsId: item.subsId ?? '',
        language: item.language?.code2 ?? '',
        subtitlesPath: item.subtitlesPath ?? '',
      ),
      refresh: refresh,
    );
  } on Object {
    marks.remove(entry.key);
    show("Couldn't blacklist the subtitle");
    return;
  }
  show('Blacklisted. Bazarr is looking for another subtitle…');
}
