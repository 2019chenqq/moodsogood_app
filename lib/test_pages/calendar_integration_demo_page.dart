import 'package:flutter/material.dart';

import '../models/calendar_day_summary.dart';
import '../services/calendar_summary_service.dart';
import '../widgets/unified_calendar_widget.dart';

class CalendarIntegrationDemoPage extends StatefulWidget {
  const CalendarIntegrationDemoPage({super.key});

  @override
  State<CalendarIntegrationDemoPage> createState() => _CalendarIntegrationDemoPageState();
}

class _CalendarIntegrationDemoPageState extends State<CalendarIntegrationDemoPage> {
  final CalendarSummaryService _summaryService = CalendarSummaryService();

  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  Map<String, CalendarDaySummary> _summaries = <String, CalendarDaySummary>{};

  bool _isLoading = true;
  String? _errorMessage;
  int _loadToken = 0;

  UnifiedCalendarMode _mode = UnifiedCalendarMode.overview;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(now.year, now.month, 1);
    _loadMonthSummary(_focusedMonth, showLoading: true);
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
      debugPrint('[CalendarIntegrationDemoPage] load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summaries[_dateKey(_selectedDate)] ?? CalendarDaySummary.empty(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('月曆整合測試'),
      ),
      backgroundColor: const Color(0xFFF6FBFC),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            _buildModeTabs(context),
            const SizedBox(height: 14),
            if (_isLoading)
              const _CalendarLoadingCard()
            else if (_errorMessage != null)
              _CalendarErrorCard(
                message: _errorMessage!,
                onRetry: () => _loadMonthSummary(_focusedMonth, showLoading: true),
              )
            else
              UnifiedCalendarWidget(
                selectedDate: _selectedDate,
                focusedMonth: _focusedMonth,
                mode: _mode,
                summariesByDate: _summaries,
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
                },
              ),
            const SizedBox(height: 16),
            _SummaryCard(mode: _mode, summary: summary),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTabs(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9EAEE)),
      ),
      padding: const EdgeInsets.all(6),
      child: SegmentedButton<UnifiedCalendarMode>(
        showSelectedIcon: false,
        emptySelectionAllowed: false,
        multiSelectionEnabled: false,
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF7AB7C2).withValues(alpha: 0.2);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF2A6774);
            }
            return const Color(0xFF7F9AA0);
          }),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
          visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: const [
          ButtonSegment(value: UnifiedCalendarMode.diary, label: Text('日記模式')),
          ButtonSegment(value: UnifiedCalendarMode.record, label: Text('紀錄模式')),
          ButtonSegment(value: UnifiedCalendarMode.period, label: Text('生理期模式')),
          ButtonSegment(value: UnifiedCalendarMode.overview, label: Text('總覽模式')),
        ],
        selected: {_mode},
        onSelectionChanged: (selection) {
          final next = selection.first;
          if (next != _mode) {
            _safeSetState(() => _mode = next);
          }
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final UnifiedCalendarMode mode;
  final CalendarDaySummary summary;

  const _SummaryCard({required this.mode, required this.summary});

  @override
  Widget build(BuildContext context) {
    final title = switch (mode) {
      UnifiedCalendarMode.diary => '日記模式摘要',
      UnifiedCalendarMode.record => '紀錄模式摘要',
      UnifiedCalendarMode.period => '生理期模式摘要',
      UnifiedCalendarMode.overview => '總覽模式摘要',
    };

    final chips = _buildModeChips();
    final isEmptyDay = !_hasAnyData(summary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCEEF1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '日期：${summary.dateKey}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7D969C),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF2C6774),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (isEmptyDay)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD8EAED)),
              ),
              child: Text(
                '這一天還沒有留下紀錄',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B8D94),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            )
          else
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: chips,
            ),
          const SizedBox(height: 12),
          Text(
            summary.averageMood != null
                ? '整體情緒：${summary.averageMood!.toStringAsFixed(1)} / 10'
                : '整體情緒：尚無資料',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF4D7880),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildModeChips() {
    switch (mode) {
      case UnifiedCalendarMode.diary:
        return [
          _StatusChip(label: '有日記', active: summary.hasDiary, activeColor: const Color(0xFFC9B6FF)),
        ];
      case UnifiedCalendarMode.record:
        return [
          _StatusChip(label: '有每日紀錄', active: summary.hasDailyRecord, activeColor: const Color(0xFF4A90E2)),
          _StatusChip(label: '有情緒資料', active: summary.hasEmotionData, activeColor: const Color(0xFF58B8C0)),
          _StatusChip(label: '有症狀資料', active: summary.hasSymptomData, activeColor: const Color(0xFFF4B183)),
          _StatusChip(label: '有睡眠資料', active: summary.hasSleepData, activeColor: const Color(0xFF9AB3F5)),
        ];
      case UnifiedCalendarMode.period:
        return [
          _StatusChip(label: '生理期', active: summary.isPeriodDay, activeColor: const Color(0xFFFFBFD4)),
          _StatusChip(
            label: '預測生理期',
            active: summary.isPredictedPeriodDay,
            activeColor: const Color(0xFFFFDDEA),
          ),
        ];
      case UnifiedCalendarMode.overview:
        return [
          _StatusChip(label: '有日記', active: summary.hasDiary, activeColor: const Color(0xFFC9B6FF)),
          _StatusChip(label: '有每日紀錄', active: summary.hasDailyRecord, activeColor: const Color(0xFF4A90E2)),
          _StatusChip(label: '有情緒資料', active: summary.hasEmotionData, activeColor: const Color(0xFF58B8C0)),
          _StatusChip(label: '有症狀資料', active: summary.hasSymptomData, activeColor: const Color(0xFFF4B183)),
          _StatusChip(label: '有睡眠資料', active: summary.hasSleepData, activeColor: const Color(0xFF9AB3F5)),
          _StatusChip(label: '生理期', active: summary.isPeriodDay, activeColor: const Color(0xFFFFBFD4)),
          _StatusChip(
            label: '預測生理期',
            active: summary.isPredictedPeriodDay,
            activeColor: const Color(0xFFFFDDEA),
          ),
        ];
    }
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
            const Icon(Icons.cloud_off_rounded, color: Color(0xFF82A8AF), size: 26),
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

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;

  const _StatusChip({
    required this.label,
    required this.active,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.22) : const Color(0xFFF4F8F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? activeColor.withValues(alpha: 0.55) : const Color(0xFFDDE8EA),
        ),
      ),
      child: Text(
        active ? '$label：是' : '$label：否',
        style: TextStyle(
          color: active ? const Color(0xFF35545B) : const Color(0xFF839CA2),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

String _dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}

bool _hasAnyData(CalendarDaySummary s) {
  return s.hasDailyRecord ||
      s.hasDiary ||
      s.hasEmotionData ||
      s.hasSymptomData ||
      s.hasSleepData ||
      s.isPeriodDay ||
      s.isPredictedPeriodDay ||
      s.averageMood != null;
}
