import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'dart:convert';

import '../constants/healing_design_system.dart';
import '../utils/date_helper.dart';
import '../utils/firebase_sync_config.dart';
import '../models/daily_record.dart';
import '../widgets/main_drawer.dart';
import 'daily_record_repository.dart';

// Import refactored modules
import 'daily_record_helpers.dart';
import 'daily_record_widgets.dart';
import 'daily_record_pages.dart';
import 'widgets/emotion_page_checkbox.dart';
import '../analytics_service.dart';
import '../tutorial/app_tutorial_service.dart';

/// Main Screen
class DailyRecordScreen extends StatefulWidget {
  const DailyRecordScreen({
    super.key,
    this.initialTab = 0,
    this.startTutorial = false,
  });

  final int initialTab;
  final bool startTutorial;

  @override
  State<DailyRecordScreen> createState() => _DailyRecordScreenState();
}

class _DailyRecordScreenState extends State<DailyRecordScreen> {
  int _index = 0;
  late final PageController _pageController;
  bool _isSaving = false;
  bool _isPeriod = false;
  final Set<DateTime> _periodSelectedDates = <DateTime>{};
  DateTime _periodFocusedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _periodCycleLength = 28;
  bool _isUpdatingPeriodCalendar = false;
  bool _showsPeriodCalendar = false;
  int? _lastSuicidalValue;
  final GlobalKey _emotionTabKey = GlobalKey();
  final GlobalKey _firstEmotionItemKey = GlobalKey();
  final GlobalKey _emotionScoreKey = GlobalKey();
  final GlobalKey _tutorialSliderKey = GlobalKey();
  final GlobalKey _saveButtonKey = GlobalKey();
  final ScrollController _emotionScrollController = ScrollController();
  TutorialCoachMark? _dailyTutorial;
  bool _didStartTutorial = false;
  bool _isDisposingTutorial = false;
  bool _showTutorialScorePreview = false;
  int _recordLoadGeneration = 0;

