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

/// Persistent navigation shell. Content routes stay inside the bottom bar.
class HomeShell extends m.StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0, this.testPages})
      : assert(initialIndex >= 0 && initialIndex < 4),
        assert(testPages == null || testPages.length == 4);

  final int initialIndex;
  @m.visibleForTesting
  final List<m.Widget>? testPages;

  static bool selectDestination(m.BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_HomeShellState>();
    if (state == null) return false;
    state._selectDestination(index);
    return true;
  }

  @override
  m.State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends m.State<HomeShell> {
  late int _index = widget.initialIndex;
  final _navigatorKey = m.GlobalKey<m.NavigatorState>();
  final _selectionRevision = m.ValueNotifier<int>(0);

  @override
  void dispose() {
    _selectionRevision.dispose();
    super.dispose();
  }

  int _todayRevision = 0;

  void _selectDestination(int value) {
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _todayRevision = homeShellTodayRevisionAfterSelection(
        currentIndex: _index,
        selectedIndex: value,
        currentRevision: _todayRevision,
      );
      _index = value;
    });
    _selectionRevision.value++;
  }

  @override
  m.Widget build(m.BuildContext context) {
    return m.Scaffold(
      // The inner page owns keyboard insets; avoid shrinking its Scaffold twice.
      resizeToAvoidBottomInset: false,
      body: m.NavigatorPopHandler<Object?>(
        onPopWithResult: (result) => _navigatorKey.currentState!.pop(result),
        child: m.Navigator(
          key: _navigatorKey,
          onGenerateRoute: (_) => m.MaterialPageRoute<void>(
            builder: (_) => m.ValueListenableBuilder<int>(
              valueListenable: _selectionRevision,
              builder: (context, revision, child) => m.IndexedStack(
                index: _index,
                children: widget.testPages ??
                    <m.Widget>[
                      HomeHubPage(key: m.ValueKey('today-$_todayRevision')),
                      const InneraAiHomePage(),
                      const TrendReviewHubPage(),
                      const ProfilePage(),
                    ],
              ),
            ),
          ),
        ),
      ),
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
