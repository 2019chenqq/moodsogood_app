import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../daily/daily_check_in_page.dart';
import '../daily/daily_record_history.dart';
import '../daily/record_detail_screen.dart';
import '../diary/diary_page_demo.dart';
import '../models/calendar_day_summary.dart';
import '../models/life_timeline_item.dart';
import '../meds/record_adjustment_history_page.dart';
import '../services/calendar_summary_service.dart';
import '../services/life_timeline_service.dart';
import '../services/life_cooccurrence_service.dart';
import '../services/cooccurrence_cluster_service.dart';
import '../widgets/unified_calendar_widget.dart';
import '../analytics_service.dart';

class LifeOverviewPage extends StatefulWidget {
  const LifeOverviewPage({super.key});

  @override
  State<LifeOverviewPage> createState() => _LifeOverviewPageState();
}

class _LifeOverviewPageState extends State<LifeOverviewPage> {
  final CalendarSummaryService _summaryService = CalendarSummaryService();
  final LifeTimelineService _timelineService = LifeTimelineService();
  final LifeCooccurrenceService _cooccurrenceService =
      const LifeCooccurrenceService();

  late DateTime _selectedDate;
  late DateTime _focusedMonth;

  Map<String, CalendarDaySummary> _summaries = <String, CalendarDaySummary>{};
  bool _isLoading = true;
  String? _errorMessage;
  int _loadToken = 0;
  List<LifeTimelineItem> _timelineItems = const [];
  bool _isTimelineLoading = true;
  String? _timelineErrorMessage;
  int _timelineLoadToken = 0;
  int _selectedRangeDays = 1;
  _MultiDayViewData? _multiDayData;
  bool _isRangeLoading = false;
  String? _rangeErrorMessage;
  int _rangeLoadToken = 0;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('life_overview_page');
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(now.year, now.month, 1);
    _loadMonthSummary(_focusedMonth, showLoading: true);
    _loadDayTimeline(_selectedDate);
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(fn);
    });
  }

  Future<void> _loadMonthSummary(
    DateTime month, {
    bool showLoading = true,
  }) async {
    final token = ++_loadToken;

    if (showLoading) {
      _safeSetState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _summaryService.loadMonthSummary(visibleMonth: month);
      if (!mounted || token != _loadToken) return;

      _safeSetState(() {
        _summaries = data;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      _safeSetState(() {
        _isLoading = false;
        _errorMessage = '資料載入失敗，請稍後再試';
      });
      debugPrint('[LifeOverviewPage] load failed: $e');
    }
  }

  Future<void> _loadDayTimeline(DateTime date) async {
    final token = ++_timelineLoadToken;
    if (FirebaseAuth.instance.currentUser == null) {
      _safeSetState(() {
        _timelineItems = const [];
        _isTimelineLoading = false;
        _timelineErrorMessage = null;
      });
      return;
    }

    _safeSetState(() {
      _isTimelineLoading = true;
      _timelineErrorMessage = null;
    });
    try {
      final items = await _timelineService.loadDay(date);
      if (!mounted || token != _timelineLoadToken) return;
      _safeSetState(() {
        _timelineItems = items;
        _isTimelineLoading = false;
      });
    } catch (error) {
      if (!mounted || token != _timelineLoadToken) return;
      _safeSetState(() {
        _timelineItems = const [];
        _isTimelineLoading = false;
        _timelineErrorMessage = '當日生活軌跡載入失敗，請稍後再試。';
      });
      debugPrint('[LifeOverviewPage] timeline load failed: $error');
    }
  }

  Future<void> _selectRange(int days) async {
    if (_selectedRangeDays == days) return;
    _safeSetState(() => _selectedRangeDays = days);
    if (days == 1) {
      await _loadDayTimeline(_selectedDate);
    } else {
      await _loadMultiDayRange(days);
    }
  }

  Future<void> _loadMultiDayRange(int days, {bool force = false}) async {
    final end = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final start = end.subtract(Duration(days: days - 1));
    final token = ++_rangeLoadToken;
    _safeSetState(() {
      _isRangeLoading = true;
      _rangeErrorMessage = null;
    });
    try {
      final range = await _timelineService.loadRange(start: start, end: end);
      final data = _MultiDayViewData(
        range: range,
        patterns: _cooccurrenceService.analyze(range.itemsByDate),
      );
      if (!mounted || token != _rangeLoadToken) return;
      _safeSetState(() {
        _multiDayData = data;
        _isRangeLoading = false;
      });
    } catch (error) {
      if (!mounted || token != _rangeLoadToken) return;
      _safeSetState(() {
        _multiDayData = null;
        _isRangeLoading = false;
        _rangeErrorMessage = '多日生活軌跡載入失敗，請稍後再試。';
      });
      debugPrint('[LifeOverviewPage] range load failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('生活軌跡'),
      ),
      backgroundColor: const Color(0xFFF6FBFC),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD8EAED)),
              ),
              child: Text(
                '在這裡，你可以用日期回顧日記、情緒、症狀、睡眠與生理週期，看看不同狀態是否在同一天或同一段時間出現。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E8189),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const SizedBox(height: 14),
            if (user == null)
              const _AuthEmptyCard()
            else if (_isLoading)
              const _CalendarLoadingCard()
            else if (_errorMessage != null)
              _CalendarErrorCard(
                message: _errorMessage!,
                onRetry: () =>
                    _loadMonthSummary(_focusedMonth, showLoading: true),
              )
            else
              UnifiedCalendarWidget(
                selectedDate: _selectedDate,
                focusedMonth: _focusedMonth,
                mode: UnifiedCalendarMode.overview,
                summariesByDate: _summaries,
                showInternalPeriodLegend: false,
                onMonthChanged: (month) {
                  final normalized = DateTime(month.year, month.month, 1);
                  if (_isSameMonth(normalized, _focusedMonth)) return;

                  _safeSetState(() {
                    _focusedMonth = normalized;
                  });
                  _loadMonthSummary(normalized, showLoading: true);
                },
                onDateSelected: (date) {
                  final normalized = DateTime(date.year, date.month, date.day);
                  _safeSetState(() {
                    _selectedDate = normalized;
                  });
                  if (_selectedRangeDays == 1) {
                    _loadDayTimeline(normalized);
                  } else {
                    _loadMultiDayRange(_selectedRangeDays);
                  }
                },
              ),
            if (user != null && !_isLoading && _errorMessage == null) ...[
              const SizedBox(height: 10),
              const _LifeOverviewLegend(),
            ],
            const SizedBox(height: 16),
            if (user != null) ...[
              _TimelineRangeSelector(
                selectedDays: _selectedRangeDays,
                onSelected: _selectRange,
              ),
              const SizedBox(height: 12),
            ],
            if (user != null)
              if (_selectedRangeDays == 1)
                _DailyTimelineSection(
                  date: _selectedDate,
                  items: _timelineItems,
                  isLoading: _isTimelineLoading,
                  errorMessage: _timelineErrorMessage,
                  onRetry: () => _loadDayTimeline(_selectedDate),
                  onTapItem: _openTimelineItem,
                  onOpenDailyRecord: _openDailyRecordEntry,
                  onOpenDiary: _openDiaryPage,
                )
              else
                _MultiDayTimelineSection(
                  data: _multiDayData,
                  isLoading: _isRangeLoading,
                  errorMessage: _rangeErrorMessage,
                  onRetry: () =>
                      _loadMultiDayRange(_selectedRangeDays, force: true),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTimelineItem(LifeTimelineItem item) async {
    if (item.type == LifeTimelineType.diary) {
      await _openDiaryPage();
      return;
    }
    if (item.type == LifeTimelineType.dailyCheckIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => DailyCheckInPage(date: _selectedDate)),
      );
      await _refreshSelectedDay();
      return;
    }
    if (item.type == LifeTimelineType.medication) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RecordAdjustmentHistoryPage()),
      );
      await _refreshSelectedDay();
      return;
    }
    if (item.type == LifeTimelineType.emotion ||
        item.type == LifeTimelineType.symptom ||
        item.type == LifeTimelineType.sleep) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final sourceId = (item.sourceId ?? '').trim();
      if (uid == null || sourceId.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordDetailScreen(
            uid: uid,
            docId: sourceId,
            autoOpenEditor: false,
          ),
        ),
      );
      await _refreshSelectedDay();
    }
  }

  Future<void> _openDailyRecordEntry() async {
    final hasExistingRecord = _timelineItems.any(
      (item) =>
          item.type == LifeTimelineType.emotion ||
          item.type == LifeTimelineType.symptom ||
          item.type == LifeTimelineType.sleep ||
          item.type == LifeTimelineType.dailyCheckIn,
    );
    if (hasExistingRecord) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const DailyRecordHistory(initialTab: 0),
        ),
      );
      await _refreshSelectedDay();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailyCheckInPage(date: _selectedDate)),
    );
    await _refreshSelectedDay();
  }

  Future<void> _refreshSelectedDay() async {
    await Future.wait([
      _loadDayTimeline(_selectedDate),
      _loadMonthSummary(_focusedMonth, showLoading: false),
      if (_selectedRangeDays > 1)
        _loadMultiDayRange(_selectedRangeDays, force: true),
    ]);
  }

  Future<void> _openDiaryPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DiaryPageDemo(date: _selectedDate)),
    );
    await _refreshSelectedDay();
  }
}

