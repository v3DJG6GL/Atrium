import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

/// Opens a subtitle bottom sheet on the root navigator, at most 90% of the
/// screen tall.
Future<T?> showSubtitleSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) =>
    showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: builder,
    );

/// The layout of a subtitle sheet: a title and subtitle, scrolling content,
/// an optional footer pinned below it. Lifts above the keyboard.
class SubtitleSheetFrame extends StatelessWidget {
  const SubtitleSheetFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.scrollable = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;

  /// False when [child] scrolls on its own (a long list).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? subtitle = this.subtitle;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Insets.xxs),
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Insets.md),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.xl,
                        0,
                        Insets.xl,
                        Insets.lg,
                      ),
                      child: child,
                    )
                  : child,
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.xl,
                  Insets.sm,
                  Insets.xl,
                  Insets.lg,
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// An error line inside a sheet (a SnackBar would show behind it).
class SheetErrorText extends StatelessWidget {
  const SheetErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Row(
        spacing: Insets.sm,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.error,
          ),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small label above a group of chips.
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A 16 px spinner for a busy button.
class SmallSpinner extends StatelessWidget {
  const SmallSpinner({this.color, super.key});

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
}
