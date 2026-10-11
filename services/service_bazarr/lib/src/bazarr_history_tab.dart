import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import 'history/bazarr_history_list.dart';

/// The History tab: movie and episode subtitle activity merged newest first,
/// grouped by day and paged as it scrolls (see [BazarrHistoryList]).
class BazarrHistoryTab extends StatelessWidget {
  const BazarrHistoryTab({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context) => BazarrHistoryList(instance: instance);
}