class _AuthEmptyCard extends StatelessWidget {
  const _AuthEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 356,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDEFF1)),
      ),
      padding: const EdgeInsets.all(18),
      child: Center(
        child: Text(
          '目前尚未登入，請先登入後查看生活總覽。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B8D94),
                fontWeight: FontWeight.w600,
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _CalendarLoadingCard extends StatelessWidget {
  const _CalendarLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 356,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDEFF1)),
      ),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: Color(0xFF63AAB6),
          ),
        ),
      ),
    );
  }
}

class _CalendarErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CalendarErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 356,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDEFF1)),
      ),
      padding: const EdgeInsets.all(18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Color(0xFF82A8AF), size: 26),
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5A7B82),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                foregroundColor: const Color(0xFF2A6774),
              ),
              child: const Text('重新載入'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LifeOverviewLegend extends StatelessWidget {
  const _LifeOverviewLegend();

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF6F8F95),
          fontWeight: FontWeight.w600,
        );

    Widget item(Widget marker, String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          marker,
          const SizedBox(width: 4),
          Text(text, style: labelStyle),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 8,
      children: [
        item(
            const Text('●',
                style: TextStyle(color: Color(0xFFF2A8C3), fontSize: 12)),
            '生理期'),
        item(
            const Text('○',
                style: TextStyle(color: Color(0xFFE6A6C0), fontSize: 12)),
            '預測生理期'),
        item(const _LegendDot(color: Color(0xFFC9B6FF)), '日記'),
        item(const _LegendDot(color: Color(0xFF58B8C0)), '快速紀錄'),
        item(const _LegendDot(color: Color(0xFF4A90E2)), '每日 Check-in'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _TimelineRangeSelector extends StatelessWidget {
  const _TimelineRangeSelector({
    required this.selectedDays,
    required this.onSelected,
  });

  final int selectedDays;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in const [
            (1, '單日'),
            (7, '7 天'),
            (14, '14 天'),
            (30, '30 天')
          ])
            ChoiceChip(
              label: Text(option.$2),
              selected: selectedDays == option.$1,
              onSelected: (_) => onSelected(option.$1),
              selectedColor: const Color(0xFFDDF1F3),
              side: const BorderSide(color: Color(0xFFD1E6E9)),
              labelStyle: TextStyle(
                color: selectedDays == option.$1
                    ? const Color(0xFF2D6974)
                    : const Color(0xFF718D93),
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      );
}

class _MultiDayTimelineSection extends StatelessWidget {
  const _MultiDayTimelineSection({
    required this.data,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final _MultiDayViewData? data;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _RangeCard(child: _TimelineLoadingState());
    }
    if (errorMessage != null || data == null) {
      return _RangeCard(
        child: _TimelineErrorState(
          message: errorMessage ?? '多日生活軌跡暫時無法顯示。',
          onRetry: onRetry,
        ),
      );
    }
    final value = data!;
    final recordedEntries = value.range.itemsByDate.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList()
      ..sort((left, right) => right.key.compareTo(left.key));

    return Column(
      children: [
        _RangeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_shortDate(value.range.start)}－${_shortDate(value.range.end)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF2C6774),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                '有紀錄 ${value.range.recordedDayCount} 天',
                style: const TextStyle(
                  color: Color(0xFF78969C),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '多日軌跡',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF315F68),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              if (recordedEntries.isEmpty)
                const Text(
                  '這段期間還沒有留下生活紀錄。',
                  style: TextStyle(color: Color(0xFF718E94)),
                )
              else
                for (final entry in recordedEntries)
                  _CompactDaySummary(date: entry.key, items: entry.value),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _RangeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '重複出現的組合',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF315F68),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                '以下只整理同日或兩小時內重複出現的紀錄，可作為後續觀察線索，不代表因果關係。',
                style: TextStyle(
                  color: Color(0xFF78969C),
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              if (value.patterns.isEmpty)
                const Text(
                  '目前還沒有足夠的重複紀錄形成可觀察的共現模式。',
                  style: TextStyle(color: Color(0xFF718E94), height: 1.4),
                )
              else
                for (final pattern in value.patterns.take(5))
                  _CooccurrenceRow(pattern: pattern),
            ],
          ),
        ),
      ],
    );
  }
}

