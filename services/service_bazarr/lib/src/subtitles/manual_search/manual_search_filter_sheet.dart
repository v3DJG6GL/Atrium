import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import 'manual_search_helpers.dart';

/// Opens the "Filter & sort subtitles" sheet. Every change applies at once
/// through [onLanguage] and [onSort].
Future<void> showManualSearchFilterSheet(
  BuildContext context, {
  required int total,
  required List<LanguageCount> languages,
  required String language,
  required ManualSearchSort sort,
  required ValueChanged<String> onLanguage,
  required ValueChanged<ManualSearchSort> onSort,
}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (BuildContext context) => ManualSearchFilterSheet(
        total: total,
        languages: languages,
        language: language,
        sort: sort,
        onLanguage: onLanguage,
        onSort: onSort,
      ),
    );

/// Language filter chips and the sort toggle of the manual search.
class ManualSearchFilterSheet extends StatefulWidget {
  const ManualSearchFilterSheet({
    required this.total,
    required this.languages,
    required this.language,
    required this.sort,
    required this.onLanguage,
    required this.onSort,
    super.key,
  });

  /// Number of results before filtering.
  final int total;
  final List<LanguageCount> languages;
  final String language;
  final ManualSearchSort sort;
  final ValueChanged<String> onLanguage;
  final ValueChanged<ManualSearchSort> onSort;

  @override
  State<ManualSearchFilterSheet> createState() =>
      _ManualSearchFilterSheetState();
}

class _ManualSearchFilterSheetState extends State<ManualSearchFilterSheet> {
  late String _language = widget.language;
  late ManualSearchSort _sort = widget.sort;

  void _setLanguage(String language) {
    setState(() => _language = language);
    widget.onLanguage(language);
  }

  void _setSort(ManualSearchSort sort) {
    setState(() => _sort = sort);
    widget.onSort(sort);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? section = theme.textTheme.labelLarge
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          0,
          Insets.lg,
          Insets.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Filter & sort subtitles', style: theme.textTheme.titleLarge),
            const SizedBox(height: Insets.lg),
            Text('Language', style: section),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: <Widget>[
                ChoiceChip(
                  label: Text('All languages (${widget.total})'),
                  selected: _language == allLanguages,
                  onSelected: (_) => _setLanguage(allLanguages),
                ),
                for (final LanguageCount l in widget.languages)
                  ChoiceChip(
                    label: Text('${l.name} (${l.count})'),
                    selected: _language == l.language,
                    onSelected: (_) => _setLanguage(l.language),
                  ),
              ],
            ),
            const SizedBox(height: Insets.xl),
            Text('Sort', style: section),
            const SizedBox(height: Insets.sm),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ManualSearchSort>(
                segments: <ButtonSegment<ManualSearchSort>>[
                  for (final ManualSearchSort s in ManualSearchSort.values)
                    ButtonSegment<ManualSearchSort>(
                      value: s,
                      label: Text(s.label),
                    ),
                ],
                selected: <ManualSearchSort>{_sort},
                onSelectionChanged: (Set<ManualSearchSort> s) =>
                    _setSort(s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
