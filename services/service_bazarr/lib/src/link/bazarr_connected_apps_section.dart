import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bazarr_link.dart';
import 'bazarr_link_providers.dart';

/// "Connected apps" on a Bazarr's instance form: which Radarr and Sonarr this
/// Bazarr serves subtitles for (model: `bazarr_link.dart`).
///
/// Each row is detected from Bazarr's own settings unless the user picks
/// something else. Picking the detected instance stores "automatic" rather
/// than a fixed id, so the badge always tells the truth: Detected means it
/// follows Bazarr's configuration, Set by you means it doesn't. Picks are
/// written straight away, not on the form's Save.
///
/// Renders nothing unless [bazarrId] is a saved Bazarr of the active profile.
/// Brings no top spacing of its own, like the form's other section titles.
class BazarrConnectedAppsSection extends ConsumerWidget {
  const BazarrConnectedAppsSection({required this.bazarrId, super.key});

  final String bazarrId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Instance? bazarr = ref.watch(instanceByIdProvider(bazarrId));
    if (bazarr == null || bazarr.kind != ServiceKind.bazarr) {
      return const SizedBox.shrink();
    }
    final BazarrLinkStatus status =
        ref.watch(bazarrLinkStatusProvider(bazarrId));
    final ThemeData theme = Theme.of(context);
    final TextStyle? note = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final String addresses = <String?>[
      status.detection?.radarr.address,
      status.detection?.sonarr.address,
    ].nonNulls.where((String a) => a.isNotEmpty).join(' and ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Connected apps', style: theme.textTheme.titleSmall),
        const SizedBox(height: Insets.xs),
        Text(
          'Subtitles from this Bazarr show on the movie and series pages of '
          'these instances.',
          style: note,
        ),
        const SizedBox(height: Insets.sm),
        for (final ServiceKind kind in bazarrArrKinds)
          _LinkTile(bazarr: bazarr, kind: kind),
        const SizedBox(height: Insets.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                status.detectError != null
                    ? "Couldn't read Bazarr's settings. Check the connection "
                        'above.'
                    : addresses.isNotEmpty
                        ? 'Bazarr reaches $addresses'
                        : status.detecting
                            ? "Reading Bazarr's settings…"
                            : 'Bazarr has no Radarr or Sonarr set up.',
                style: note,
              ),
            ),
            const SizedBox(width: Insets.md),
            OutlinedButton.icon(
              onPressed:
                  status.detecting ? null : () => _detectAgain(context, ref),
              icon: status.detecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.manage_search_outlined),
              label: Text(status.detecting ? 'Detecting…' : 'Detect again'),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        Text(
          "Detection reads Bazarr's settings and compares the API key and "
          'address it uses for each app with the instances in this profile. '
          'Only the result is kept. Nothing else from those settings is used '
          'or stored.',
          style: note,
        ),
      ],
    );
  }

  // Re-reads Bazarr's settings only; the user's choices stay.
  Future<void> _detectAgain(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    try {
      final ArrLinkDetection result = await redetectBazarrLinks(ref, bazarrId);
      if (!context.mounted) {
        return;
      }
      final List<Instance> instances = ref.read(activeInstancesProvider);
      final List<String> names = <String>[
        for (final ServiceKind kind in bazarrArrKinds)
          if (instances.firstWhereOrNull(
            (Instance i) => i.id == result.of(kind).instanceId,
          )
              case final Instance found)
            found.name,
      ];
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            names.isNotEmpty
                ? 'Found ${names.join(' and ')}'
                : "Bazarr isn't connected to any Radarr or Sonarr set up here",
          ),
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text("Couldn't read Bazarr's settings")),
      );
    }
  }
}

/// Everything one row and its picker show, from the providers.
class _RowModel {
  _RowModel({
    required this.bazarr,
    required this.kind,
    required this.status,
    required this.arrs,
    required this.bazarrs,
    required this.entries,
  })  : state = status.of(kind),
        stored = bazarr.links[kind.name],
        detectedId = status.detection?.of(kind).instanceId {
    row = linkRowOf(
      bazarrId: bazarr.id,
      state: state,
      stored: stored,
      entries: entries,
    );
  }