class _RangeCard extends StatelessWidget {
  const _RangeCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDCEEF1)),
        ),
        child: child,
      );
}

class _CompactDaySummary extends StatelessWidget {
  const _CompactDaySummary({required this.date, required this.items});

  final DateTime date;
  final List<LifeTimelineItem> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.where(_isMultiDayPrimaryItem).take(4).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              _shortDate(date),
              style: const TextStyle(
                color: Color(0xFF4F767E),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _timelineIcon(item.type),
                          size: 16,
                          color: const Color(0xFF65AEB8),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${item.title}｜${_timelineSummary(item)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF587A81),
                              height: 1.35,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (items.length > visible.length)
                  Text(
                    '另有 ${items.length - visible.length} 筆紀錄',
                    style: const TextStyle(
                      color: Color(0xFF91A6AA),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CooccurrenceRow extends StatelessWidget {
  const _CooccurrenceRow({required this.pattern});

  final CooccurrenceCluster pattern;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: _LegendDot(color: Color(0xFF65AEB8)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _cooccurrenceText(pattern),
                style: const TextStyle(
                  color: Color(0xFF587A81),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

class _MultiDayViewData {
  const _MultiDayViewData({required this.range, required this.patterns});

  final LifeTimelineRangeData range;
  final List<CooccurrenceCluster> patterns;
}

bool _isMultiDayPrimaryItem(LifeTimelineItem item) =>
    item.type != LifeTimelineType.diary;

String _cooccurrenceText(CooccurrenceCluster pattern) {
  final lines = <String>[
    pattern.coreItems.join('＋'),
    pattern.nearbyTimeCount > 0
        ? '重複出現 ${pattern.occurrenceCount} 次'
        : '同日重複出現 ${pattern.sameDayCount} 次',
  ];
  if (pattern.companionItems.isNotEmpty) {
    lines.add('常伴隨：${pattern.companionItems.join('、')}');
  }
  if (pattern.nearbyTimeCount > 0) {
    lines.add(
      '其中 ${pattern.nearbyTimeCount} 次在 ${pattern.windowMinutes ~/ 60} 小時內出現',
    );
  }
  return lines.join('\n');
}

String _shortDate(DateTime value) => '${value.month}/${value.day}';

class _DailyTimelineSection extends StatelessWidget {
  const _DailyTimelineSection({
    required this.date,
    required this.items,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.onTapItem,
    required this.onOpenDailyRecord,
    required this.onOpenDiary,
  });

  final DateTime date;
  final List<LifeTimelineItem> items;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<LifeTimelineItem> onTapItem;
  final VoidCallback onOpenDailyRecord;
  final VoidCallback onOpenDiary;

  @override
  Widget build(BuildContext context) {
    final hasDailyRecord = items.any(
      (item) =>
          item.type == LifeTimelineType.dailyCheckIn ||
          item.type == LifeTimelineType.emotion ||
          item.type == LifeTimelineType.symptom ||
          item.type == LifeTimelineType.sleep,
    );
    final hasDiary = items.any((item) => item.type == LifeTimelineType.diary);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCEEF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${date.month} 月 ${date.day} 日',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF2C6774),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '當日生活軌跡',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF78969C),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const _TimelineLoadingState()
          else if (errorMessage != null)
            _TimelineErrorState(message: errorMessage!, onRetry: onRetry)
          else if (items.isEmpty)
            const _TimelineEmptyState()
          else
            for (var index = 0; index < items.length; index++)
              _TimelineRow(
                item: items[index],
                isLast: index == items.length - 1,
                onTap: _isTimelineItemActionable(items[index])
                    ? () => onTapItem(items[index])
                    : null,
              ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenDailyRecord,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(hasDailyRecord ? '查看每日紀錄' : '新增每日紀錄'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenDiary,
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: Text(hasDiary ? '查看日記' : '補寫日記'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isTimelineItemActionable(LifeTimelineItem item) {
    if (item.type == LifeTimelineType.diary ||
        item.type == LifeTimelineType.dailyCheckIn ||
        item.type == LifeTimelineType.medication) {
      return true;
    }
    return (item.type == LifeTimelineType.emotion ||
            item.type == LifeTimelineType.symptom ||
            item.type == LifeTimelineType.sleep) &&
        (item.sourceId ?? '').trim().isNotEmpty;
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.item,
    required this.isLast,
    this.onTap,
  });

  final LifeTimelineItem item;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final precise = item.hasExplicitTime;
    final timeLabel = precise
        ? '${item.time.hour.toString().padLeft(2, '0')}:${item.time.minute.toString().padLeft(2, '0')}'
        : '當日紀錄';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 58,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                timeLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: precise
                          ? const Color(0xFF4E747C)
                          : const Color(0xFF91A6AA),
                      fontWeight: precise ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ),
          ),
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 15),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF65AEB8),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFFD5E8EA),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 2 : 10),
              child: Material(
                color: const Color(0xFFF7FBFC),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE1EFF1)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _timelineIcon(item.type),
                          size: 20,
                          color: const Color(0xFF4D929D),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF315F68),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  if (onTap != null)
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: Color(0xFF91AAAF),
                                    ),
                                ],
                              ),
                              if (_timelineSummary(item).isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _timelineSummary(item),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF5F7F86),
                                        height: 1.4,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineLoadingState extends StatelessWidget {
  const _TimelineLoadingState();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Color(0xFF63AAB6),
          ),
        ),
      );
}

