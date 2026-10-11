import 'dart:async';

import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../elapsed.dart';

DateTime _systemNow() => DateTime.now();

/// The waiting state of a long-running provider search, so a search that
/// takes a minute never looks frozen: an expressive loading indicator (a
/// still magnifier when the system asks for reduced motion), a title, a hint,
/// and a running m:ss timer that keeps moving either way.
///
/// After [restartAfter] the hint switches to [lateHint] and, when
/// [onRestart] is set, a "Restart search" button appears.
class SearchingIndicator extends StatefulWidget {
  const SearchingIndicator({
    required this.since,
    this.onRestart,
    this.restartAfter = const Duration(seconds: 30),
    this.title = 'Searching providers…',
    this.hint =
        'Bazarr asks every subtitle provider in turn. This can take a minute.',
    this.lateHint = 'Still searching. Some providers are slow or '
        'rate-limited; Bazarr keeps going even if you leave.',
    this.now,
    super.key,
  });

  /// When the search started.
  final DateTime since;
  final VoidCallback? onRestart;
  final Duration restartAfter;
  final String title;
  final String hint;
  final String lateHint;

  /// The clock; defaults to [DateTime.now]. Injectable for tests.
  final DateTime Function()? now;

  @override
  State<SearchingIndicator> createState() => _SearchingIndicatorState();
}

class _SearchingIndicatorState extends State<SearchingIndicator> {
  Timer? _lateTimer;
  bool _late = false;

  DateTime Function() get _now => widget.now ?? _systemNow;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(SearchingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.since != widget.since ||
        oldWidget.restartAfter != widget.restartAfter) {
      _schedule();
    }
  }

  void _schedule() {
    _lateTimer?.cancel();
    _lateTimer = null;
    final remaining = widget.restartAfter - _now().difference(widget.since);
    _late = remaining <= Duration.zero;
    if (!_late) {
      _lateTimer = Timer(remaining, () {
        if (mounted) setState(() => _late = true);
      });
    }
  }

  @override
  void dispose() {
    _lateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: reduceMotion
                  ? Icon(Icons.search, size: 36, color: scheme.primary)
                  : ExpressiveProgressIndicator(color: scheme.primary),
            ),
            const SizedBox(height: Insets.xl),
            Text(
              widget.title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.sm),
            Text(
              _late ? widget.lateHint : widget.hint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.md),
            ElapsedText(
              since: widget.since,
              now: widget.now,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_late && widget.onRestart != null) ...[
              const SizedBox(height: Insets.lg),
              OutlinedButton.icon(
                onPressed: widget.onRestart,
                icon: const Icon(Icons.refresh),
                label: const Text('Restart search'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "0:42": how long something has been running since [since], ticking once
/// a second on the whole second (re-aligned on every tick, so it never
/// drifts), in tabular figures so the digits don't jitter.
class ElapsedText extends StatefulWidget {
  const ElapsedText({
    required this.since,
    this.now,
    this.style,
    super.key,
  });

  final DateTime since;

  /// The clock; defaults to [DateTime.now]. Injectable for tests.
  final DateTime Function()? now;
  final TextStyle? style;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _timer;

  DateTime Function() get _now => widget.now ?? _systemNow;

  Duration get _elapsed {
    final d = _now().difference(widget.since);
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(ElapsedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.since != widget.since) _scheduleTick();
  }

  void _scheduleTick() {
    _timer?.cancel();
    // Wake on the next whole second of elapsed time.
    final ms = _elapsed.inMilliseconds;
    final delay = Duration(milliseconds: 1000 - ms % 1000);
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _elapsed;
    final seconds = elapsed.inSeconds;
    final style = (widget.style ?? DefaultTextStyle.of(context).style)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      label: 'Searching for $seconds second${seconds == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Text(
        formatElapsed(elapsed),
        style: style,
        textAlign: TextAlign.center,
      ),
    );
  }
}