  factory _RowModel.watch(WidgetRef ref, Instance bazarr, ServiceKind kind) {
    final List<Instance> instances = ref.watch(activeInstancesProvider);
    return _RowModel(
      bazarr: bazarr,
      kind: kind,
      status: ref.watch(bazarrLinkStatusProvider(bazarr.id)),
      arrs: instances
          .where((Instance i) => i.kind == kind)
          .toList(growable: false),
      bazarrs: instances
          .where((Instance i) => i.kind == ServiceKind.bazarr)
          .toList(growable: false),
      entries: ref.watch(bazarrLinkEntriesProvider(kind)),
    );
  }

  final Instance bazarr;
  final ServiceKind kind;
  final BazarrLinkStatus status;
  final List<Instance> arrs;
  final List<Instance> bazarrs;
  final List<BazarrLinkEntry> entries;
  final LinkState state;
  final String? stored;
  final String? detectedId;
  late final LinkRow row;

  String get label => kind.displayName;

  String get bazarrName =>
      bazarr.name.trim().isEmpty ? 'Bazarr' : bazarr.name.trim();

  String get title => '$label for $bazarrName';

  String? get address => status.detection?.of(kind).address;

  /// Why the row is not linked.
  String get notLinkedReason {
    if (row.outranked) {
      return row.outrankedByManual
          ? 'Another Bazarr has the detected instance set by hand'
          : 'Another Bazarr is connected to the detected instance too';
    }
    if (status.detection != null) {
      return 'Nothing detected';
    }
    return status.detectError != null
        ? "Couldn't read Bazarr's settings"
        : "Reading Bazarr's settings…";
  }

  /// The badge for [arrId], if any.
  String? badgeOf(String arrId) {
    if (state.how == LinkHow.manual && arrId == state.arrId) {
      return 'Set by you';
    }
    return arrId == detectedId ? 'Detected' : null;
  }

  /// Another Bazarr serving [arrId] (the one pages use), for the "moves the
  /// link" hint.
  String? ownerNameOf(String arrId) {
    final String? owner = bazarrForArr(arrId, entries);
    if (owner == null || owner == bazarr.id) {
      return null;
    }
    return bazarrs.firstWhereOrNull((Instance b) => b.id == owner)?.name;
  }

  String descriptionOf(String arrId) {
    if (arrId == detectedId) {
      return 'Same API key Bazarr uses for $label';
    }
    if (arrId == row.selected) {
      return 'Linked to $bazarrName';
    }
    final String? owner = ownerNameOf(arrId);
    return owner != null
        ? 'Linked to $owner. Picking it here moves the link.'
        : 'Not linked to any Bazarr';
  }
}

class _LinkTile extends ConsumerWidget {
  const _LinkTile({required this.bazarr, required this.kind});

  final Instance bazarr;
  final ServiceKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _RowModel model = _RowModel.watch(ref, bazarr, kind);
    final ThemeData theme = Theme.of(context);
    final String? selected = model.row.selected;

    final String choice;
    String? detail;
    String? badge;
    if (selected == null) {
      choice = 'Not linked';
      detail = model.notLinkedReason;
    } else if (selected == Instance.linkNone) {
      choice = 'None';
      detail = "Don't show subtitles on ${model.label} pages";
    } else if (model.state.how == LinkHow.stale) {
      choice = 'Unavailable instance';
      detail = 'Deleted or disabled. Pick another one, or None.';
    } else {
      choice =
          model.arrs.firstWhereOrNull((Instance a) => a.id == selected)?.name ??
              selected;
      badge = model.badgeOf(selected);
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ServiceVisuals.icon(kind),
        color: ServiceVisuals.accent(kind),
      ),
      title: Text(model.title),
      subtitle: Text(detail == null ? choice : '$choice\n$detail'),
      isThreeLine: detail != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (badge != null) _LinkBadge(label: badge),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (BuildContext sheetContext) =>
            _LinkPickerSheet(bazarrId: bazarr.id, kind: kind),
      ),
    );
  }
}