class _TimelineErrorState extends StatelessWidget {
  const _TimelineErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          children: [
            Text(message, style: const TextStyle(color: Color(0xFF6F8F95))),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('重新載入')),
          ],
        ),
      );
}

class _TimelineEmptyState extends StatelessWidget {
  const _TimelineEmptyState();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FBFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1EFF1)),
        ),
        child: const Text(
          '這一天還沒有留下生活紀錄。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF718E94)),
        ),
      );
}

IconData _timelineIcon(String type) {
  switch (type) {
    case LifeTimelineType.quickRecord:
      return Icons.bolt_rounded;
    case LifeTimelineType.dailyCheckIn:
      return Icons.check_circle_rounded;
    case LifeTimelineType.emotion:
      return Icons.mood_rounded;
    case LifeTimelineType.symptom:
      return Icons.healing_rounded;
    case LifeTimelineType.sleep:
      return Icons.bedtime_rounded;
    case LifeTimelineType.diary:
      return Icons.menu_book_rounded;
    case LifeTimelineType.period:
      return Icons.water_drop_rounded;
    case LifeTimelineType.activity:
      return Icons.directions_walk_rounded;
    case LifeTimelineType.medication:
      return Icons.medication_rounded;
    case LifeTimelineType.subjectiveMedicationResponse:
      return Icons.monitor_heart_rounded;
    default:
      return Icons.circle_outlined;
  }
}

String _timelineSummary(LifeTimelineItem item) {
  if (item.type != LifeTimelineType.emotion) return item.summary;
  final metadata = item.metadata;
  final scale = metadata?['moodScale'];
  if (scale != 5 && scale != 10) return item.summary;

  final parts = <String>[];
  final emotions = metadata?['emotions'];
  if (emotions is Iterable) {
    for (final raw in emotions.whereType<Map>()) {
      final name = (raw['name'] ?? '').toString().trim();
      final value = raw['value'];
      if (name.isEmpty) continue;
      parts.add(value is num ? '$name ${_numberText(value)}/$scale' : name);
    }
  }
  final overallMood = metadata?['overallMood'];
  if (overallMood is num) {
    parts.add('整體情緒 ${_numberText(overallMood)}/$scale');
  }
  return parts.isEmpty ? item.summary : parts.join('、');
}

String _numberText(num value) => value.toDouble() == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}
