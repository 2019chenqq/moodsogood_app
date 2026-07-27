import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../widgets/main_drawer.dart';
import '../ai/innera_ai_home_page.dart';
import '../daily/daily_record_screen.dart';
import '../daily/daily_record_history.dart';
import '../diary/diary_home_page.dart';
import '../meds/medication_home_page.dart';
import '../meds/medication_checkin_page.dart';
import '../community/community_home_page.dart';
import '../analytics_service.dart';
import '../tutorial/app_tutorial_service.dart';
import '../settings_page.dart';
import 'feedback_page.dart';
import 'follow_up_hub_page.dart';
import 'life_overview_page.dart';
import 'profile_page.dart';

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
              icon: Icons.edit_note_rounded,
              title: '紀錄系統',
              subtitle: '記錄每日狀態、日記、用藥與服藥情形',
              color: const Color.fromARGB(255, 129, 199, 132),
              onTap: () => _push(context, const RecordHubPage()),
              actionLabel: '開始記錄',
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
              icon: Icons.calendar_month_outlined,
              title: '生活軌跡',
              subtitle: '從日曆回顧每天的紀錄與生活變化',
              color: const Color(0xFF5C9BD5),
              onTap: () => _push(context, const LifeOverviewPage()),
              actionLabel: '查看軌跡',
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
  final GlobalKey _dailyRecordCardKey = GlobalKey();
  TutorialCoachMark? _homeTutorial;
  bool _didCheckTutorial = false;
  bool _isShowingHomeTutorial = false;
  bool _isContinuingTutorial = false;
  bool _isDisposingTutorial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowDailyRecordTutorial();
    });
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  void dispose() {
    _isDisposingTutorial = true;
    _homeTutorial?.finish();
    _homeTutorial = null;
    super.dispose();
  }

  Future<void> _maybeShowDailyRecordTutorial() async {
    if (_didCheckTutorial || _isShowingHomeTutorial) return;
    _didCheckTutorial = true;

    final shouldShow = await AppTutorialService.shouldShowDailyRecordTutorial();
    if (!mounted || !shouldShow) return;
    if (_dailyRecordCardKey.currentContext == null) return;

    _isShowingHomeTutorial = true;
    _homeTutorial = TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'daily_record_entry',
          keyTarget: _dailyRecordCardKey,
          shape: ShapeLightFocus.RRect,
          radius: 18,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => _TutorialBubble(
                text: '從這裡開始填寫今天的情緒、症狀與睡眠狀態。',
                primaryText: '下一步',
                onPrimary: _goToDailyRecordFromTutorial,
                onSkip: controller.skip,
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.48,
      paddingFocus: 8,
      textSkip: '跳過',
      onClickTarget: (_) => _goToDailyRecordFromTutorial(),
      onFinish: _goToDailyRecordFromTutorial,
      onSkip: () {
        _isShowingHomeTutorial = false;
        _homeTutorial = null;
        return true;
      },
    );
    _homeTutorial?.show(context: context);
  }

  Future<void> _goToDailyRecordFromTutorial() async {
    if (!mounted || _isContinuingTutorial || _isDisposingTutorial) return;
    _isContinuingTutorial = true;
    _isShowingHomeTutorial = false;
    _homeTutorial?.finish();
    _homeTutorial = null;

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DailyRecordScreen(startTutorial: true),
      ),
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
            _RecordEntryCard(
              icon: Icons.book_outlined,
              title: '日記',
              subtitle: '獨立日記頁與歷史日記',
              color: const Color.fromARGB(255, 255, 195, 113),
              onTap: () => _push(context, const DiaryHomePage()),
            ),
            const SizedBox(height: 12),
            _RecordEntryCard(
              key: _dailyRecordCardKey,
              icon: Icons.edit_note,
              title: '每日狀態紀錄',
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
    super.key,
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
              title: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                    if (widget.actionLabel != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.actionLabel!,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: widget.color,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing: Container(
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
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorialBubble extends StatelessWidget {
  const _TutorialBubble({
    required this.text,
    required this.primaryText,
    required this.onPrimary,
    required this.onSkip,
  });

  final String text;
  final String primaryText;
  final VoidCallback onPrimary;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFF),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF2F4858),
              fontSize: 16,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onSkip,
                child: const Text('跳過'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onPrimary,
                child: Text(primaryText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
