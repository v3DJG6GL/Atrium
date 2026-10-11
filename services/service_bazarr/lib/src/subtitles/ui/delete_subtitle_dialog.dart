import 'package:core_subtitles/core_subtitles.dart';
import 'package:flutter/material.dart';

/// "Delete the German forced subtitle file? …".
String deleteSubtitleMessage(SubtitleRow row) =>
    'Delete the ${row.name}${row.forced ? ' forced' : ''} subtitle file? '
    'If the language profile asks for it, Bazarr searches for it again.';

/// Asks before deleting [row]'s file; true when confirmed.
Future<bool> confirmDeleteSubtitle(
  BuildContext context,
  SubtitleRow row,
) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) {
      final ColorScheme scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Delete subtitle'),
        content: Text(deleteSubtitleMessage(row)),
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
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}
