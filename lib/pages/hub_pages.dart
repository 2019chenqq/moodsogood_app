import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/main_drawer.dart';
import '../daily/daily_check_in_page.dart';
import '../daily/daily_record_history.dart';
import '../daily/period_calendar_page.dart';
import '../daily/period_feature_visibility_service.dart';
import '../daily/quick_record_home_card.dart';
import '../daily/body_measurement_record_page.dart';
import '../daily/sleep_record_page.dart';
import '../diary/diary_home_page.dart';
import '../meds/medication_home_page.dart';
import '../meds/medication_checkin_page.dart';
import '../meds/medication_subjective_pending_service.dart';
import '../meds/medication_subjective_reminder_service.dart';
import '../meds/medication_subjective_response_page.dart';
import '../community/community_home_page.dart';
import '../analytics_service.dart';
import '../constants/healing_design_system.dart';
import '../follow_up/pages/follow_up_hub_page.dart';
import '../follow_up/services/follow_up_service.dart';
import 'life_overview_page.dart';
import 'trend_review_hub_page.dart';

class HomeHubPage extends StatefulWidget {
  const HomeHubPage({super.key});

  @override
  State<HomeHubPage> createState() => _HomeHubPageState();
}

class _HomeHubPageState extends State<HomeHubPage> with WidgetsBindingObserver {
  final _pendingService = MedicationSubjectivePendingService();
  List<MedicationSubjectivePendingResponse> _pendingResponses = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSubjectiveTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSubjectiveTracking();
    }
  }

  Future<void> _refreshSubjectiveTracking() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final pending = await _pendingService.load(uid: uid);
      await MedicationSubjectiveReminderService().syncForCurrentUser(uid: uid);
      if (mounted) setState(() => _pendingResponses = pending);
    } catch (error, stackTrace) {
      debugPrint('Medication subjective pending scan deferred: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _openPendingResponse(
    MedicationSubjectivePendingResponse pending,
  ) async {
    final cycle = pending.cycle;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationSubjectiveResponsePage(
          medicationId: cycle.medicationId,
          medicationName:
              pending.cycles.length == 1 ? cycle.medicationName : '本次用藥調整',
          changeRecordId: cycle.changeRecordId,
          changeDate: cycle.changeDate,
          adjustmentSummary: pending.adjustmentSummary,
          followUpDay: pending.followUpDay,
        ),
      ),
    );
    await _refreshSubjectiveTracking();
  }

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
            if (_pendingResponses.isNotEmpty) ...[
              _RecordEntryCard(
                icon: Icons.rate_review_outlined,
                title: '主觀用藥感受待回報',
                subtitle:
                    '最近一次用藥調整已滿 ${_pendingResponses.first.calculatedDay} 天，記錄一下這幾天的整體感受',
                color: const Color(0xFF7DB7D8),
                onTap: () => _openPendingResponse(_pendingResponses.first),
                actionLabel: '開始填寫',
              ),
              const SizedBox(height: 16),
            ],
            FutureBuilder<List<FollowUpAppointment>>(
              future: FollowUpService.getAppointments(),
              builder: (context, snapshot) {
                final hasAppointmentToday = (snapshot.data ?? const [])
                    .any((appointment) => appointment.daysUntil == 0);
                if (!hasAppointmentToday) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _RecordEntryCard(
                    icon: Icons.event_available_outlined,
                    title: '今天是回診日',
                    subtitle: '回診後記得填寫下一次回診日期',
                    color: const Color(0xFF7DB7D8),
                    onTap: () => _push(
                      context,
                      const FollowUpHubPage(promptAddAppointment: true),
                    ),
                    actionLabel: '填寫下次日期',
                  ),
                );
              },
            ),
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
              icon: Icons.calendar_month_outlined,
              title: '生活軌跡',
              subtitle: '從日曆回顧每天的紀錄與生活變化',
              color: const Color(0xFF5C9BD5),
              onTap: () => _push(context, const LifeOverviewPage()),
              actionLabel: '查看軌跡',
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

class _RecordHubPageState extends State<RecordHubPage>
    with WidgetsBindingObserver {
  final _pendingService = MedicationSubjectivePendingService();
  MedicationSubjectivePendingResponse? _pendingResponse;
  bool _showsPeriodFeatures = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSubjectiveTracking();
    _refreshPeriodFeatureVisibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSubjectiveTracking();
      _refreshPeriodFeatureVisibility();
    }
  }

  Future<void> _refreshPeriodFeatureVisibility() async {
    final visible =
        await PeriodFeatureVisibilityService().shouldShowForCurrentUser();
    if (mounted) setState(() => _showsPeriodFeatures = visible);
  }

  Future<void> _refreshSubjectiveTracking() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final pending = await _pendingService.load(uid: uid);
      if (mounted) {
        setState(
            () => _pendingResponse = pending.isEmpty ? null : pending.first);
      }
    } catch (error, stackTrace) {
      debugPrint('Record hub subjective pending scan deferred: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _openPendingResponse() async {
    final pending = _pendingResponse;
    if (pending == null) return;
    final cycle = pending.cycle;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationSubjectiveResponsePage(
          medicationId: cycle.medicationId,
          medicationName:
              pending.cycles.length == 1 ? cycle.medicationName : '本次用藥調整',
          changeRecordId: cycle.changeRecordId,
          changeDate: cycle.changeDate,
          adjustmentSummary: pending.adjustmentSummary,
          followUpDay: pending.followUpDay,
        ),
      ),
    );
    await _refreshSubjectiveTracking();
  }

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
            if (_pendingResponse case final pending?) ...[
              _RecordEntryCard(
                icon: Icons.rate_review_outlined,
                title: '主觀用藥感受待回報',
                subtitle: '最近一次用藥調整已滿 ${pending.calculatedDay} 天，記錄一下這幾天的整體感受',
                color: const Color(0xFF7DB7D8),
                onTap: _openPendingResponse,
                actionLabel: '開始填寫',
              ),
              const SizedBox(height: 12),
            ],
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
            _RecordEntryCard(
              icon: Icons.history,
              title: '紀錄歷程',
              subtitle: '查看每日紀錄與狀態摘要',
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
            if (_showsPeriodFeatures) ...[
              _RecordEntryCard(
                icon: Icons.water_drop_outlined,
                title: '生理期月曆',
                subtitle: '查看月經日期、平均週期與下次預估',
                color: const Color(0xFFE78EAA),
                onTap: () => _push(
                  context,
                  const PeriodCalendarPage(),
                ),
                actionLabel: '查看月曆',
              ),
              const SizedBox(height: 12),
            ],
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 125,
          ),
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
                        mainAxisSize: MainAxisSize.min,
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
