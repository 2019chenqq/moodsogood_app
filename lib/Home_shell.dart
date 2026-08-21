import 'package:flutter/material.dart' as m;

import 'ai/innera_ai_home_page.dart';
import 'pages/hub_pages.dart';
import 'pages/profile_page.dart';
import 'pages/trend_review_hub_page.dart';

@m.visibleForTesting
int homeShellTodayRevisionAfterSelection({
  required int currentIndex,
  required int selectedIndex,
  required int currentRevision,
}) =>
    selectedIndex == 0 && currentIndex != 0
        ? currentRevision + 1
        : currentRevision;

/// Minimal app shell.
///
/// We keep this wrapper to avoid touching existing entrypoints in main.dart,
/// while delegating drawer/navigation concerns to pages that already use MainDrawer.
class HomeShell extends m.StatefulWidget {
  const HomeShell({super.key});

  @override
  m.State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends m.State<HomeShell> {
  int _index = 0;
  int _todayRevision = 0;

  void _selectDestination(int value) {
    setState(() {
      _todayRevision = homeShellTodayRevisionAfterSelection(
        currentIndex: _index,
        selectedIndex: value,
        currentRevision: _todayRevision,
      );
      _index = value;
    });
  }

  @override
  m.Widget build(m.BuildContext context) {
    final pages = <m.Widget>[
      HomeHubPage(key: m.ValueKey('today-$_todayRevision')),
      const InneraAiHomePage(),
      const TrendReviewHubPage(),
      const ProfilePage(),
    ];
    return m.Scaffold(
      body: m.IndexedStack(index: _index, children: pages),
      bottomNavigationBar: m.NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectDestination,
        destinations: const [
          m.NavigationDestination(
            icon: m.Icon(m.Icons.today_outlined),
            selectedIcon: m.Icon(m.Icons.today_rounded),
            label: '今天',
          ),
          m.NavigationDestination(
            icon: m.Icon(m.Icons.chat_bubble_outline_rounded),
            selectedIcon: m.Icon(m.Icons.chat_bubble_rounded),
            label: '聊聊',
          ),
          m.NavigationDestination(
            icon: m.Icon(m.Icons.insights_outlined),
            selectedIcon: m.Icon(m.Icons.insights_rounded),
            label: '回顧',
          ),
          m.NavigationDestination(
            icon: m.Icon(m.Icons.person_outline_rounded),
            selectedIcon: m.Icon(m.Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
