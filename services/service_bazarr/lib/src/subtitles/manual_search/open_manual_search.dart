import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/widgets.dart';

import '../bazarr_subtitle_params.dart';
import 'bazarr_manual_search_screen.dart';

/// Opens the manual subtitle search for [target] on [bazarr].
///
/// [title] names what is searched, e.g. a movie title or "S01E02".
Future<void> openBazarrManualSearch(
  BuildContext context, {
  required Instance bazarr,
  required SubtitleTarget target,
  required String title,
}) =>
    pushScreen<void>(
      context,
      BazarrManualSearchScreen(bazarr: bazarr, target: target, title: title),
    );
