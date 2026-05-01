import 'package:flutter/material.dart' as m;

import 'pages/hub_pages.dart';

/// Minimal app shell.
///
/// We keep this wrapper to avoid touching existing entrypoints in main.dart,
/// while delegating drawer/navigation concerns to pages that already use MainDrawer.
class HomeShell extends m.StatelessWidget {
  const HomeShell({super.key});

  @override
  m.Widget build(m.BuildContext context) {
    return const RecordHubPage();
  }
}
