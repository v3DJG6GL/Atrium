import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import 'bazarr_blacklist_tab.dart';
import 'bazarr_history_tab.dart';
import 'bazarr_settings_tab.dart';
import 'bazarr_system_tab.dart';
import 'library/bazarr_library_tab.dart';

/// Bazarr's per-instance UI: tabbed Library / History / Blacklist / System /
/// Settings. Library lists every movie and series with its audio and
/// subtitle languages (its Missing filter replaces the old Wanted lists);
/// History logs subtitle activity; Blacklist manages blocked subtitles;
/// System surfaces status, providers, tasks, backups, logs.
class BazarrHome extends StatefulWidget {
  const BazarrHome({required this.instance, super.key});

  final Instance instance;

  @override
  State<BazarrHome> createState() => _BazarrHomeState();
}

class _BazarrHomeState extends State<BazarrHome>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const <Widget>[
              Tab(text: 'Library'),
              Tab(text: 'History'),
              Tab(text: 'Blacklist'),
              Tab(text: 'System'),
              Tab(text: 'Settings'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: <Widget>[
                BazarrLibraryTab(instance: widget.instance),
                BazarrHistoryTab(instance: widget.instance),
                BazarrBlacklistTab(instance: widget.instance),
                BazarrSystemTab(instance: widget.instance),
                BazarrSettingsTab(instance: widget.instance),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
