import 'package:collection/collection.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../bazarr_subtitle_params.dart';
import '../subtitle_ui_text.dart';
import 'subtitle_sheet.dart';

/// The steps of the shift nudges.
const List<({int ms, String label})> timingSteps = <({int ms, String label})>[
  (ms: 100, label: '0.1 s'),
  (ms: 500, label: '0.5 s'),
  (ms: 1000, label: '1 s'),
  (ms: 5000, label: '5 s'),
  (ms: 60000, label: '1 min'),
];

/// The listed frame rate within 0.01 of [videoFps], or null.
num? knownFrameRate(double? videoFps) => videoFps == null
    ? null
    : frameRates.firstWhereOrNull((num r) => (r - videoFps).abs() < 0.01);

/// The frame-rate defaults: "plays at" is the video's rate when listed, else
/// 23.976; "made for" is 25, or 23.976 for a 25 fps video.
({num from, num to}) defaultFrameRates(double? videoFps) {
  final num? known = knownFrameRate(videoFps);
  return (from: known == 25 ? 23.976 : 25, to: known ?? 23.976);
}

/// Opens "Adjust timing". [onApply] runs the chosen action and throws on
/// failure (shown in the sheet); resolves with what was done ("Shifted by
/// +1.5 s") once it succeeded, or null when dismissed.
Future<String?> showSubtitleTimingSheet(
  BuildContext context, {
  required String subtitle,
  required Future<void> Function(SubtitleToolAction action) onApply,
  double? videoFps,
}) =>
    showSubtitleSheet<String>(
      context,
      builder: (BuildContext _) => SubtitleTimingSheet(
        subtitle: subtitle,
        videoFps: videoFps,
        onApply: onApply,
      ),
    );

enum _TimingMode { shift, fps }

/// Shift every line by any amount, or convert between frame rates when lines
/// drift further off the longer the video runs.
class SubtitleTimingSheet extends StatefulWidget {
  const SubtitleTimingSheet({
    required this.subtitle,
    required this.onApply,
    this.videoFps,
    super.key,
  });

  /// "German · Film.de.srt".
  final String subtitle;

  /// The video's frame rate from its media info.
  final double? videoFps;
  final Future<void> Function(SubtitleToolAction action) onApply;

  @override
  State<SubtitleTimingSheet> createState() => _SubtitleTimingSheetState();
}

class _SubtitleTimingSheetState extends State<SubtitleTimingSheet> {
  _TimingMode _mode = _TimingMode.shift;
  int _offsetMs = 0;
  int _step = 500;
  late num _fromFps;
  late num _toFps;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ({num from, num to}) d = defaultFrameRates(widget.videoFps);
    _fromFps = d.from;
    _toFps = d.to;
  }

  bool get _canApply =>
      _mode == _TimingMode.shift ? _offsetMs != 0 : _fromFps != _toFps;

  String get _label => _mode == _TimingMode.shift
      ? (_offsetMs == 0 ? 'Shift' : 'Shift by ${formatOffset(_offsetMs)}')
      : 'Convert $_fromFps → $_toFps fps';

  Future<void> _apply() async {
    final bool shift = _mode == _TimingMode.shift;
    final SubtitleToolAction action = shift
        ? SubtitleToolAction.shift(_offsetMs)
        : SubtitleToolAction.fps(_fromFps, _toFps);
    final String done = shift
        ? 'Shifted by ${formatOffset(_offsetMs)}'
        : 'Converted from $_fromFps to $_toFps fps';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onApply(action);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Bazarr couldn't change the timing";
        });
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final num? known = knownFrameRate(widget.videoFps);
    return SubtitleSheetFrame(
      title: 'Adjust timing',
      subtitle: widget.subtitle,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_error != null) SheetErrorText(_error!),
          FilledButton(
            onPressed: _canApply && !_busy ? _apply : null,
            child: _busy ? const SmallSpinner() : Text(_label),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<_TimingMode>(
            segments: const <ButtonSegment<_TimingMode>>[
              ButtonSegment<_TimingMode>(
                value: _TimingMode.shift,
                label: Text('Shift'),
              ),
              ButtonSegment<_TimingMode>(
                value: _TimingMode.fps,
                label: Text('Frame rate'),
              ),
            ],
            selected: <_TimingMode>{_mode},
            showSelectedIcon: false,
            onSelectionChanged: (Set<_TimingMode> s) =>
                setState(() => _mode = s.single),
          ),
          const SizedBox(height: Insets.lg),
          if (_mode == _TimingMode.shift) ...<Widget>[
            Row(
              children: <Widget>[
                _NudgeButton(
                  icon: Icons.remove,
                  label: 'Earlier',
                  onPressed: () => setState(() => _offsetMs -= _step),
                ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Text(
                        formatOffset(_offsetMs),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                          color: _offsetMs == 0
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: Insets.xxs),
                      Text(
                        _offsetMs == 0
                            ? 'Tap − to show lines earlier, + to show them '
                                'later'
                            : _offsetMs < 0
                                ? 'Lines appear earlier'
                                : 'Lines appear later',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _NudgeButton(
                  icon: Icons.add,
                  label: 'Later',
                  onPressed: () => setState(() => _offsetMs += _step),
                ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            const SheetLabel('Step per tap'),
            _ChipRow(
              children: <Widget>[
                for (final ({int ms, String label}) s in timingSteps)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _step == s.ms,
                    onSelected: (_) => setState(() => _step = s.ms),
                  ),
              ],
            ),
          ] else ...<Widget>[
            const SheetLabel('Subtitle was made for'),
            _ChipRow(
              children: <Widget>[
                for (final num r in frameRates)
                  ChoiceChip(
                    label: Text('$r'),
                    selected: _fromFps == r,
                    onSelected: (_) => setState(() => _fromFps = r),
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            const SheetLabel('Video plays at'),
            _ChipRow(
              children: <Widget>[
                for (final num r in frameRates)
                  ChoiceChip(
                    label: Text('$r'),
                    selected: _toFps == r,
                    onSelected: (_) => setState(() => _toFps = r),
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            Text(
              'Use this when lines drift further off the longer the video '
              'runs.'
              '${known != null ? ' The video plays at $known fps, from its '
                  'media info.' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 56,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          // Also the button's semantic label.
          tooltip: label,
          iconSize: 26,
          style: IconButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
            ),
          ),
          icon: Icon(icon),
        ),
      );
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: Insets.sm, children: children),
      );
}
