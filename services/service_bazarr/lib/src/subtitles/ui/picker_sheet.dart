import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../subtitle_ui_text.dart';
import 'subtitle_sheet.dart';

/// Past this many options the picker gets a search field.
const int pickerSearchThreshold = 12;

/// A single-select list picker in a sheet: one row per option, a tick on
/// the selected one, a search field past [pickerSearchThreshold] options.
/// Pops with the picked value.
class PickerSheet<T> extends StatefulWidget {
  const PickerSheet({
    required this.title,
    required this.options,
    this.selected = const <Never>{},
    this.loading = false,
    this.searchable,
    this.emptyTitle = 'Nothing to pick',
    this.emptyMessage,
    super.key,
  });

  final String title;
  final List<PickerOption<T>> options;

  /// Values shown ticked.
  final Set<T> selected;

  /// Shows a spinner instead of the options.
  final bool loading;

  /// Null: searchable past [pickerSearchThreshold] options.
  final bool? searchable;
  final String emptyTitle;
  final String? emptyMessage;

  @override
  State<PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool searchable =
        widget.searchable ?? widget.options.length > pickerSearchThreshold;
    final String q = _query.trim().toLowerCase();
    final List<PickerOption<T>> shown = q.isEmpty
        ? widget.options
        : widget.options
            .where((PickerOption<T> o) => o.label.toLowerCase().contains(q))
            .toList(growable: false);

    final Widget body;
    if (widget.loading) {
      body = const Padding(
        padding: EdgeInsets.all(Insets.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (widget.options.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.xl,
          Insets.sm,
          Insets.xl,
          Insets.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: Insets.md),
            Text(
              widget.emptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (widget.emptyMessage != null) ...<Widget>[
              const SizedBox(height: Insets.xs),
              Text(
                widget.emptyMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Insets.sm),
        itemCount: shown.length,
        itemBuilder: (BuildContext context, int i) {
          final PickerOption<T> o = shown[i];
          final bool selected = widget.selected.contains(o.value);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Insets.xl),
            title: Text(o.label),
            subtitle: o.description == null ? null : Text(o.description!),
            selected: selected,
            trailing: selected ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(context).pop(o.value),
          );
        },
      );
    }

    return SubtitleSheetFrame(
      title: widget.title,
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (searchable && !widget.loading && widget.options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.xl,
                0,
                Insets.xl,
                Insets.sm,
              ),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search',
                  isDense: true,
                ),
                onChanged: (String v) => setState(() => _query = v),
              ),
            ),
          Flexible(child: body),
        ],
      ),
    );
  }
}
