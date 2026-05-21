import 'package:flutter/material.dart';
import '../widgets/main_drawer.dart';
import '../daily/daily_record_screen.dart';
import '../daily/daily_record_history.dart';
import '../diary/diary_home_page.dart';
import '../meds/medication_home_page.dart';
import '../meds/medication_checkin_page.dart';
import '../community/community_home_page.dart';

class RecordHubPage extends StatelessWidget {
  const RecordHubPage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: '選單',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('紀錄'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.05),
              Theme.of(context).colorScheme.secondary.withOpacity(0.03),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _RecordEntryCard(
              icon: Icons.book_outlined,
              title: '日記',
              subtitle: '獨立日記頁與歷史日記',
              color: const Color.fromARGB(255, 255, 195, 113),
              onTap: () => _push(context, const DiaryHomePage()),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.edit_note,
              title: '紀錄',
              subtitle: '開始填寫今日紀錄',
              color: const Color.fromARGB(255, 129, 199, 132),
              onTap: () => _push(context, const DailyRecordScreen()),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.history,
              title: '紀錄歷程',
              subtitle: '列表與週報',
              color: const Color.fromARGB(255, 144, 202, 249),
              onTap: () =>
                  _push(context, const DailyRecordHistory(initialTab: 0)),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.medication_outlined,
              title: '藥物紀錄',
              subtitle: '管理用藥與回診調整',
              color: const Color.fromARGB(255, 206, 147, 216),
              onTap: () => _push(context, const MedicationHomePage()),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.task_alt,
              title: '服藥打卡',
              subtitle: '按時勾選今日服藥狀態',
              color: const Color.fromARGB(255, 255, 167, 167),
              onTap: () => _push(context, const MedicationCheckinPage()),
            ),
          ],
        ),
      ),
    );
  }
}

class DiscussionHubPage extends StatelessWidget {
  const DiscussionHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommunityHomePage();
  }
}

class RelaxHubPage extends StatelessWidget {
  const RelaxHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      title: '放鬆區',
      subtitle: '放鬆內容準備中',
      icon: Icons.spa_outlined,
    );
  }
}

class TreeholePostOfficePage extends StatelessWidget {
  const TreeholePostOfficePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      title: '樹洞郵局',
      subtitle: '樹洞郵局功能準備中',
      icon: Icons.mail_outline,
    );
  }
}

class LocationsHubPage extends StatelessWidget {
  const LocationsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      title: '據點',
      subtitle: '據點資訊整理中',
      icon: Icons.place_outlined,
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: '選單',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: color),
              const SizedBox(height: 16),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordEntryCard extends StatefulWidget {
  const _RecordEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_RecordEntryCard> createState() => _RecordEntryCardState();
}

class _RecordEntryCardState extends State<_RecordEntryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Card(
          elevation: 4,
          shadowColor: widget.color.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.color.withOpacity(0.15),
                  widget.color.withOpacity(0.05),
                ],
              ),
              border: Border.all(
                color: widget.color.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color.withOpacity(0.3),
                      widget.color.withOpacity(0.15),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  color: widget.color,
                  size: 28,
                ),
              ),
              title: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
              trailing: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(0.1),
                ),
                child: Icon(
                  Icons.arrow_forward_ios,
                  color: widget.color,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}