  // ——— 目前紀錄日期與時間（給頁首顯示；docId 只吃日期） ———
  DateTime _recordDate = DateTime.now();
  TimeOfDay _recordTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    _index = widget.initialTab.clamp(0, 2);
    _pageController = PageController(initialPage: _index);
    _loadPeriodVisibilityAndCalendarState();
    _loadExistingData(_recordDate);
    if (widget.startTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        await _startDailyRecordTutorial();
      });
    }
    AnalyticsService.logPage('daily_record_page'); // 一進來就載入今天的紀錄（含生理期狀態）
  }

  @override
  void dispose() {
    _isDisposingTutorial = true;
    _dailyTutorial?.finish();
    _dailyTutorial = null;
    _emotionScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _loadPeriodVisibilityAndCalendarState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    var showsPeriodCalendar = false;
    try {
      final profile =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final sex = (profile.data()?['sexAssignedAtBirth'] as String?)?.trim();
      showsPeriodCalendar = sex == null || sex.isEmpty || sex == '女性';
    } catch (e) {
      debugPrint('讀取生理性別失敗: $e');
    }

    if (!mounted) return;
    setState(() {
      _showsPeriodCalendar = showsPeriodCalendar;
      if (!showsPeriodCalendar) {
        _isPeriod = false;
      }
    });

    if (showsPeriodCalendar) {
      await _loadPeriodCalendarState();
    }
  }

  List<DateTime> _periodStarts() {
    final sorted = _periodSelectedDates.toList()..sort();
    if (sorted.isEmpty) return const [];

    final starts = <DateTime>[];
    for (final day in sorted) {
      final prev = day.subtract(const Duration(days: 1));
      if (!_periodSelectedDates.contains(prev)) {
        starts.add(day);
      }
    }
    return starts;
  }

  int _inferCycleLengthFromDays(Set<DateTime> markedDays, {int fallback = 28}) {
    if (markedDays.isEmpty) return fallback;
    final sorted = markedDays.toList()..sort();
    final starts = <DateTime>[];
    for (final day in sorted) {
      final prev = day.subtract(const Duration(days: 1));
      if (!markedDays.contains(prev)) {
        starts.add(day);
      }
    }
    if (starts.length < 2) return fallback;

    final intervals = <int>[];
    for (int i = 1; i < starts.length; i++) {
      final diff =
          _dateOnly(starts[i]).difference(_dateOnly(starts[i - 1])).inDays;
      if (diff >= 15 && diff <= 60) {
        intervals.add(diff);
      }
    }
    if (intervals.isEmpty) return fallback;

    final sum = intervals.fold<int>(0, (acc, v) => acc + v);
    final avg = (sum / intervals.length).round();
    return avg.clamp(21, 45);
  }

  DateTime? _predictedNextPeriodStart() {
    final starts = _periodStarts();
    if (starts.isEmpty) return null;
    return starts.last.add(Duration(days: _periodCycleLength));
  }

  int? _arrivalDeltaDays() {
    final starts = _periodStarts();
    if (starts.length < 2) return null;
    final previous = starts[starts.length - 2];
    final latest = starts.last;
    final expected = previous.add(Duration(days: _periodCycleLength));
    return _dateOnly(latest).difference(_dateOnly(expected)).inDays;
  }

  Future<void> _loadPeriodCalendarState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final startDate = _dateOnly(now.subtract(const Duration(days: 540)));
    final endDate = _dateOnly(now.add(const Duration(days: 365)));
    final selected = <DateTime>{};

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCycle = prefs.getInt('period_cycle_length');
      if (savedCycle != null && savedCycle >= 21 && savedCycle <= 45) {
        _periodCycleLength = savedCycle;
      }

      final savedDays =
          prefs.getStringList('period_selected_dates') ?? const [];
      for (final id in savedDays) {
        final d = DateTime.tryParse(id);
        if (d != null) selected.add(_dateOnly(d));
      }
    } catch (_) {}

    try {
      final repo = DailyRecordRepository();
      final localRecords = await repo.getDailyRecordsByDateRange(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );
      for (final row in localRecords) {
        final periodData = row['periodData'];
        final isPeriod = periodData is Map && periodData['isPeriod'] == true;
        if (!isPeriod) continue;
        final date = DateTime.tryParse(row['date']?.toString() ?? '');
        if (date != null) {
          selected.add(_dateOnly(date));
        }
      }
    } catch (_) {}

    if (FirebaseSyncConfig.shouldSync()) {
      try {
        final configRef = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('periodTracker');
        final configSnap = await configRef.get();
        final config = configSnap.data();
        final cloudCycle = (config?['cycleLength'] as num?)?.toInt();
        if (cloudCycle != null && cloudCycle >= 21 && cloudCycle <= 45) {
          _periodCycleLength = cloudCycle;
        }

        final periodSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('dailyRecords')
            .where('date',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
            .get();

        for (final doc in periodSnap.docs) {
          if (doc.data()['isPeriod'] != true) continue;
          final ts = doc.data()['date'] as Timestamp?;
          if (ts != null) {
            selected.add(_dateOnly(ts.toDate()));
          }
        }
      } catch (e) {
        debugPrint('讀取生理期月曆資料失敗: $e');
      }
    }

    if (!mounted) return;
    _periodCycleLength = _inferCycleLengthFromDays(
      selected,
      fallback: _periodCycleLength,
    );
    setState(() {
      _periodSelectedDates
        ..clear()
        ..addAll(selected);
      _isPeriod = _periodSelectedDates.contains(_dateOnly(_recordDate));
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('period_cycle_length', _periodCycleLength);
    } catch (_) {}
  }

  Future<void> _persistPeriodDatesToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = _periodSelectedDates.toList()..sort();
      await prefs.setStringList(
        'period_selected_dates',
        ids.map(DateHelper.toId).toList(),
      );
    } catch (_) {}
  }

  Future<void> _upsertPeriodDayLocal({
    required String uid,
    required DateTime day,
    required bool isPeriod,
    String? startId,
  }) async {
    final repo = DailyRecordRepository();
    final existing = await repo.getDailyRecord(userId: uid, date: day);

    await repo.saveDailyRecord(
      id: DateHelper.toId(day),
      userId: uid,
      date: day,
      emotions: (existing?['emotions'] as Map?)?.cast<String, dynamic>(),
      sleep: (existing?['sleep'] as Map?)?.cast<String, dynamic>(),
      bodySymptoms: (existing?['bodySymptoms'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      dailyActivities:
          (existing?['dailyActivities'] as Map?)?.cast<String, dynamic>(),
      medicines: (existing?['medicines'] as List?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
      moodScale: (existing?['moodScale'] as num?)?.toInt() == 10 ? 10 : 5,
      periodData: {
        'isPeriod': isPeriod,
        'periodStartId': isPeriod ? startId : null,
        'periodEndId': null,
        'cycleLength': _periodCycleLength,
      },
    );
  }

  Future<void> _applyPeriodDaysUpdate({
    required Set<DateTime> days,
    required bool isPeriod,
    String? startId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || days.isEmpty || _isUpdatingPeriodCalendar) return;

    setState(() => _isUpdatingPeriodCalendar = true);
    try {
      if (isPeriod) {
        _periodSelectedDates.addAll(days);
      } else {
        _periodSelectedDates.removeAll(days);
      }
      _isPeriod = _periodSelectedDates.contains(_dateOnly(_recordDate));
      _periodCycleLength = _inferCycleLengthFromDays(
        _periodSelectedDates,
        fallback: _periodCycleLength,
      );
      await _persistPeriodDatesToPrefs();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('period_cycle_length', _periodCycleLength);
      } catch (_) {}

      for (final day in days) {
        await _upsertPeriodDayLocal(
          uid: uid,
          day: day,
          isPeriod: isPeriod,
          startId: startId,
        );
      }

      if (FirebaseSyncConfig.shouldSync()) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('periodTracker')
            .set({
          'cycleLength': _periodCycleLength,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final batch = FirebaseFirestore.instance.batch();
        for (final day in days) {
          final docId = DateHelper.toId(day);
          final ref = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('dailyRecords')
              .doc(docId);
          batch.set(
            ref,
            {
              'date': Timestamp.fromDate(day),
              'isPeriod': isPeriod,
              'periodStartId': isPeriod ? startId : null,
              'periodEndId': null,
              'periodCycleLength': _periodCycleLength,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('更新生理期月曆失敗: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新生理期資料失敗：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingPeriodCalendar = false);
      }
    }
  }

  Future<void> _onTapPeriodDate(DateTime date) async {
    if (!_showsPeriodCalendar) return;

    final day = _dateOnly(date);
    if (_periodSelectedDates.contains(day)) {
      final isStartOfRun = !_periodSelectedDates.contains(
        day.subtract(const Duration(days: 1)),
      );

      if (isStartOfRun) {
        final removedDays = _periodSelectedDates
            .where((d) =>
                !d.isBefore(day) &&
                d.isBefore(day.add(const Duration(days: 7))))
            .toSet();

        if (removedDays.isNotEmpty) {
          await _applyPeriodDaysUpdate(days: removedDays, isPeriod: false);
        }
        return;
      }

      await _applyPeriodDaysUpdate(days: {day}, isPeriod: false);
      return;
    }

    final hasAdjacentSelected =
        _periodSelectedDates.contains(day.subtract(const Duration(days: 1))) ||
            _periodSelectedDates.contains(day.add(const Duration(days: 1)));

    if (hasAdjacentSelected) {
      await _applyPeriodDaysUpdate(days: {day}, isPeriod: true, startId: null);
      return;
    }

    final startId = DateHelper.toId(day);
    final autoDays = Set<DateTime>.from(
      List.generate(7, (i) => day.add(Duration(days: i))),
    );
    await _applyPeriodDaysUpdate(
      days: autoDays,
      isPeriod: true,
      startId: startId,
    );
  }

  void _resetForm({bool keepPeriodStatus = false}) {
    setState(() {
      // 🔹 情緒（包含移除前一個日期才有的自訂情緒）
      _emotions
        ..clear()
        ..addAll(emotionItemsForRecord(const <Emotion>[]));
      _lastSuicidalValue = null;

      // 🔹 症狀
      _symptoms.clear();
      _symptoms.add(SymptomItem(name: ''));

      // 🔹 安眠藥相關
      tookHypnotic = false;
      hypnoticName = '';
      _hypnoticNameCtrl.clear();
      hypnoticDose = '';
      _hypnoticDoseCtrl.clear();

      // 🔹 睡眠時間
      sleepTime = null;
      wakeTime = null;
      finalWakeTime = null;
      midWakeList = '';
      _midWakeCtrl.clear();

      // 🔹 睡眠旗標、備註、品質
      _sleepFlags.clear();
      sleepNote = '';
      sleepQuality = null;

      // 🔹 小睡
      _naps.clear();

      // 🔹 生理期狀態：除非特別說「要保留」，才歸零
      if (!keepPeriodStatus) {
        _isPeriod = false;
      }
    });
  }

  // ——— 情緒/症狀/睡眠本地狀態 ———
  final List<EmotionItem> _emotions =
      kEmotionCheckboxNames.map((name) => EmotionItem(name)).toList();

  final List<SymptomItem> _symptoms = [SymptomItem(name: '')];

  bool tookHypnotic = false;
  String hypnoticName = '';
  String hypnoticDose = '';
  TimeOfDay? sleepTime;
  TimeOfDay? wakeTime;
  TimeOfDay? finalWakeTime;
  String midWakeList = '';
  late final TextEditingController _midWakeCtrl = TextEditingController();
  late final TextEditingController _hypnoticNameCtrl = TextEditingController();
  late final TextEditingController _hypnoticDoseCtrl = TextEditingController();
  final Set<SleepFlag> _sleepFlags = {};
  String sleepNote = '';
  int? sleepQuality;
  final List<NapItem> _naps = [];

  // ——— 共用：包裹每個分頁（頁首 + 內容 + 底部儲存鈕） ———
  Widget _pageWrapper(Widget child) {
    return Column(
      children: [
        RecordHeader(
          dateText: DateHelper.toDisplay(_recordDate),
          timeText: DateHelper.formatTime(_recordTime),
          onPickDate: _pickRecordDate,
          onPickTime: _pickRecordTime,
        ),
        Expanded(child: child),
      ],
    );
  }

  Future<void> _startDailyRecordTutorial() async {
    if (_didStartTutorial) return;
    _didStartTutorial = true;

    if (_index != 0) {
      setState(() => _index = 0);
      _pageController.jumpToPage(0);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (!mounted) return;

    await _showDailyTutorialSegment(
      targets: [
        _buildTargetIfVisible(
          key: _emotionTabKey,
          identify: 'emotion_tab',
          text: '先從情緒開始，記錄今天主要的感受。',
          radius: 16,
        ),
        _buildTargetIfVisible(
          key: _firstEmotionItemKey,
          identify: 'first_emotion_item',
          text: '點選情緒項目，可以設定今天的情緒強度。',
        ),
      ],
      onFinish: _showEmotionScoreTutorialWithBubble,
    );
  }

  Future<void> _showEmotionScoreTutorialWithBubble() async {
    if (!mounted) return;

    if (!_emotions.any((emotion) => emotion.value != null) &&
        !_showTutorialScorePreview) {
      setState(() => _showTutorialScorePreview = true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }

    final scoreContext = _tutorialSliderKey.currentContext;
    if (scoreContext != null && scoreContext.mounted) {
      await Scrollable.ensureVisible(
        scoreContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.35,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (!mounted) return;

    final scoreTarget = _buildTargetIfVisible(
      key: _tutorialSliderKey,
      identify: 'emotion_score',
      text: '滑動以調整分數',
    );

    final effectiveScoreTarget = _buildSliderTargetIfVisible() ?? scoreTarget;

    if (effectiveScoreTarget == null) {
      await _showSaveTutorial();
      return;
    }

    await _showDailyTutorialSegment(
      targets: [effectiveScoreTarget],
      onFinish: _showSaveTutorial,
    );
  }

  Future<void> _showSaveTutorial() async {
    if (!mounted) return;

    await _showDailyTutorialSegment(
      targets: [
        _buildTargetIfVisible(
          key: _saveButtonKey,
          identify: 'save_button',
          text: '完成後記得儲存，資料才會出現在紀錄歷程與趨勢圖。',
          primaryText: '我知道了',
        ),
      ],
      onFinish: _markDailyRecordTutorialSeen,
    );
  }

  TargetFocus? _buildSliderTargetIfVisible() {
    if (_tutorialSliderKey.currentContext == null) return null;

    return TargetFocus(
      identify: 'emotion_score',
      keyTarget: _tutorialSliderKey,
      shape: ShapeLightFocus.RRect,
      radius: 16,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          builder: (context, controller) => _DailyTutorialBubble(
            text: '滑動以調整分數',
            primaryText: '下一步',
            onPrimary: controller.next,
            onSkip: controller.skip,
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Future<void> _showEmotionScoreTutorial() async {
    if (!mounted) return;

    if (!_emotions.any((emotion) => emotion.value != null) &&
        !_showTutorialScorePreview) {
      setState(() => _showTutorialScorePreview = true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }

    final scoreContext = _emotionScoreKey.currentContext;
    if (scoreContext != null && scoreContext.mounted) {
      await Scrollable.ensureVisible(
        scoreContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.35,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (!mounted) return;

    await _showDailyTutorialSegment(
      targets: [
        _buildTargetIfVisible(
          key: _emotionScoreKey,
          identify: 'emotion_score',
          text: '用分數記錄強度，之後就能在趨勢圖看到變化。',
        ),
        _buildTargetIfVisible(
          key: _saveButtonKey,
          identify: 'save_button',
          text: '完成後記得儲存，資料才會出現在紀錄歷程與趨勢圖。',
          primaryText: '我知道了',
        ),
      ],
      onFinish: _markDailyRecordTutorialSeen,
    );
  }

  Future<void> _showDailyTutorialSegment({
    required List<TargetFocus?> targets,
    required Future<void> Function() onFinish,
  }) async {
    final visibleTargets = targets.whereType<TargetFocus>().toList();
    if (visibleTargets.isEmpty) {
      await onFinish();
      return;
    }

    _dailyTutorial?.finish();
    _dailyTutorial = null;

    _dailyTutorial = TutorialCoachMark(
      targets: visibleTargets,
      colorShadow: Colors.black,
      opacityShadow: 0.48,
      paddingFocus: 8,
      textSkip: '跳過',
      onFinish: () async {
        _dailyTutorial = null;
        if (_isDisposingTutorial) return;
        await onFinish();
      },
      onSkip: () {
        _dailyTutorial = null;
        if (_isDisposingTutorial) return true;
        _markDailyRecordTutorialSeen();
        return true;
      },
    )..show(context: context);
  }

  TargetFocus? _buildTargetIfVisible({
    required GlobalKey key,
    required String identify,
    required String text,
    ShapeLightFocus shape = ShapeLightFocus.RRect,
    double radius = 20,
    ContentAlign contentAlign = ContentAlign.bottom,
    String primaryText = '下一步',
  }) {
    if (key.currentContext == null) return null;

    return TargetFocus(
      identify: identify,
      keyTarget: key,
      shape: shape,
      radius: radius,
      contents: [
        TargetContent(
          align: contentAlign,
          builder: (context, controller) => _DailyTutorialBubble(
            text: text,
            primaryText: primaryText,
            onPrimary: controller.next,
            onSkip: controller.skip,
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Future<void> _maybeShowDailyRecordTutorial() async {
    if (_didStartTutorial) return;
    _didStartTutorial = true;

    if (_index != 0) {
      setState(() => _index = 0);
      _pageController.jumpToPage(0);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (!mounted) return;

    final targets = <TargetFocus?>[
      _buildTutorialTarget(
        key: _emotionTabKey,
        identify: 'emotion_tab',
        text: '先從情緒開始，記錄今天主要的感受。',
      ),
      _buildTutorialTarget(
        key: _firstEmotionItemKey,
        identify: 'first_emotion_item',
        text: '點選情緒項目，可以設定今天的情緒強度。',
      ),
      _buildTutorialTarget(
        key: _emotionScoreKey.currentContext == null
            ? _firstEmotionItemKey
            : _emotionScoreKey,
        identify: 'emotion_score',
        text: '用分數記錄強度，之後就能在趨勢圖看到變化。',
      ),
      _buildTutorialTarget(
        key: _saveButtonKey,
        identify: 'save_button',
        text: '完成後記得儲存，資料才會出現在紀錄歷程與趨勢圖。',
        primaryText: '我知道了',
      ),
    ].whereType<TargetFocus>().toList();

    if (targets.isEmpty) return;

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.48,
      paddingFocus: 8,
      textSkip: '跳過',
      onFinish: _markDailyRecordTutorialSeen,
      onSkip: () {
        _markDailyRecordTutorialSeen();
        return true;
      },
    ).show(context: context);
  }

  // ignore: unused_element
  TargetFocus? _buildTutorialTarget({
    required GlobalKey key,
    required String identify,
    required String text,
    String primaryText = '下一步',
  }) {
    if (key.currentContext == null) return null;

    return TargetFocus(
      identify: identify,
      keyTarget: key,
      shape: ShapeLightFocus.RRect,
      radius: 18,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) => _DailyTutorialBubble(
            text: text,
            primaryText: primaryText,
            onPrimary: controller.next,
            onSkip: controller.skip,
          ),
        ),
      ],
    );
  }

  Future<void> _markDailyRecordTutorialSeen() async {
    if (mounted && _showTutorialScorePreview) {
      setState(() => _showTutorialScorePreview = false);
    }
    await AppTutorialService.markDailyRecordTutorialSeen();
  }

  Widget _buildTopTabBar() {
    const tabs = [
      (icon: Icons.sentiment_satisfied, label: '情緒'),
      (icon: Icons.healing, label: '症狀'),
      (icon: Icons.nightlight_round, label: '睡眠'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HealingDesignSystem.lineColor),
        boxShadow: [HealingDesignSystem.shadowLight()],
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isSelected = _index == i;
          return Expanded(
            child: AnimatedContainer(
              duration: HealingDesignSystem.animationFast,
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                gradient:
                    isSelected ? HealingDesignSystem.primaryGradient() : null,
                color: isSelected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: i == 0 ? _emotionTabKey : null,
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _selectTab(i),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          tabs[i].icon,
                          size: 18,
                          color: isSelected
                              ? Colors.white
                              : HealingDesignSystem.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tabs[i].label,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : HealingDesignSystem.deepText,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _selectTab(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    _pageController.animateToPage(
      index,
      duration: HealingDesignSystem.animationFast,
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadExistingData(DateTime date) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('❌ No user ID found');
      return;
    }

    final docId = DateHelper.toId(date);
    final loadGeneration = ++_recordLoadGeneration;
    _resetForm();
    debugPrint(
        '🔄 _loadExistingData called: uid=$uid, date=$date (ISO: ${date.toIso8601String()}), docId=$docId');

    try {
      // 1. 先嘗試從本地 SQLite 加載
      final repo = DailyRecordRepository();
      debugPrint('📦 Attempting to load from local SQLite...');
      var localData = await repo.getDailyRecord(userId: uid, date: date);

      if (localData != null) {
        if (!_isCurrentRecordLoad(loadGeneration, docId)) return;
        debugPrint('✅ Loaded record from local SQLite: $docId');
        _applyLocalRecordData(localData, date);
        return;
      }

      debugPrint('⚠️  No local record found, trying Firebase...');

      // 2. 如果本地沒有，再從 Firebase 加載
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .doc(docId)
          .get();

      if (!_isCurrentRecordLoad(loadGeneration, docId)) return;
      if (doc.exists && doc.data() != null) {
        debugPrint('✅ Loaded record from Firebase: $docId');
        // A. 這一天已經有紀錄 → 完整讀取
        final record = DailyRecord.fromFirestore(doc);
        _applyFirebaseRecordData(record, date);
      } else {
        debugPrint(
            '⚠️  No record found in Firebase either, loading period state...');
        // B. 今日沒有紀錄 → 自動推算生理期（看昨天）
        await _loadPeriodState(date);
        if (!_isCurrentRecordLoad(loadGeneration, docId)) return;

        // C. 清空其他欄位，但保留剛推算的 _isPeriod
        _resetForm(keepPeriodStatus: true);
      }
    } catch (e, st) {
      debugPrint('❌ 讀取資料錯誤: $e\nStacktrace: $st');
    }
  }

  bool _isCurrentRecordLoad(int generation, String docId) =>
      mounted &&
      generation == _recordLoadGeneration &&
      DateHelper.toId(_recordDate) == docId;

  /// 從本地 SQLite 記錄應用數據
  void _applyLocalRecordData(Map<String, dynamic> data, DateTime date) {
    debugPrint('🔄 _applyLocalRecordData: data keys = ${data.keys.toList()}');

    // 解析 emotions 和其他 JSON 字段
    List<Emotion> emotions = [];
    if (data['emotions'] != null) {
      try {
        final rawEmotions = data['emotions'];
        if (rawEmotions is List) {
          emotions = rawEmotions
              .whereType<Map>()
              .map((item) => Emotion.fromMap(Map<String, dynamic>.from(item)))
              .toList();
        } else {
          final emotionMap = rawEmotions is String
              ? jsonDecode(rawEmotions) as Map<String, dynamic>
              : (rawEmotions as Map).cast<String, dynamic>();
          emotionMap.forEach((name, value) {
            emotions.add(Emotion(name: name, value: value as int?));
          });
        }
        debugPrint('✅ Total emotions parsed: ${emotions.length}');
      } catch (e) {
        debugPrint('❌ Failed to parse emotions: $e');
      }
    } else {
      debugPrint('⚠️  No emotions field in data');
    }

    List<String> symptoms = [];
    if (data['bodySymptoms'] != null) {
      try {
        List<dynamic> symptomList;
        if (data['bodySymptoms'] is String) {
          symptomList = jsonDecode(data['bodySymptoms']) as List<dynamic>;
        } else if (data['bodySymptoms'] is List) {
          symptomList = data['bodySymptoms'] as List<dynamic>;
        } else {
          throw TypeError();
        }
        symptoms = symptomList.cast<String>();
        debugPrint('✅ Parsed symptoms: ${symptoms.length} items');
      } catch (e) {
        debugPrint('❌ Failed to parse symptoms: $e');
      }
    }

    Map<String, dynamic>? periodData;
    if (data['periodData'] != null) {
      try {
        if (data['periodData'] is String) {
          periodData = jsonDecode(data['periodData']) as Map<String, dynamic>;
        } else if (data['periodData'] is Map) {
          periodData = data['periodData'] as Map<String, dynamic>;
        } else {
          throw TypeError();
        }
        debugPrint('✅ Parsed periodData: $periodData');
      } catch (e) {
        debugPrint('❌ Failed to parse periodData: $e');
      }
    }

    SleepData sleepData = SleepData();
    if (data['sleep'] != null) {
      try {
        Map<String, dynamic> sleepMap;
        if (data['sleep'] is String) {
          sleepMap = jsonDecode(data['sleep']) as Map<String, dynamic>;
        } else if (data['sleep'] is Map) {
          sleepMap = data['sleep'] as Map<String, dynamic>;
        } else {
          throw TypeError();
        }
        sleepData = _parseSleepDataFromMap(sleepMap);
        debugPrint('✅ Parsed sleep data successfully');
      } catch (e, st) {
        debugPrint('❌ Failed to parse sleep: $e\nStacktrace: $st');
      }
    } else {
      debugPrint('⚠️  No sleep field in data');
    }

    debugPrint('🎨 Applying parsed data to UI...');
    setState(() {
      // 應用情緒
      _emotions
        ..clear()
        ..addAll(emotionItemsForRecord(emotions));
      debugPrint('✅ Applied ${emotions.length} emotions to UI');

      // 應用症狀
      _symptoms
        ..clear()
        ..addAll(
          symptoms.isEmpty
              ? [SymptomItem(name: '')]
              : symptoms.map((n) => SymptomItem(name: n)),
        );
      debugPrint('✅ Applied ${symptoms.length} symptoms to UI');

      // 應用睡眠數據
      tookHypnotic = sleepData.tookHypnotic;
      hypnoticName = sleepData.hypnoticName ?? '';
      _hypnoticNameCtrl.text = hypnoticName;
      hypnoticDose = sleepData.hypnoticDose ?? '';
      _hypnoticDoseCtrl.text = hypnoticDose;

      sleepTime = sleepData.sleepTime;
      wakeTime = sleepData.wakeTime;
      finalWakeTime = sleepData.finalWakeTime;

      midWakeList = sleepData.midWakeList ?? '';
      _midWakeCtrl.text = midWakeList;

      // 睡眠標籤
      _sleepFlags.clear();
      for (final f in sleepData.flags) {
        try {
          final match = SleepFlag.values.firstWhere((e) => e.name == f);
          _sleepFlags.add(match);
        } catch (_) {}
      }

      sleepNote = sleepData.note ?? '';
      sleepQuality = sleepData.quality;

      // 小睡
      _naps
        ..clear()
        ..addAll(sleepData.naps);

      // 生理期狀態（月曆資料優先）
      final localPeriod = periodData?['isPeriod'] == true;
      _isPeriod = _periodSelectedDates.contains(_dateOnly(date)) || localPeriod;

      debugPrint('✅ All data applied to UI successfully');
    });
  }

  /// 從 Firebase 記錄應用數據
  void _applyFirebaseRecordData(DailyRecord record, DateTime date) {
    final s = record.sleep;

    setState(() {
      // --- 情緒 ---
      _emotions
        ..clear()
        ..addAll(emotionItemsForRecord(record.emotions));
      // --- 症狀 ---
      _symptoms
        ..clear()
        ..addAll(
          record.symptoms.isEmpty
              ? [SymptomItem(name: '')]
              : record.symptoms.map((n) => SymptomItem(name: n)),
        );

      // --- 睡眠 ---
      tookHypnotic = s.tookHypnotic;
      hypnoticName = s.hypnoticName ?? '';
      _hypnoticNameCtrl.text = hypnoticName;
      hypnoticDose = s.hypnoticDose ?? '';
      _hypnoticDoseCtrl.text = hypnoticDose;

      sleepTime = s.sleepTime;
      wakeTime = s.wakeTime;
      finalWakeTime = s.finalWakeTime;

      midWakeList = s.midWakeList ?? '';
      _midWakeCtrl.text = midWakeList;

      // 睡眠標籤
      _sleepFlags.clear();
      for (final f in s.flags) {
        try {
          final match = SleepFlag.values.firstWhere((e) => e.name == f);
          _sleepFlags.add(match);
        } catch (_) {}
      }

      sleepNote = s.note ?? '';
      sleepQuality = s.quality;

      // 小睡
      _naps
        ..clear()
        ..addAll(
          s.naps.map(
            (n) => NapItem(start: n.start, end: n.end),
          ),
        );

      // 生理期狀態（月曆資料優先）
      _isPeriod =
          _periodSelectedDates.contains(_dateOnly(date)) || record.isPeriod;
    });
  }

  /// 從 Map 解析睡眠數據
  SleepData _parseSleepDataFromMap(Map<String, dynamic> sleepMap) {
    return SleepData(
      tookHypnotic: sleepMap['tookHypnotic'] ?? false,
      hypnoticName: sleepMap['hypnoticName'],
      hypnoticDose: sleepMap['hypnoticDose'],
      sleepTime: sleepMap['sleepTime'] != null
          ? DateHelper.parseTime(sleepMap['sleepTime'])
          : null,
      wakeTime: sleepMap['wakeTime'] != null
          ? DateHelper.parseTime(sleepMap['wakeTime'])
          : null,
      finalWakeTime: sleepMap['finalWakeTime'] != null
          ? DateHelper.parseTime(sleepMap['finalWakeTime'])
          : null,
      midWakeList: sleepMap['midWakeList'],
      flags: List<String>.from(sleepMap['flags'] ?? []),
      note: sleepMap['note'],
      quality: sleepMap['quality'],
      naps: (sleepMap['naps'] as List?)
              ?.map((n) => NapItem(
                    start: DateHelper.parseTime(n['start']) ??
                        const TimeOfDay(hour: 0, minute: 0),
                    end: DateHelper.parseTime(n['end']) ??
                        const TimeOfDay(hour: 0, minute: 0),
                  ))
              .toList() ??
          [],
    );
  }

  Future<void> _loadPeriodState(DateTime currentDate) async {
    _isPeriod = _periodSelectedDates.contains(_dateOnly(currentDate));
  }

  Future<void> _pickRecordDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _recordDate = picked;
        _periodFocusedMonth = DateTime(picked.year, picked.month, 1);
      });
      await _loadExistingData(_recordDate);
    }
  }

  Future<void> _saveAll() async {
    if (_isSaving) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final date = _recordDate;
    final docId = DateHelper.toId(date);

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyRecords')
        .doc(docId);

    setState(() => _isSaving = true);

    try {
      String? oldStartId;
      bool oldIsPeriod = false;
      var cloudSyncFailed = false;
      final effectiveIsPeriod = _showsPeriodCalendar && _isPeriod;

      // 離線時這一步可能失敗，不能影響本地儲存。
      if (FirebaseSyncConfig.shouldSync()) {
        try {
          final oldSnap = await ref.get(
            const GetOptions(source: Source.serverAndCache),
          );
          if (oldSnap.exists && oldSnap.data() != null) {
            final old = DailyRecord.fromFirestore(oldSnap);
            oldStartId = old.periodStartId;
            oldIsPeriod = old.isPeriod;
          }
        } catch (e) {
          debugPrint('⚠️ 讀取雲端舊資料失敗，改用離線流程：$e');
        }
      }

      final payload = <String, dynamic>{
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'emotions': _emotions
            .where((e) => e.value != null)
            .map((e) => {'name': e.name, 'value': e.value})
            .toList(),
        'symptoms': _symptoms.map((s) => s.name).toList(),
        'sleep': {
          'tookHypnotic': tookHypnotic,
          'hypnoticName': hypnoticName,
          'hypnoticDose': hypnoticDose,
          'sleepTime': DateHelper.formatTime(sleepTime),
          'wakeTime': DateHelper.formatTime(wakeTime),
          'flags': _sleepFlags.map((f) => f.name).toList(),
          'note': sleepNote,
          'quality': sleepQuality,
          'finalWakeTime': DateHelper.formatTime(finalWakeTime),
          'midWakeList': midWakeList,
          'naps': _naps
              .map((n) => {
                    'start': DateHelper.formatTime(n.start),
                    'end': DateHelper.formatTime(n.end),
                    'minutes': DateHelper.calcDurationMinutes(n.start, n.end),
                  })
              .toList(),
        },
        'savedAt': FieldValue.serverTimestamp(),
        'periodCycleLength': _periodCycleLength,
      };

      // 計算整體情緒：所有已選情緒的平均值
      final selectedEmotions = _emotions.where((e) => e.value != null).toList();
      if (selectedEmotions.isNotEmpty) {
        final sum = selectedEmotions.fold<int>(0, (acc, e) => acc + e.value!);
        payload['overallMood'] = (sum / selectedEmotions.length);
      }

      if (effectiveIsPeriod == true) {
        payload['isPeriod'] = true;
        payload['periodStartId'] = oldStartId ?? docId;
        payload['periodEndId'] = null;
      } else {
        payload['isPeriod'] = false;
        if (oldIsPeriod == true) {
          payload['periodEndId'] = docId;
        }
        payload['periodStartId'] = oldStartId;
      }

      payload['periodNextExpectedStart'] =
          _predictedNextPeriodStart()?.toIso8601String();
      payload['periodArrivalDeltaDays'] = _arrivalDeltaDays();

      // Only sync to Firebase if enabled
      if (FirebaseSyncConfig.shouldSync()) {
        try {
          await ref.set(payload, SetOptions(merge: true));
        } catch (e) {
          cloudSyncFailed = true;
          debugPrint('⚠️ 雲端同步失敗（已改為僅本地儲存）：$e');
        }
      }

      // Always save to local database
      try {
        final repo = DailyRecordRepository();
        debugPrint('🏁 Start saving to local database...');
        debugPrint(
            '📅 Saving with date: $_recordDate (ISO: ${_recordDate.toIso8601String()})');
        debugPrint('👤 Saving with userId: $uid');

        final emotionsToSave = Map<String, dynamic>.from(_emotions
            .where((e) =>
                e.value != null &&
                e.name != '整體情緒') // Exclude overallMood from emotions
            .toList()
            .asMap()
            .map((k, v) => MapEntry(v.name, v.value)));
        debugPrint('📊 Emotions to save: $emotionsToSave');

        final symptomsToSave = _symptoms
            .map((s) => s.name)
            .where((name) => name.isNotEmpty)
            .toList();
        debugPrint(
            '🩹 Symptoms to save: $symptomsToSave (from _symptoms: ${_symptoms.map((s) => s.name).toList()})');

        await repo.saveDailyRecord(
          id: docId,
          userId: uid,
          date: _recordDate,
          emotions: emotionsToSave,
          bodySymptoms: symptomsToSave,
          moodScale: 5,
          sleep: {
            'sleepTime':
                sleepTime != null ? DateHelper.formatTime(sleepTime!) : null,
            'wakeTime':
                wakeTime != null ? DateHelper.formatTime(wakeTime!) : null,
            'finalWakeTime': finalWakeTime != null
                ? DateHelper.formatTime(finalWakeTime!)
                : null,
            'midWakeList': midWakeList,
            'quality': sleepQuality,
            'tookHypnotic': tookHypnotic,
            'hypnoticName': hypnoticName,
            'hypnoticDose': hypnoticDose,
            'flags': _sleepFlags.map((f) => f.name).toList(),
            'note': sleepNote,
            'naps': _naps
                .map((n) => {
                      'start': DateHelper.formatTime(n.start),
                      'end': DateHelper.formatTime(n.end),
                      'minutes': DateHelper.calcDurationMinutes(n.start, n.end),
                    })
                .toList(),
          },
          periodData: {
            'isPeriod': effectiveIsPeriod,
            'periodStartId':
                effectiveIsPeriod ? (oldStartId ?? docId) : oldStartId,
            'periodEndId': !effectiveIsPeriod && oldIsPeriod ? docId : null,
            'cycleLength': _periodCycleLength,
            'nextExpectedStart': _predictedNextPeriodStart()?.toIso8601String(),
            'arrivalDeltaDays': _arrivalDeltaDays(),
          },
        );
        debugPrint('✅ Local save completed successfully');
      } catch (e) {
        debugPrint('❌ Local storage failed: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本地存儲失敗：$e')),
        );
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cloudSyncFailed ? '已離線儲存，恢復網路後會再同步。' : '已儲存成功！'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickRecordTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _recordTime,
    );
    if (picked != null) setState(() => _recordTime = picked);
  }

  Future<void> _addEmotion() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新增情緒項目'),
        content: TextField(
            controller: c, decoration: const InputDecoration(hintText: '項目名稱')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text),
              child: const Text('確定')),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _emotions.add(EmotionItem(name.trim())));
    }
  }

  Future<void> _renameEmotion(int i) async {
    if (i == 0) return;
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重新命名'),
        content: TextField(
            controller: c,
            decoration: InputDecoration(hintText: _emotions[i].name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text),
              child: const Text('確定')),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _emotions[i] = _emotions[i].copyWith(name: name.trim()));
    }
  }

  void _deleteEmotion(int i) => setState(() => _emotions.removeAt(i));

  void _maybeShowEmergencyAlert() {
    if (!mounted) return;

    final suicidal = _emotions
        .where((e) => e.name == '自殺意念')
        .map((e) => e.value)
        .firstOrNull;

    final lastValue = _lastSuicidalValue ?? 0;
    _lastSuicidalValue = suicidal ?? 0;

    // 只要有自殺意念（value != null），就立即顯示求救管道
    if (suicidal != null && lastValue == 0) {
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: const Text('緊急提醒'),
          content: const Text(
            '如果你正在經歷強烈痛苦或有自傷/自殺念頭，請優先尋求即時協助。\n\n'
            '【立即危險】\n'
            '📞 撥打 119（救護車／急診）\n\n'
            '【有人可以陪你】\n'
            '📞 生命線\n'
            '1995（24 小時）\n'
            '對象：情緒崩潰、想活不下去、需要有人陪你撐過此刻\n\n'
            '📞 安心專線（衛福部）\n'
            '1925（24 小時）\n'
            '對象：自殺意念、心理危機、重度低潮\n\n'
            '📞 張老師\n'
            '1980\n'
            '服務時間：每日 9:00–22:00（依地區略有不同）\n'
            '對象：情緒支持、談話陪伴',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _addSymptom() async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _TextInputDialog(
        title: '新增症狀',
        hintText: '輸入症狀名稱',
        confirmText: '確認',
      ),
    );

    if (!mounted) return;
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    setState(() {
      if (!_symptoms.any((symptom) => symptom.name == trimmed)) {
        _symptoms.add(SymptomItem(name: trimmed));
      }
    });
  }

  Future<void> _renameSymptom(int index) async {
    if (index < 0 || index >= _symptoms.length) return;

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _TextInputDialog(
        title: '編輯症狀',
        hintText: '輸入症狀名稱',
        initialValue: _symptoms[index].name,
        confirmText: '確認',
      ),
    );

    if (!mounted || index < 0 || index >= _symptoms.length) return;
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    setState(() {
      _symptoms[index] = _symptoms[index].copyWith(name: trimmed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? Theme.of(context).colorScheme.surface
        : HealingDesignSystem.softBlue;
    final pages = [
      // 情緒頁
      _pageWrapper(
        EmotionPageCheckbox(
          items: _emotions,
          onAdd: _addEmotion,
          onRename: _renameEmotion,
          onDelete: _deleteEmotion,
          onToggleChecked: (i, checked) {
            setState(() {
              _emotions[i] = _emotions[i].copyWith(
                value: checked ? (_emotions[i].value ?? 3) : null,
              );
            });
            _maybeShowEmergencyAlert();
          },
          onChangeValue: (i, v) {
            setState(() {
              _emotions[i] = _emotions[i].copyWith(value: v);
            });
            _maybeShowEmergencyAlert();
          },
          firstEmotionItemKey: _firstEmotionItemKey,
          emotionScoreKey: _emotionScoreKey,
          tutorialSliderKey: _tutorialSliderKey,
          scrollController: _emotionScrollController,
          showTutorialScorePreview: _showTutorialScorePreview,
        ),
      ),
      _pageWrapper(SymptomPage(
        items: _symptoms,
        onAdd: _addSymptom,
        onRename: _renameSymptom,
        onDelete: (i) => setState(() => _symptoms.removeAt(i)),
        onTogglePreset: (name, selected) {
          setState(() {
            if (selected) {
              if (!_symptoms.any((s) => s.name == name)) {
                _symptoms.add(SymptomItem(name: name));
              }
            } else {
              _symptoms.removeWhere((s) => s.name == name);
              if (_symptoms.isEmpty) {
                _symptoms.add(SymptomItem(name: ''));
              }
            }
          });
        },
        showPeriodCalendar: _showsPeriodCalendar,
        isPeriod: _isPeriod,
        onTogglePeriod: (v) => setState(() => _isPeriod = v),
        periodMarkedDays: _periodSelectedDates,
        periodFocusedMonth: _periodFocusedMonth,
        onTapPeriodDate: _onTapPeriodDate,
        onChangePeriodMonth: (month) {
          setState(() {
            _periodFocusedMonth = DateTime(month.year, month.month, 1);
          });
        },
        periodCycleLength: _periodCycleLength,
        nextExpectedStart: _predictedNextPeriodStart(),
        arrivalDeltaDays: _arrivalDeltaDays(),
        periodBusy: _isUpdatingPeriodCalendar,
      )),
      _pageWrapper(SleepPage(
        sleepTime: sleepTime,
        wakeTime: wakeTime,
        onPickSleepTime: () async {
          final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.now());
          if (t != null) setState(() => sleepTime = t);
        },
        onPickWakeTime: () async {
          final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.now());
          if (t != null) setState(() => wakeTime = t);
        },
        flags: _sleepFlags,
        onToggleFlag: (f) => setState(() {
          if (_sleepFlags.contains(f)) {
            _sleepFlags.remove(f);
          } else {
            _sleepFlags.add(f);
          }
        }),
        sleepNote: sleepNote,
        onChangeNote: (v) => setState(() => sleepNote = v),
        sleepQuality: sleepQuality,
        onPickValue: () async {
          int tempValue = sleepQuality ?? 1;
          final v = await showDialog<int>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('選擇睡眠品質'),
                content: StatefulBuilder(
                  builder: (context, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Slider(
                          value: tempValue.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          label: tempValue.toString(),
                          onChanged: (v) {
                            setState(() => tempValue = v.round());
                          },
                        ),
                        Text('$tempValue / 5'),
                      ],
                    );
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, tempValue),
                    child: const Text('確定'),
                  ),
                ],
              );
            },
          );
          if (v != null) setState(() => sleepQuality = v);
        },
        finalWakeTime: finalWakeTime,
        onPickFinalWakeTime: () async {
          final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.now());
          if (t != null) setState(() => finalWakeTime = t);
        },
        midWakeCtrl: _midWakeCtrl,
        onChangeMidWake: (v) => setState(() => midWakeList = v),
        tookHypnotic: tookHypnotic,
        onToggleHypnotic: (v) => setState(() => tookHypnotic = v),
        hypnoticName: hypnoticName,
        onChangeHypnoticName: (v) => setState(() => hypnoticName = v),
        hypnoticDose: hypnoticDose,
        onChangeHypnoticDose: (v) => setState(() => hypnoticDose = v),
        hypnoticNameCtrl: _hypnoticNameCtrl,
        hypnoticDoseCtrl: _hypnoticDoseCtrl,
        naps: _naps,
        onAddNap: () async {
          final start = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.now(),
            helpText: '入睡時間',
            confirmText: '確定',
            cancelText: '取消',
          );
          if (start == null) return;

          final end = await showTimePicker(
            context: context,
            initialTime: start,
            helpText: '起床時間',
            confirmText: '確定',
            cancelText: '取消',
          );
          if (end == null) return;

          if (start.hour == end.hour && start.minute == end.minute) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('開始與結束時間不可相同')),
            );
            return;
          }
          setState(() => _naps.add(NapItem(start: start, end: end)));
        },
        onEditNap: (i) async {
          final curr = _naps[i];

          final start = await showTimePicker(
            context: context,
            initialTime: curr.start,
            helpText: '入睡時間',
            confirmText: '確定',
            cancelText: '取消',
          );
          if (start == null) return;

          final end = await showTimePicker(
            context: context,
            initialTime: curr.end,
            helpText: '起床時間',
            confirmText: '確定',
            cancelText: '取消',
          );
          if (end == null) return;

          if (start.hour == end.hour && start.minute == end.minute) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('開始與結束時間不可相同')),
            );
            return;
          }
          setState(() => _naps[i] = _naps[i].copyWith(start: start, end: end));
        },
        onDeleteNap: (i) => setState(() => _naps.removeAt(i)),
      )),
    ];
    return Scaffold(
      backgroundColor: scaffoldBg,
      drawer: const MainDrawer(),
      appBar: AppBar(
        toolbarHeight: 60,
        elevation: 0,
        backgroundColor: isDark
            ? Theme.of(context).colorScheme.surface
            : HealingDesignSystem.softBlue,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 80,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '儲存',
              onPressed: _saveAll,
            ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: isDark
              ? null
              : BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      HealingDesignSystem.softBlue,
                      HealingDesignSystem.softBlue.withOpacity(0.82),
                      const Color(0xFFF8FCFF),
                    ],
                  ),
                ),
          child: Column(
            children: [
              _buildTopTabBar(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    if (_index != index) {
                      setState(() => _index = index);
                    }
                  },
                  children: pages,
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: _saveButtonKey,
                      onPressed: _isSaving ? null : _saveAll,
                      icon: const Icon(Icons.save),
                      label: Text(_isSaving ? '儲存中…' : '儲存全部'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.hintText,
    required this.confirmText,
    this.initialValue = '',
  });

  final String title;
  final String hintText;
  final String confirmText;
  final String initialValue;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

class _DailyTutorialBubble extends StatelessWidget {
  const _DailyTutorialBubble({
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