/// "Detected" (primary container) or "Set by you" (secondary container).
class _LinkBadge extends StatelessWidget {
  const _LinkBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool detected = label == 'Detected';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.xxs,
      ),
      decoration: BoxDecoration(
        color: detected ? colors.primaryContainer : colors.secondaryContainer,
        borderRadius: Radii.chip,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: detected
                  ? colors.onPrimaryContainer
                  : colors.onSecondaryContainer,
            ),
      ),
    );
  }
}

/// The picker for one row. Watches the live state, so a detection finishing
/// while it is open shows up.
class _LinkPickerSheet extends ConsumerWidget {
  const _LinkPickerSheet({required this.bazarrId, required this.kind});

  final String bazarrId;
  final ServiceKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Instance? bazarr = ref.watch(instanceByIdProvider(bazarrId));
    if (bazarr == null) {
      return const SizedBox.shrink();
    }
    final _RowModel model = _RowModel.watch(ref, bazarr, kind);
    final ThemeData theme = Theme.of(context);
    final String? selected = model.row.selected;
    final String? address = model.address;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: Insets.pageH,
              child: Text(model.title, style: theme.textTheme.titleMedium),
            ),
            if (address != null)
              Padding(
                padding: Insets.pageH,
                child: Text(
                  'Bazarr reaches $address',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: Insets.sm),
            if (selected == null)
              _PickOption(
                label: 'Not linked',
                description: model.notLinkedReason,
                selected: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            for (final Instance arr in model.arrs)
              _PickOption(
                label: arr.name,
                description: model.descriptionOf(arr.id),
                badge: model.badgeOf(arr.id),
                selected: arr.id == selected,
                onTap: () => _pick(context, ref, model, arr.id),
              ),
            if (model.state.how == LinkHow.stale && model.stored != null)
              _PickOption(
                label: 'Unavailable instance',
                description: 'Deleted or disabled. Pick another one, or None.',
                selected: selected == model.stored,
                onTap: () => Navigator.of(context).pop(),
              ),
            _PickOption(
              label: 'None',
              description: "Don't show subtitles on ${model.label} pages",
              selected: selected == Instance.linkNone,
              onTap: () => _pick(context, ref, model, Instance.linkNone),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    _RowModel model,
    String pick,
  ) async {
    // Everything the write needs is read before the sheet closes.
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    final Map<String, String?> plan = planLinkPick(
      kind: kind,
      bazarrId: bazarrId,
      pick: pick,
      bazarrs: model.bazarrs,
      state: model.state,
      detectedId: model.detectedId,
      entries: model.entries,
    );
    final String? profileId = ref.read(activeProfileProvider)?.id;
    final ProfileListController profiles =
        ref.read(profileListProvider.notifier);
    Navigator.of(context).pop();
    if (plan.isEmpty || profileId == null) {
      return;
    }

    final List<Instance> changed = <Instance>[
      for (final Instance b in model.bazarrs)
        if (plan.containsKey(b.id)) withLink(b, kind, plan[b.id]),
    ];
    try {
      await profiles.upsertInstances(profileId, changed);
      final String? arrName =
          model.arrs.firstWhereOrNull((Instance a) => a.id == pick)?.name;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            pick == Instance.linkNone
                ? '${model.label} unlinked'
                : 'Linked ${arrName ?? model.label}',
          ),
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text("Couldn't save the link")),
      );
    }
  }
}

class _PickOption extends StatelessWidget {
  const _PickOption({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final String description;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String? badge = this.badge;
    return ListTile(
      selected: selected,
      contentPadding: Insets.pageH,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      title: Text(label),
      subtitle: Text(description),
      trailing: badge == null ? null : _LinkBadge(label: badge),
      onTap: onTap,
    );
  }
}
