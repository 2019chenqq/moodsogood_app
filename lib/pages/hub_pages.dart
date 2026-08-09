import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/main_drawer.dart';
import '../ai/innera_ai_home_page.dart';
import '../daily/daily_check_in_page.dart';
import '../daily/daily_record_history.dart';
import '../daily/quick_record_home_card.dart';
import '../daily/body_measurement_record_page.dart';
import '../daily/sleep_record_page.dart';
import '../daily/weekly_record_repository.dart';
import '../daily/weekly_review_page.dart';
import '../models/weekly_record.dart';
import '../diary/diary_home_page.dart';
import '../meds/medication_home_page.dart';
import '../meds/medication_checkin_page.dart';
import '../community/community_home_page.dart';
import '../analytics_service.dart';
import '../constants/healing_design_system.dart';
import '../settings_page.dart';
import 'feedback_page.dart';
import '../follow_up/pages/follow_up_hub_page.dart';
import 'life_overview_page.dart';
import 'profile_page.dart';
import 'trend_review_hub_page.dart';

class HomeHubPage extends StatelessWidget {
  const HomeHubPage({super.key});

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
        title: const Text('首頁'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const QuickRecordHomeCard(),
            const SizedBox(height: 16),
            _RecordEntryCard(
              icon: Icons.edit_note_rounded,
              title: '紀錄系統',
              subtitle: '記錄每日狀態、日記、用藥與服藥情形',
              color: const Color.fromARGB(255, 129, 199, 132),
              onTap: () => _push(context, const RecordHubPage()),
              actionLabel: '開始記錄',
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.auto_awesome_rounded,
              title: '心域 AI',
              subtitle: '說說現在的狀態，或讓 AI 協助回顧近期紀錄',
              color: const Color(0xFF7DB7D8),
              onTap: () => _push(context, const InneraAiHomePage()),
              actionLabel: '開始對話',
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.calendar_month_outlined,
              title: '生活軌跡',
              subtitle: '從日曆回顧每天的紀錄與生活變化',
              color: const Color(0xFF5C9BD5),
              onTap: () => _push(context, const LifeOverviewPage()),
              actionLabel: '查看軌跡',
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.medical_information_outlined,
              title: '回診專區',
              subtitle: '整理調藥、醫囑、待討論問題與近期趨勢',
              color: const Color(0xFF26A69A),
              onTap: () => _push(context, const FollowUpHubPage()),
              actionLabel: '前往專區',
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.person_outline_rounded,
              title: '個人資料',
              subtitle: '查看與更新個人基本資料',
              color: const Color(0xFF9575CD),
              onTap: () => _push(context, const ProfilePage()),
              actionLabel: '查看資料',
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.settings_outlined,
              title: '設定',
              subtitle: '調整提醒、外觀、安全與其他使用偏好',
              color: const Color(0xFF78909C),
              onTap: () => _push(context, const SettingsPage()),
              actionLabel: '開啟設定',
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.help_outline_rounded,
              title: '幫助與回饋',
              subtitle: '取得使用協助，或告訴我們你的建議',
              color: const Color(0xFFFFA25B),
              onTap: () => _push(context, const FeedbackPage()),
              actionLabel: '取得協助',
            ),
          ],
        ),
      ),
    );
  }
}

class RecordHubPage extends StatefulWidget {
  const RecordHubPage({super.key});

  @override
  State<RecordHubPage> createState() => _RecordHubPageState();
}

class _RecordHubPageState extends State<RecordHubPage> {
  Future<WeeklyRecord?>? _weeklyRecordFuture;

  @override
  void initState() {
    super.initState();
    _refreshWeeklyRecord();
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  DateTime _currentWeekStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  void _refreshWeeklyRecord() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _weeklyRecordFuture = uid == null
        ? Future<WeeklyRecord?>.value(null)
        : WeeklyRecordRepository().getWeeklyRecord(
            userId: uid,
            weekStart: _currentWeekStart(),
          );
  }

  Future<void> _openWeeklyReview() async {
    final start = _currentWeekStart();
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WeeklyReviewPage(
          weekStart: start,
          weekEnd: start.add(const Duration(days: 6)),
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(_refreshWeeklyRecord);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已留下這週的狀態紀錄')),
      );
    }
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
        title: const Text('紀錄系統'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const QuickRecordHomeCard(),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.fact_check_outlined,
              title: '每日 Check-in',
              subtitle: '用兩個評分快速建立今天的基準',
              color: HealingDesignSystem.primaryBlue,
              onTap: () => _push(context, const DailyCheckInPage()),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.bedtime_outlined,
              title: '睡眠紀錄',
              subtitle: '記錄睡眠時間、品質與睡眠狀況',
              color: const Color(0xFF7986CB),
              onTap: () => _push(context, const SleepRecordPage()),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.monitor_weight_outlined,
              title: '身體測量',
              subtitle: '記錄體重、體脂與腰圍',
              color: const Color(0xFF4DB6AC),
              onTap: () => _push(context, const BodyMeasurementRecordPage()),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.book_outlined,
              title: '日記',
              subtitle: '寫下今天的感受與生活片段',
              color: const Color.fromARGB(255, 255, 195, 113),
              onTap: () => _push(context, const DiaryHomePage()),
            ),
            const SizedBox(height: 12),
            FutureBuilder<WeeklyRecord?>(
              future: _weeklyRecordFuture,
              builder: (context, snapshot) {
                final record = snapshot.data;
                return _RecordEntryCard(
                  icon: record == null
                      ? Icons.calendar_view_week_rounded
                      : Icons.check_circle_outline_rounded,
                  title: '每週狀態紀錄',
                  subtitle: record == null
                      ? '3 分鐘留下一週的整體狀態，不用補登每天'
                      : '本週已完成：${record.overallState} / 5 分',
                  color: const Color(0xFF7DB7D8),
                  onTap: record == null
                      ? _openWeeklyReview
                      : () => _push(
                            context,
                            const DailyRecordHistory(initialTab: 0),
                          ),
                  actionLabel: record == null ? '開始本週回顧' : '查看本週摘要',
                );
              },
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.history,
              title: '紀錄歷程',
              subtitle: '查看每日紀錄與每週摘要',
              color: const Color.fromARGB(255, 144, 202, 249),
              onTap: () =>
                  _push(context, const DailyRecordHistory(initialTab: 0)),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              icon: Icons.insights_rounded,
              title: '趨勢回顧',
              subtitle: '睡眠、情緒與症狀變化集中查看',
              color: const Color(0xFF5C9BD5),
              onTap: () => _push(context, const TrendReviewHubPage()),
              actionLabel: '查看趨勢',
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
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final String? actionLabel;

  @override
  State<_RecordEntryCard> createState() => _RecordEntryCardState();
}

class _RecordEntryCardState extends State<_RecordEntryCard>
    with SingleTickerProviderStateMixin {
  static const double _cardHeight = 120;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('hub_pages');
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
        child: SizedBox(
          height: _cardHeight,
          child: Card(
            elevation: 4,
            shadowColor: widget.color.withValues(alpha: 0.4),
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
                    widget.color.withValues(alpha: 0.15),
                    widget.color.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.color.withValues(alpha: 0.3),
                            widget.color.withValues(alpha: 0.15),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.2),
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.subtitle,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                      height: 1.35,
                                    ),
                          ),
                          if (widget.actionLabel != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              widget.actionLabel!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: widget.color,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color.withValues(alpha: 0.1),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios,
                        color: widget.color,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
